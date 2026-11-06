# frozen_string_literal: true

require "lepus/saga/active_record"

module Lepus
  module Saga
    module Stores
      # Executions and step attempts as ActiveRecord rows. Locks are
      # SELECT ... FOR UPDATE inside a transaction (a no-op on SQLite, where
      # ActiveRecord 8 opens IMMEDIATE transactions that serialize writers
      # instead). Pass other model
      # classes to use subclasses with their own table names or connections.
      #
      # The query methods use portable SQL only (filters, GROUP BY, COUNT,
      # MAX), so they behave the same on SQLite, PostgreSQL and MySQL/MariaDB:
      # time buckets and percentiles are computed in Ruby over at most
      # `max_rows` plucked values.
      class ActiveRecord < Base
        def initialize(execution_class: nil, step_attempt_class: nil)
          super()
          @execution_class = execution_class
          @step_attempt_class = step_attempt_class
        end

        def execution_class
          @execution_class ||= Lepus::Saga::ActiveRecord::Execution
        end

        def step_attempt_class
          @step_attempt_class ||= Lepus::Saga::ActiveRecord::StepAttempt
        end

        def create_execution(attributes)
          execution_class.create!(attributes)
        end

        def find_execution(id)
          execution_class.find_by(id: id)
        end

        def save_execution(execution)
          execution.save!
          execution
        end

        def with_lock(execution)
          execution.with_lock { yield execution }
        end

        def with_locked_execution(id)
          execution_class.transaction do
            yield execution_class.lock.find_by(id: id)
          end
        end

        def increment_resume_count(execution)
          execution_class.update_counters(execution.id, resume_count: 1, touch: true)
          execution.resume_count = execution_class.where(id: execution.id).pick(:resume_count)
          execution.clear_attribute_changes(%i[resume_count])
          execution.resume_count
        end

        def stalled_executions(before:)
          execution_class.in_progress.where(last_progress_at: ...before).order(:last_progress_at)
        end

        def executions_for_resource(resource_type, resource_id)
          execution_class.for_resource(resource_type, resource_id).recent_first
        end

        def create_step_attempt(execution, attributes)
          step_attempt_class.create!(attributes.merge(saga_execution_id: execution.id))
        rescue ::ActiveRecord::RecordNotUnique => error
          raise DuplicateAttemptError, error.message
        end

        def save_step_attempt(attempt)
          attempt.save!
          attempt
        end

        def step_attempts(execution)
          attempts_of(execution).chronological
        end

        def count_step_attempts(execution, step_name:, direction:, epoch:)
          attempts_of(execution).where(step_name: step_name, direction: direction, epoch: epoch).count
        end

        def running_step_attempt?(execution, step_name:, direction:, epoch:, started_since:)
          attempts_of(execution)
            .where(step_name: step_name, direction: direction, epoch: epoch, status: "running")
            .exists?(started_at: started_since..)
        end

        def stale_step_attempts(execution, step_name:, direction:, epoch:, started_before:)
          attempts_of(execution)
            .where(step_name: step_name, direction: direction, epoch: epoch, status: "running", started_at: ...started_before)
        end

        def step_succeeded?(execution, step_name)
          attempts_of(execution).exists?(step_name: step_name, direction: "execute", status: "succeeded")
        end

        def queries? = true

        def list_executions(before_id: nil, limit: 50, **filters)
          scope = matching_executions(**filters)
          scope = scope.where(id: ...before_id) if before_id
          scope.order(id: :desc).limit(limit).to_a
        end

        def count_executions(group_by:, **filters)
          keys = group_keys(group_by)
          columns = keys.include?(:partition) ? keys | [:saga_name] : keys
          counts = matching_executions(**filters).group(*columns).count
          rows = counts.map { |values, count| [columns.zip((columns.size == 1) ? [values] : values).to_h, count] }
          tally_groups(rows, group_by)
        end

        def execution_series(from:, to:, bucket:, saga_name: nil, max_rows: QUERY_MAX_ROWS)
          seconds = series_bucket(from, to, bucket)
          scope = matching_executions(saga_name: saga_name)
          started, started_truncated = take_rows(
            scope.where(created_at: from...to).order(created_at: :desc).limit(max_rows + 1).pluck(:created_at),
            max_rows
          )
          finished, finished_truncated = take_rows(
            scope.where(status: ExecutionBehaviour::TERMINAL_STATUSES, finished_at: from...to)
              .order(finished_at: :desc).limit(max_rows + 1).pluck(:finished_at, :status),
            max_rows
          )
          {rows: build_series(from, to, seconds, started, finished), truncated: started_truncated || finished_truncated}
        end

        def step_latency(from:, to:, saga_name: nil, max_rows: QUERY_MAX_ROWS)
          attempts = step_attempt_class.arel_table
          samples, truncated = take_rows(
            attempts_with_saga(from, to, saga_name)
              .where(status: LATENCY_STATUSES).where.not(duration_ms: nil)
              .order(attempts[:started_at].desc).limit(max_rows + 1)
              .pluck(execution_class.arel_table[:saga_name], attempts[:step_name], attempts[:direction], attempts[:duration_ms]),
            max_rows
          )
          {rows: latency_rows(samples), truncated: truncated}
        end

        def failure_summary(from:, to:, saga_name: nil, limit: 20)
          attempts = step_attempt_class.arel_table
          saga = execution_class.arel_table[:saga_name]
          failed = attempts_with_saga(from, to, saga_name).where(status: "failed")
          failed
            .group(attempts[:error_class], saga, attempts[:step_name])
            .order(Arel::Nodes::Descending.new(Arel.star.count), Arel::Nodes::Descending.new(attempts[:finished_at].maximum))
            .limit(limit)
            .pluck(attempts[:error_class], saga, attempts[:step_name], Arel.star.count)
            .map do |error_class, group_saga, step_name, count|
              message, last_seen_at, execution_id = failed
                .where(error_class: error_class, step_name: step_name).where(saga.eq(group_saga))
                .order(attempts[:finished_at].desc, attempts[:id].desc)
                .pick(attempts[:error_message], attempts[:finished_at], attempts[:saga_execution_id])
              {
                error_class: error_class, saga_name: group_saga, step_name: step_name, count: count,
                last_seen_at: last_seen_at, sample_message: message, sample_execution_id: execution_id
              }
            end
        end

        def saga_names
          execution_class.distinct.order(:saga_name).pluck(:saga_name)
        end

        private

        def attempts_of(execution)
          step_attempt_class.where(saga_execution_id: execution.id)
        end

        def matching_executions(saga_name: nil, status: nil, current_step: nil, partition: nil, resource: nil, from: nil, to: nil)
          sagas = filter_values(saga_name)
          statuses = filter_values(status)
          steps = filter_values(current_step)
          scope = execution_class.all
          scope = scope.where(saga_name: sagas) if sagas
          scope = scope.where(status: statuses) if statuses
          scope = scope.where(current_step: steps) if steps
          scope = scope.where(created_at: from..) if from
          scope = scope.where(created_at: ...to) if to
          scope = scope.and(in_partition(partition.to_s)) if partition.present?
          scope = scope.and(matching_resource(resource.to_s.downcase)) if resource.present?
          scope
        end

        def in_partition(partition)
          execution_class.where(partition: partition)
            .or(execution_class.where(partition: nil, saga_name: partition_saga_names(partition)))
        end

        def matching_resource(needle)
          execution_class.where(
            "LOWER(resource_type) LIKE :pattern ESCAPE '!' OR LOWER(resource_id) LIKE :pattern ESCAPE '!'",
            pattern: "%#{execution_class.sanitize_sql_like(needle, "!")}%"
          )
        end

        # Attempts started in the window, joined to their execution.
        def attempts_with_saga(from, to, saga_name)
          attempts = step_attempt_class.arel_table
          executions = execution_class.arel_table
          scope = step_attempt_class
            .joins(attempts.join(executions).on(executions[:id].eq(attempts[:saga_execution_id])).join_sources)
            .where(started_at: from...to)
          sagas = filter_values(saga_name)
          sagas ? scope.where(executions[:saga_name].in(sagas)) : scope
        end
      end
    end
  end
end
