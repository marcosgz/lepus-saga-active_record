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

        private

        def attempts_of(execution)
          step_attempt_class.where(saga_execution_id: execution.id)
        end
      end
    end
  end
end
