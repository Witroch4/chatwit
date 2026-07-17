require 'rails_helper'

# rubocop:disable Rails/SkipsModelValidations

RSpec.describe Captain::PaymentReview::LeaseService do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:run) { create(:captain_payment_review_run, conversation: conversation, status: :queued) }

  describe '#acquire!' do
    it 'claims a queued run and returns a fresh token' do
      token = described_class.new(run).acquire!

      expect(token).to be_present
      run.reload
      expect(run).to be_running
      expect(run.execution_token).to eq(token)
      expect(run.lease_expires_at).to be_future
      expect(run.started_at).to be_present
    end

    it 'refuses to steal a running run whose lease is still valid' do
      first = described_class.new(run).acquire!
      expect(first).to be_present

      second = described_class.new(run.reload).acquire!

      expect(second).to be_nil
      expect(run.reload.execution_token).to eq(first)
    end

    it 'reclaims a running run once the lease has expired' do
      run.update!(status: :running, execution_token: SecureRandom.uuid, lease_expires_at: 5.minutes.ago)

      token = described_class.new(run.reload).acquire!

      expect(token).to be_present
      expect(run.reload.execution_token).to eq(token)
      expect(run.lease_expires_at).to be_future
    end

    it 'preserves the original started_at when reclaiming' do
      started = 10.minutes.ago
      run.update!(status: :running, execution_token: SecureRandom.uuid, lease_expires_at: 5.minutes.ago, started_at: started)

      described_class.new(run.reload).acquire!

      expect(run.reload.started_at).to be_within(1.second).of(started)
    end
  end

  describe '#heartbeat!' do
    it 'renews the lease while the token still owns the run' do
      token = described_class.new(run).acquire!
      run.update_column(:lease_expires_at, 30.seconds.from_now)

      renewed = described_class.new(run.reload).heartbeat!(token)

      expect(renewed).to be(true)
      expect(run.reload.lease_expires_at).to be_within(5.seconds).of(Captain::PaymentReviewRun::LEASE_DURATION.from_now)
    end

    it 'refuses to renew for a stale token after the run was reclaimed' do
      old_token = described_class.new(run).acquire!
      run.update!(lease_expires_at: 5.minutes.ago)
      new_token = described_class.new(run.reload).acquire!
      expect(new_token).not_to eq(old_token)

      expect(described_class.new(run.reload).heartbeat!(old_token)).to be(false)
      expect(run.reload.execution_token).to eq(new_token)
    end
  end
end
# rubocop:enable Rails/SkipsModelValidations
