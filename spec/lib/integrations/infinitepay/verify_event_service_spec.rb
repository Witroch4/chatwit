# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Integrations::Infinitepay::VerifyEventService do
  let(:account) { create(:account, custom_attributes: { 'infinitepay_handle' => 'oficial' }) }
  let(:conversation) { create(:conversation, account: account) }
  let(:payment_link) do
    PaymentLink.create!(account: account, conversation: conversation, user: create(:user, account: account),
                        order_nsu: "chatwit-#{account.id}-1-abc", amount_cents: 2790,
                        checkout_url: 'https://checkout.infinitepay.io/x', status: 'pending')
  end
  let(:verify_url) { %r{/api/v1/socialwise/integrations/captain/payment-events/verify} }
  let(:receipt) { { 'status' => 'paid', 'source' => 'infinitepay_payment_check' } }

  around do |example|
    with_modified_env(CAPTAIN_PAYMENT_PLATFORM_URL: 'http://platform-api:8000', CHATWIT_WEBHOOK_SECRET: 'segredo-de-teste') do
      example.run
    end
  end

  def sent_body
    body = nil
    stub_request(:post, verify_url).with { |request| body = JSON.parse(request.body) }
                                   .to_return(status: 200, body: { receipt: receipt }.to_json,
                                              headers: { 'Content-Type' => 'application/json' })
    yield
    body
  end

  it 'sends the webhook receipt link so the Platform can keep it on the JusMonitorIA entry' do
    raw = { 'transaction_nsu' => 'T1', 'invoice_slug' => 'S1', 'receipt_url' => 'https://recibo.infinitepay.io/abc' }

    body = sent_body { described_class.new(payment_link: payment_link, raw_payload: raw).receipt }

    expect(body['event']).to eq('receipt_url' => 'https://recibo.infinitepay.io/abc')
    expect(body['expectedLink']).to include('orderNsu' => payment_link.order_nsu, 'transactionNsu' => 'T1',
                                            'invoiceSlug' => 'S1')
  end

  it 'omits a receipt link from any host other than the official InfinitePay one' do
    raw = { 'transaction_nsu' => 'T1', 'receipt_url' => 'https://recibo.infinitepay.io.evil.com/abc' }

    body = sent_body { described_class.new(payment_link: payment_link, raw_payload: raw).receipt }

    expect(body).not_to have_key('event')
  end

  it 'omits the event when the webhook has no receipt link' do
    body = sent_body { described_class.new(payment_link: payment_link, raw_payload: { 'transaction_nsu' => 'T1' }).receipt }

    expect(body).not_to have_key('event')
  end
end
