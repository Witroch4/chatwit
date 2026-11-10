require 'rails_helper'

describe Integrations::Infinitepay::FlowPaymentPushService do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, name: 'Amanda Alves') }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:order_nsu) { "sw-#{SecureRandom.hex(8)}" }
  let(:answer) { { 'verified' => true, 'conversationId' => conversation.id, 'paidAmountCents' => 2790 } }
  let(:pusher) { instance_double(Integrations::Infinitepay::PushNotificationService, perform: true) }

  before do
    allow(Integrations::Infinitepay::PushNotificationService).to receive(:new).and_return(pusher)
  end

  after { Redis::Alfred.delete("infinitepay:flow_payment_push:#{order_nsu}") }

  it 'pushes the account agents with the verified amount and the conversation link' do
    described_class.new(order_nsu: order_nsu, answer: answer).perform

    expect(Integrations::Infinitepay::PushNotificationService).to have_received(:new).with(
      account: account,
      notification_payload: {
        title: 'Pagamento Confirmado!',
        body: 'Olá, Amanda Alves! Pagamento de R$ 27,90 recebido com sucesso.',
        tag: "infinitepay_payment_confirmed_#{order_nsu}",
        url: end_with("/app/accounts/#{account.id}/conversations/#{conversation.display_id}")
      },
      log_reference: "order_nsu=#{order_nsu}"
    )
    expect(pusher).to have_received(:perform)
  end

  it 'pushes only once per order even when the Platform answers again' do
    2.times { described_class.new(order_nsu: order_nsu, answer: answer).perform }

    expect(pusher).to have_received(:perform).once
  end

  it 'never pushes an unverified answer or an unknown conversation' do
    described_class.new(order_nsu: order_nsu, answer: answer.merge('verified' => false)).perform
    described_class.new(order_nsu: order_nsu, answer: answer.merge('conversationId' => 0)).perform

    expect(Integrations::Infinitepay::PushNotificationService).not_to have_received(:new)
  end
end
