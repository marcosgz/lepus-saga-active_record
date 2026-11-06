# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "generators/lepus/saga/install/install_generator"

RSpec.describe "lepus:saga:install generator" do
  let(:destination) { Dir.mktmpdir }

  after { FileUtils.rm_rf(destination) }

  def generated_migration
    Lepus::Saga::InstallGenerator.start(["--quiet"], destination_root: destination)
    migrations = Dir[File.join(destination, "db/migrate/*_create_lepus_saga_tables.rb")]
    expect(migrations.size).to eq(1)
    File.read(migrations.first)
  end

  it "is found under the lepus:saga:install namespace" do
    expect(Rails::Generators.find_by_namespace("lepus:saga:install")).to eq(Lepus::Saga::InstallGenerator)
  end

  it "writes one migration creating both saga tables" do
    source = generated_migration

    expect(source).to include("class CreateLepusSagaTables < ActiveRecord::Migration[#{ActiveRecord::VERSION::MAJOR}.#{ActiveRecord::VERSION::MINOR}]")
    expect(source).to include("create_table :saga_executions, id: :string, limit: 36")
    expect(source).to include("create_table :saga_step_attempts, id: :string, limit: 36")
    expect(source).to include('name: "idx_saga_step_attempts_dedup"')
  end

  it "indexes the columns the store's query methods filter on" do
    source = generated_migration

    expect(source).to include("add_index :saga_executions, [:started_at, :id]")
    expect(source).to include("add_index :saga_executions, [:duration_ms, :id]")
    expect(source).to include("add_index :saga_executions, [:saga_name, :started_at]")
    expect(source).to include("add_index :saga_executions, [:status, :started_at]")
    expect(source).to include("add_index :saga_executions, :finished_at")
    expect(source).not_to include(":created_at]")
    expect(source).to include("add_index :saga_step_attempts, :started_at")
    expect(source).to include("add_index :saga_step_attempts, [:error_class, :started_at]")
  end

  it "stores the duration as a bigint" do
    expect(generated_migration).to match(/t\.bigint\s+:duration_ms/)
  end

  it "stores the failure reason as text" do
    expect(generated_migration).to match(/t\.text\s+:failure_reason/)
  end

  it "has no lock_version column" do
    expect(generated_migration).not_to include("lock_version")
  end
end
