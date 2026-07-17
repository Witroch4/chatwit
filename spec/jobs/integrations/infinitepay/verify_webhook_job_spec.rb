require 'rails_helper'

RSpec.describe Integrations::Infinitepay::VerifyWebhookJob do
  let(:account) { create(:account, custom_attributes: { 'infinitepay_handle' => 'official-handle' }) }
  let(:conversation) { create(:conversation, account: account) }
  let(:order_nsu) { 'chatwit-1-2-abc123' }
  let(:verify_url) { 'http://platform-api:8000/api/v1/socialwise/integrations/captain/payment-events/verify' }
  let(:event) do
    InfinitepayWebhookEvent.record(payload: { 'order_nsu' => order_nsu, 'paid_amount' => 999_999,
                                              'transaction_nsu' => 'tx-123', 'invoice_slug' => 'slug-123' })
  end

  around do |example|
    with_modified_env(CHATWIT_WEBHOOK_SECRET: 'shared-secret',
                      CAPTAIN_PAYMENT_PLATFORM_URL: 'http://platform-api:8000',
                      SOCIALWISE_WEBHOOK_URL: 'http://platform-api:8000') do
      example.run
    end
  end

  context 'with a local payment link' do
    let!(:payment_link) do
      PaymentLink.create!(account: account, conversation: conversation, order_nsu: order_nsu,
                          amount_cents: 500, description: 'Análise', checkout_url: 'x', status: 'pending')
    end

    def receipt_body(status: 'paid')
      { receipt: { status: status, source: 'infinitepay_payment_check', orderNsu: order_nsu,
                   expectedAmountCents: 500, providerAmountCents: 500, paidAmountCents: 500,
                   checkedAt: Time.current.utc.iso8601, reasonCode: 'provider_confirmed' } }.to_json
    end

    it 'verifies with expected metadata plus the quarantined query pointers and reconciles on paid' do
      stub = stub_request(:post, verify_url)
             .with(
               headers: { 'X-Chatwit-Secret' => 'shared-secret', 'X-Chatwoot-Account-Id' => account.id.to_s },
               body: hash_including(
                 'expectedLink' => hash_including('handle' => 'official-handle', 'orderNsu' => order_nsu,
                                                  'amountCents' => 500,
                                                  'transactionNsu' => 'tx-123', 'invoiceSlug' => 'slug-123')
               )
             )
             .to_return(status: 200, body: receipt_body, headers: { 'Content-Type' => 'application/json' })
      reconciler = instance_double(Integrations::Infinitepay::ReconciliationService, perform: true)
      allow(Integrations::Infinitepay::ReconciliationService).to receive(:new)
        .with(hash_including(order_nsu: order_nsu)).and_return(reconciler)

      described_class.perform_now(event.id)

      expect(stub).to have_been_requested
      expect(reconciler).to have_received(:perform)
      expect(event.reload).to be_processed
    end

    it 'schedules a retry when the provider still reports pending' do
      stub_request(:post, verify_url)
        .to_return(status: 200, body: receipt_body(status: 'pending'), headers: { 'Content-Type' => 'application/json' })

      expect { described_class.perform_now(event.id) }.to have_enqueued_job(described_class)
      expect(event.reload).to be_awaiting_verification
      expect(PaymentReconciliation.count).to eq(0)
      expect(payment_link.reload.status).to eq('pending')
    end

    it 'retries unknown receipts (provider propagation delay) without any effect' do
      stub_request(:post, verify_url)
        .to_return(status: 200, body: receipt_body(status: 'unknown'), headers: { 'Content-Type' => 'application/json' })

      expect { described_class.perform_now(event.id) }.to have_enqueued_job(described_class)
      expect(event.reload).to be_awaiting_verification
      expect(payment_link.reload.status).to eq('pending')
    end
  end

  context 'without a local anchor (flow charge)' do
    let(:order_nsu) { "sw-#{SecureRandom.hex(8)}" }

    it 'forwards the raw event to the Platform (which verifies server-side) and never touches local state' do
      forward = stub_request(:post, %r{/api/v1/socialwise/admin/leads-chatwit/recebearquivos})
                .to_return(status: 200, body: '{}')

      described_class.perform_now(event.id)

      expect(forward).to have_been_requested
      expect(event.reload).to be_processed
      expect(PaymentLink.count).to eq(0)
      expect(PaymentReconciliation.count).to eq(0)
    end
  end
end
