# frozen_string_literal: true

module Lepus
  module Saga
    module ActiveRecord
      class Execution < Record
        include ExecutionBehaviour

        self.table_name = "saga_executions"
        # Concurrency is the row lock plus the epoch fence. A legacy
        # lock_version column would otherwise turn every write made outside
        # the lock into a possible StaleObjectError.
        self.lock_optimistically = false

        attribute :context, :json, default: -> { {} }
        attribute :last_progress_at, :datetime, default: -> { Time.current }

        has_many :step_attempts,
          class_name: "Lepus::Saga::ActiveRecord::StepAttempt",
          foreign_key: :saga_execution_id,
          inverse_of: :execution,
          dependent: :delete_all

        before_create { self.id ||= SecureRandom.uuid_v7 }

        validates :saga_name, :resource_type, :resource_id, presence: true
        validates :status, inclusion: {in: STATUSES}
        validates :direction, inclusion: {in: DIRECTIONS}

        scope :for_resource, ->(type, id) { where(resource_type: type, resource_id: id) }
        scope :in_progress, -> { where(status: IN_PROGRESS_STATUSES) }
        scope :completed, -> { where(status: "completed") }
        scope :recent_first, -> { order(started_at: :desc, id: :desc) }
        # Deliberately not `updated_at`: a re-publish, a lock or an attempt
        # opened and abandoned all touch the row while the cursor stands
        # still, so a wedged execution would keep resetting its own stall clock.
        scope :stalled, ->(older_than = 15.minutes) { in_progress.where(last_progress_at: ...older_than.ago) }

        # Deletes completed executions that finished before the cutoff, with
        # their step attempts, batch by batch. Call it on a relation to keep
        # some: `where.not(id: ids_to_keep).prune(finished_before: 30.days.ago)`.
        # Returns the number of executions deleted.
        def self.prune(finished_before:, batch_size: 1_000)
          step_attempt_class = reflect_on_association(:step_attempts).klass
          completed.where(finished_at: ...finished_before).in_batches(of: batch_size).sum do |batch|
            ids = batch.pluck(:id)
            transaction do
              step_attempt_class.where(saga_execution_id: ids).delete_all
              unscoped.where(id: ids).delete_all
            end
          end
        end

        def attempts_for_current_step
          step_attempts.where(current_step_scope)
        end
      end
    end
  end
end
