# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "generators/lepus/saga/dashboard_indexes/dashboard_indexes_generator"

RSpec.describe "lepus:saga:dashboard_indexes generator" do
  let(:destination) { Dir.mktmpdir }
  let(:connection) { ActiveRecord::Base.connection }
  let(:indexes) do
    {
      saga_executions: [%w[saga_name created_at], %w[status created_at], %w[finished_at]],
      saga_step_attempts: [%w[started_at], %w[error_class started_at]]
    }
  end

  after { FileUtils.rm_rf(destination) }

  def generated_migration_path
    Lepus::Saga::DashboardIndexesGenerator.start(["--quiet"], destination_root: destination)
    migrations = Dir[File.join(destination, "db/migrate/*_add_lepus_saga_dashboard_indexes.rb")]
    expect(migrations.size).to eq(1)
    migrations.first
  end

  def generated_migration = File.read(generated_migration_path)

  def migration
    namespace = Module.new
    load(generated_migration_path, namespace)
    namespace::AddLepusSagaDashboardIndexes
  end

  def migrate(direction)
    ActiveRecord::Migration.suppress_messages { migration.migrate(direction) }
  end

  def present_indexes
    indexes.to_h { |table, columns| [table, columns.select { |column| connection.index_exists?(table, column) }] }
  end

  it "is found under the lepus:saga:dashboard_indexes namespace" do
    expect(Rails::Generators.find_by_namespace("lepus:saga:dashboard_indexes")).to eq(Lepus::Saga::DashboardIndexesGenerator)
  end

  it "writes a versioned migration" do
    expect(generated_migration).to include(
      "class AddLepusSagaDashboardIndexes < ActiveRecord::Migration[#{ActiveRecord::VERSION::MAJOR}.#{ActiveRecord::VERSION::MINOR}]"
    )
  end

  it "adds the indexes the install migration creates to tables without them" do
    expect(present_indexes).to eq(indexes)

    migrate(:down)
    expect(present_indexes).to eq(saga_executions: [], saga_step_attempts: [])

    migrate(:up)
    expect(present_indexes).to eq(indexes)
  ensure
    migrate(:up)
  end

  it "skips indexes that already exist" do
    expect { migrate(:up) }.not_to raise_error
    expect(present_indexes).to eq(indexes)
  end
end
