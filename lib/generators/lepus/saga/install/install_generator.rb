# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record"

module Lepus
  module Saga
    class InstallGenerator < Rails::Generators::Base
      include ::ActiveRecord::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      desc "Creates the migration for the saga_executions and saga_step_attempts tables"

      def create_migration_file
        migration_template "create_lepus_saga_tables.rb.erb", File.join(db_migrate_path, "create_lepus_saga_tables.rb")
      end

      private

      def migration_version
        "[#{::ActiveRecord::VERSION::MAJOR}.#{::ActiveRecord::VERSION::MINOR}]"
      end
    end
  end
end
