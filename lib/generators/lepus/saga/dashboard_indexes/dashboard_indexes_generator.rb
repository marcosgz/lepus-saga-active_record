# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record"

module Lepus
  module Saga
    class DashboardIndexesGenerator < Rails::Generators::Base
      include ::ActiveRecord::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      desc "Adds the indexes the store's query methods use to saga tables created before they were in lepus:saga:install"

      def create_migration_file
        migration_template "add_lepus_saga_dashboard_indexes.rb.erb", File.join(db_migrate_path, "add_lepus_saga_dashboard_indexes.rb")
      end

      private

      def migration_version
        "[#{::ActiveRecord::VERSION::MAJOR}.#{::ActiveRecord::VERSION::MINOR}]"
      end
    end
  end
end
