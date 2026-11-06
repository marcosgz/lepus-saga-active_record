# frozen_string_literal: true

RSpec.describe Lepus::Saga::ActiveRecord::StepAttempt do
  let(:execution) do
    Lepus::Saga::ActiveRecord::Execution.create!(
      saga_name: "orders.checkout", resource_type: "Order", resource_id: "1",
      current_step: "first", started_at: Time.current
    )
  end

  it "includes the step attempt behaviour" do
    expect(described_class.include?(Lepus::Saga::StepAttemptBehaviour)).to be(true)
  end

  it "generates a uuid v7 id and defaults context_after" do
    attempt = execution.step_attempts.create!(step_name: "first", attempt: 1, started_at: Time.current).reload

    expect(attempt.id).to match(/\A\h{8}-\h{4}-7\h{3}-\h{4}-\h{12}\z/)
    expect(attempt).to have_attributes(context_after: {}, status: "running", direction: "execute", epoch: 0)
    expect(attempt.execution).to eq(execution)
  end

  it "validates step name and status" do
    attempt = described_class.new(status: "nope")

    expect(attempt).not_to be_valid
    expect(attempt.errors.attribute_names).to contain_exactly(:step_name, :status)
  end

  it "orders chronologically" do
    later = execution.step_attempts.create!(step_name: "second", attempt: 1, started_at: 1.minute.ago)
    earlier = execution.step_attempts.create!(step_name: "first", attempt: 1, started_at: 2.minutes.ago)

    expect(execution.step_attempts.chronological).to eq([earlier, later])
  end
end
