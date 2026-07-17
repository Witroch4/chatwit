require 'rails_helper'

# rubocop:disable RSpec/MultipleExpectations

RSpec.describe Captain::PaymentReview::WakeService do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

  before do
    create(:captain_inbox, inbox: inbox, captain_assistant: assistant, mode: :phase2_only)
  end

  def eligible_trigger(generation:, message_id: nil, key: nil)
    create(:captain_payment_review_trigger,
           conversation: conversation, state: :eligible, generation: generation,
           trigger_message_id: message_id,
           event_key: key || "captain-payment-review:#{conversation.id}:#{generation}")
  end

  it 'claims the current eligible unclaimed trigger into a queued run' do
    trigger = eligible_trigger(generation: 1, message_id: 42)

    expect { described_class.new(conversation).call }.to have_enqueued_job(Captain::PaymentReviewJob)

    run = Captain::PaymentReviewRun.find_by(conversation_id: conversation.id)
    expect(run).to be_present
    expect(run).to be_queued
    expect(run.generation).to eq(1)
    expect(run.trigger_key).to eq(trigger.event_key)
    expect(run.trigger_message_id).to eq(42)
    expect(run.captain_assistant_id).to eq(assistant.id)
    expect(trigger.reload).to be_claimed
    expect(trigger.run_id).to eq(run.id)
  end

  it 'creates exactly one run for duplicate nudges of the same trigger' do
    eligible_trigger(generation: 1)

    described_class.new(conversation).call
    described_class.new(conversation).call

    expect(Captain::PaymentReviewRun.where(conversation_id: conversation.id).count).to eq(1)
  end

  it 'claims only the newest present generation after a remove+add' do
    old = eligible_trigger(generation: 1, key: 'old-gen')
    old.update!(state: :cancelled, deactivated_at: Time.current)
    newest = eligible_trigger(generation: 2, key: 'new-gen')

    described_class.new(conversation).call

    run = Captain::PaymentReviewRun.find_by(conversation_id: conversation.id)
    expect(run.generation).to eq(2)
    expect(run.trigger_key).to eq(newest.event_key)
    expect(old.reload).to be_cancelled
  end

  it 'never claims an ineligible trigger' do
    create(:captain_payment_review_trigger, conversation: conversation, state: :ineligible, generation: 1)

    result = described_class.new(conversation).call

    expect(result).to be_nil
    expect(Captain::PaymentReviewRun.where(conversation_id: conversation.id)).to be_empty
  end

  it 'records a pending successor instead of a second run while one is active' do
    gen1 = eligible_trigger(generation: 1, key: 'gen-1')
    described_class.new(conversation).call
    active = Captain::PaymentReviewRun.find_by(conversation_id: conversation.id)
    active.update!(status: :running, execution_token: SecureRandom.uuid, lease_expires_at: 2.minutes.from_now)

    # Remove+add during the run: the old generation is deactivated before the new one appears.
    gen1.update!(state: :cancelled, deactivated_at: Time.current)
    successor_trigger = eligible_trigger(generation: 2, key: 'gen-2')
    described_class.new(conversation).call

    expect(Captain::PaymentReviewRun.where(conversation_id: conversation.id).count).to eq(1)
    expect(active.reload.pending_trigger_key).to eq(successor_trigger.event_key)
  end

  it 'promotes the pending generation to a successor run once the active run is terminal' do
    gen1 = eligible_trigger(generation: 1, key: 'gen-1')
    described_class.new(conversation).call
    active = Captain::PaymentReviewRun.find_by(conversation_id: conversation.id)
    active.update!(status: :completed, outcome: :replied, completed_at: Time.current)
    gen1.update!(state: :consumed, deactivated_at: Time.current)

    eligible_trigger(generation: 2, key: 'gen-2')
    described_class.new(conversation).call

    runs = Captain::PaymentReviewRun.where(conversation_id: conversation.id).order(:generation)
    expect(runs.count).to eq(2)
    expect(runs.last.generation).to eq(2)
    expect(runs.last).to be_queued
  end
end
# rubocop:enable RSpec/MultipleExpectations
