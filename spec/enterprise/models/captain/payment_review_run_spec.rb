require 'rails_helper'

RSpec.describe Captain::PaymentReviewRun do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }

  it 'builds a valid queued run from the factory' do
    run = build(:captain_payment_review_run, conversation: conversation)

    expect(run).to be_valid
    expect(run).to be_queued
  end

  it 'requires a unique trigger_key' do
    create(:captain_payment_review_run, conversation: conversation, trigger_key: 'dup-key')
    duplicate = build(:captain_payment_review_run, conversation: create(:conversation, account: account), trigger_key: 'dup-key')

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:trigger_key]).to be_present
  end

  it 'rejects a second active run for the same conversation and label' do
    create(:captain_payment_review_run, conversation: conversation, status: :running)
    second = build(:captain_payment_review_run, conversation: conversation, status: :queued)

    expect(second).not_to be_valid
    expect(second.errors[:base]).to be_present
  end

  it 'allows a new run once the previous one is terminal' do
    create(:captain_payment_review_run, conversation: conversation, status: :completed, outcome: :replied)
    successor = build(:captain_payment_review_run, conversation: conversation, status: :queued)

    expect(successor).to be_valid
  end

  it 'enforces the active-run uniqueness at the database level' do
    create(:captain_payment_review_run, conversation: conversation, status: :running)

    expect do
      described_class.new(
        account: account, conversation: conversation,
        trigger_label: Captain::PaymentReviewTrigger::CANONICAL_LABEL,
        trigger_key: 'race-key', generation: 99, triggered_at: Time.current, status: :queued
      ).save!(validate: false)
    end.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'rejects an assistant from another account' do
    foreign_assistant = create(:captain_assistant, account: create(:account))
    run = build(:captain_payment_review_run, conversation: conversation, captain_assistant: foreign_assistant)

    expect(run).not_to be_valid
    expect(run.errors[:captain_assistant_id]).to be_present
  end

  it 'freezes the trigger identity after creation' do
    run = create(:captain_payment_review_run, conversation: conversation, generation: 3)

    run.update(generation: 9)

    expect(run.reload.generation).to eq(3)
  end

  it 'links the claimed trigger through run_id' do
    run = create(:captain_payment_review_run, conversation: conversation)
    trigger = create(:captain_payment_review_trigger, conversation: conversation, state: :claimed, run: run)

    expect(run.reload.trigger).to eq(trigger)
  end

  describe '#lease_held_by?' do
    it 'is true only for a running run with a matching unexpired token' do
      token = SecureRandom.uuid
      run = create(:captain_payment_review_run, conversation: conversation, status: :running,
                                                execution_token: token, lease_expires_at: 2.minutes.from_now)

      expect(run.lease_held_by?(token)).to be(true)
      expect(run.lease_held_by?(SecureRandom.uuid)).to be(false)
    end

    it 'is false once the lease has expired' do
      token = SecureRandom.uuid
      run = create(:captain_payment_review_run, conversation: conversation, status: :running,
                                                execution_token: token, lease_expires_at: 1.minute.ago)

      expect(run.lease_held_by?(token)).to be(false)
    end
  end
end
