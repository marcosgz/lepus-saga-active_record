# frozen_string_literal: true

module Lepus
  module Saga
    module ActiveRecord
      class StepAttempt < Record
        include StepAttemptBehaviour

        self.table_name = "saga_step_attempts"

        attribute :context_after, :json, default: -> { {} }

        # The foreign key guards the reference; validating it would load the
        # execution again on every attempt the executor opens under the lock.
        belongs_to :execution,
          class_name: "Lepus::Saga::ActiveRecord::Execution",
          foreign_key: :saga_execution_id,
          inverse_of: :step_attempts,
          optional: true

        before_create { self.id ||= SecureRandom.uuid_v7 }

        validates :step_name, presence: true
        validates :status, inclusion: {in: STATUSES}

        scope :chronological, -> { order(:started_at, :created_at) }
      end
    end
  end
end
