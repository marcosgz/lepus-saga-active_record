# frozen_string_literal: true

module Lepus
  module Saga
    module ActiveRecord
      # Abstract parent of the saga models, so an app can point them at another
      # database with `connects_to` without touching its own models.
      class Record < ::ActiveRecord::Base
        self.abstract_class = true
      end
    end
  end
end
