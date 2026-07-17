require 'rails_helper'

RSpec.describe Integrations::SocialwiseFlow::OwnershipGuard do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }

  def active_run
    create(:captain_payment_review_run, conversation: conversation, status: :running,
                                        trigger_label: Captain::PaymentReviewTrigger::CANONICAL_LABEL,
                                        execution_token: SecureRandom.uuid, lease_expires_at: 2.minutes.from_now)
  end

  it 'keeps the fence while a queued/running run exists even without the label' do
    guard = described_class.new(conversation)
    epoch = guard.snapshot_epoch
    expect(guard.socialwise_owned?).to be(true)

    active_run

    expect(described_class.new(conversation).socialwise_owned?).to be(false)
    expect(described_class.new(conversation).can_publish?(epoch: epoch)).to be(false)
  end

  it 'returns ownership to socialwise once the run is terminal' do
    create(:captain_payment_review_run, conversation: conversation, status: :completed, outcome: :replied,
                                        trigger_label: Captain::PaymentReviewTrigger::CANONICAL_LABEL,
                                        completed_at: Time.current)

    expect(described_class.new(conversation).socialwise_owned?).to be(true)
  end
end
