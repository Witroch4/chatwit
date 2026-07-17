require 'rails_helper'

RSpec.describe CaptainPaymentReviewListener do
  let(:listener) { described_class.instance }
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }

  describe '#conversation_captain_payment_review_requested' do
    it 'is a nudge that drains the wake service for the conversation' do
      wake = instance_double(Captain::PaymentReview::WakeService, call: nil)
      allow(Captain::PaymentReview::WakeService).to receive(:new).with(conversation).and_return(wake)

      event = Events::Base.new('conversation.captain_payment_review_requested', Time.zone.now, conversation: conversation)
      listener.conversation_captain_payment_review_requested(event)

      expect(wake).to have_received(:call).once
    end

    it 'swallows wake errors so the nudge never blows up the dispatcher' do
      allow(Captain::PaymentReview::WakeService).to receive(:new).and_raise(StandardError, 'boom')

      event = Events::Base.new('conversation.captain_payment_review_requested', Time.zone.now, conversation: conversation)

      expect { listener.conversation_captain_payment_review_requested(event) }.not_to raise_error
    end
  end
end
