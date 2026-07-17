require 'rails_helper'

RSpec.describe SocialwiseFlowListener do
  subject(:listener) { described_class.instance }

  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:timestamp) { 2.minutes.ago }
  let(:event) { Events::Base.new(:conversation_resolved, timestamp, conversation: conversation) }

  describe '#conversation_resolved' do
    it 'delegates release to the ownership guard with the immutable event cutoff' do
      guard = instance_double(Integrations::SocialwiseFlow::OwnershipGuard)
      expect(Integrations::SocialwiseFlow::OwnershipGuard).to receive(:new).with(conversation).and_return(guard)
      expect(guard).to receive(:release_for_resolve!).with(cutoff: timestamp)

      listener.conversation_resolved(event)
    end

    it 'does nothing when the event has no conversation' do
      event.data[:conversation] = nil

      expect(Integrations::SocialwiseFlow::OwnershipGuard).not_to receive(:new)

      listener.conversation_resolved(event)
    end
  end
end
