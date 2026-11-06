# frozen_string_literal: true

require "erb"

module Database
  TEMPLATE = File.expand_path("../../lib/generators/lepus/saga/install/templates/create_lepus_saga_tables.rb.erb", __dir__)
  SQLITE_PATH = File.expand_path("../../tmp/lepus_saga_test.sqlite3", __dir__)

  module_function

  # SQLite runs from a file rather than :memory: so the threaded examples share
  # one database across connections.
  def connect!
    if ENV["DATABASE_URL"]
      ActiveRecord::Base.establish_connection(url: ENV["DATABASE_URL"], pool: 10)
    else
      FileUtils.mkdir_p(File.dirname(SQLITE_PATH))
      FileUtils.rm_f(Dir["#{SQLITE_PATH}*"])
      ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: SQLITE_PATH, pool: 10, timeout: 10_000)
    end
  end

  def sqlite? = ActiveRecord::Base.connection_db_config.adapter == "sqlite3"

  def load_schema!
    ActiveRecord::Migration.suppress_messages do
      ActiveRecord::Schema.define do
        drop_table :saga_step_attempts, if_exists: true
        drop_table :saga_executions, if_exists: true
      end
      install_migration.migrate(:up)
    end
    reset_models!
  end

  def install_migration
    migration_version = "[#{ActiveRecord::VERSION::MAJOR}.#{ActiveRecord::VERSION::MINOR}]"
    source = ERB.new(File.read(TEMPLATE)).result_with_hash(migration_version: migration_version)
    Module.new.module_eval(source + "\nCreateLepusSagaTables", TEMPLATE)
  end

  def reset_models!
    [Lepus::Saga::ActiveRecord::Execution, Lepus::Saga::ActiveRecord::StepAttempt].each(&:reset_column_information)
  end

  def clean!
    Lepus::Saga::ActiveRecord::StepAttempt.delete_all
    Lepus::Saga::ActiveRecord::Execution.delete_all
  end
end
