# frozen_string_literal: true

# Tables created before the generator may carry a lock_version column. With optimistic locking on, a write from a stale copy would raise
# ActiveRecord::StaleObjectError.
RSpec.describe "Tables with a lock_version column" do
  let(:store) { Lepus::Saga::Stores::ActiveRecord.new }
  let(:execution_class) { Lepus::Saga::ActiveRecord::Execution }

  before(:context) do
    ActiveRecord::Migration.suppress_messages do
      ActiveRecord::Migration.add_column :saga_executions, :lock_version, :integer, null: false, default: 0
    end
    Database.reset_models!
  end

  after(:context) do
    ActiveRecord::Migration.suppress_messages do
      ActiveRecord::Migration.remove_column :saga_executions, :lock_version
    end
    Database.reset_models!
  end

  def create_execution
    store.create_execution(
      saga_name: "legacy.spec", resource_type: "Resource", resource_id: "1",
      current_step: "first", started_at: Time.current, last_progress_at: 1.hour.ago
    )
  end

  it "does not lock optimistically" do
    expect(execution_class.locking_enabled?).to be(false)
  end

  it "lets a stale copy write" do
    stale = create_execution
    store.update_execution(execution_class.find(stale.id), status: "failed")

    expect { store.update_execution(stale, current_step: "second") }.not_to raise_error
  end

  it "increments resume_count from a stale copy" do
    stale = create_execution
    store.update_execution(execution_class.find(stale.id), resume_count: 2)

    expect(store.increment_resume_count(stale)).to eq(3)
  end

  it_behaves_like "a lepus saga engine"
end
