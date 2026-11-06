# frozen_string_literal: true

RSpec.describe Lepus::Saga::ActiveRecord::Execution do
  def create_execution(**attributes)
    described_class.create!({
      saga_name: "orders.checkout", resource_type: "Order", resource_id: "1",
      current_step: "first", started_at: Time.current
    }.merge(attributes))
  end

  it "includes the execution behaviour" do
    expect(described_class.include?(Lepus::Saga::ExecutionBehaviour)).to be(true)
    expect(described_class::STATUSES).to eq(Lepus::Saga::ExecutionBehaviour::STATUSES)
  end

  it "generates a uuid v7 id" do
    expect(create_execution.id).to match(/\A\h{8}-\h{4}-7\h{3}-\h{4}-\h{12}\z/)
  end

  it "defaults context, progress clock and counters" do
    execution = create_execution.reload

    expect(execution).to have_attributes(context: {}, status: "running", direction: "execute", epoch: 0, resume_count: 0)
    expect(execution.last_progress_at).to be_within(1).of(Time.current)
  end

  it "validates presence, status and direction" do
    execution = described_class.new(status: "nope", direction: "sideways")

    expect(execution).not_to be_valid
    expect(execution.errors.attribute_names).to include(:saga_name, :resource_type, :resource_id, :status, :direction)
  end

  it "stores a long failure reason" do
    execution = create_execution(failure_reason: "x" * 5000)

    expect(execution.reload.failure_reason.size).to eq(5000)
  end

  it "has read scopes" do
    completed = create_execution(status: "completed", resource_id: "2")
    running = create_execution(last_progress_at: 1.hour.ago)
    compensating = create_execution(status: "compensating", direction: "compensate")

    expect(described_class.for_resource("Order", "2")).to eq([completed])
    expect(described_class.in_progress).to contain_exactly(running, compensating)
    expect(described_class.completed).to eq([completed])
    expect(described_class.recent_first.first).to eq(compensating)
    expect(described_class.stalled(15.minutes)).to eq([running])
  end

  it "deletes its step attempts with it" do
    execution = create_execution
    execution.step_attempts.create!(step_name: "first", attempt: 1, started_at: Time.current)

    expect { execution.destroy }.to change(Lepus::Saga::ActiveRecord::StepAttempt, :count).by(-1)
  end

  describe ".prune" do
    def finished_execution(status: "completed", finished_at: 2.days.ago)
      create_execution(status: status, finished_at: finished_at).tap do |execution|
        execution.step_attempts.create!(step_name: "first", attempt: 1, started_at: finished_at)
      end
    end

    it "deletes completed executions finished before the cutoff with their attempts" do
      old = Array.new(3) { finished_execution }
      recent = finished_execution(finished_at: 1.minute.ago)
      failed = finished_execution(status: "failed")
      running = create_execution

      expect(described_class.prune(finished_before: 1.day.ago, batch_size: 2)).to eq(3)
      expect(described_class.all).to contain_exactly(recent, failed, running)
      expect(Lepus::Saga::ActiveRecord::StepAttempt.where(saga_execution_id: old.map(&:id))).to be_empty
      expect(Lepus::Saga::ActiveRecord::StepAttempt.count).to eq(2)
    end

    it "keeps what the calling relation leaves out" do
      kept = finished_execution
      finished_execution

      expect(described_class.where.not(id: kept.id).prune(finished_before: 1.day.ago)).to eq(1)
      expect(described_class.all).to eq([kept])
    end
  end

  it "scopes the attempts of the current step" do
    execution = create_execution
    current = execution.step_attempts.create!(step_name: "first", attempt: 1, started_at: Time.current)
    execution.step_attempts.create!(step_name: "first", epoch: 1, attempt: 1, started_at: Time.current)
    execution.step_attempts.create!(step_name: "second", attempt: 1, started_at: Time.current)

    expect(execution.attempts_for_current_step).to eq([current])
  end
end
