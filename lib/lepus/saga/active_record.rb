# frozen_string_literal: true

require "lepus/saga"
require "active_record"
require_relative "active_record/version"

module Lepus
  module Saga
    # ActiveRecord models for the saga tables. Select the store with
    #
    #   Lepus::Saga.configure { |config| config.store = :active_record }
    module ActiveRecord
      autoload :Record, "lepus/saga/active_record/record"
      autoload :Execution, "lepus/saga/active_record/execution"
      autoload :StepAttempt, "lepus/saga/active_record/step_attempt"
    end
  end
end

require_relative "stores/active_record"
