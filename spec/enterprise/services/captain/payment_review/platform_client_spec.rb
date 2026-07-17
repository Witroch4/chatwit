require 'rails_helper'

RSpec.describe Captain::PaymentReview::PlatformClient do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:run) do
    create(:captain_payment_review_run, conversation: conversation,
                                        triggered_at: Time.zone.parse('2026-07-17T12:00:00Z'),
                                        payment_context_id: 'ctx_1', payment_context_version: 4)
  end
  let(:base) { 'http://platform-api:8000/api/v1/socialwise/integrations/captain' }
  let(:client) { described_class.new(run) }

  around do |example|
    with_modified_env(CHATWIT_WEBHOOK_SECRET: 'shared-secret', CAPTAIN_PAYMENT_PLATFORM_URL: 'http://platform-api:8000') do
      example.run
    end
  end

  describe '#payment_context' do
    let(:context_body) do
      {
        paymentContextId: 'ctx_1', version: 4, status: 'pending', provider: 'infinitepay',
        orderNsu: 'sw-abc', amountCents: 2790, canSendCta: true, hasOfficialPixKey: true,
        canSendStatus: true, checkedAt: '2026-07-17T12:00:00Z', reasonCode: 'provider_not_paid'
      }.to_json
    end

    it 'sends the signed headers and the run correlation' do
      stub = stub_request(:get, "#{base}/payment-context")
             .with(
               query: hash_including(
                 'triggered_at' => '2026-07-17T12:00:00Z',
                 'payment_context_id' => 'ctx_1',
                 'payment_context_version' => '4'
               ),
               headers: {
                 'X-Chatwit-Secret' => 'shared-secret',
                 'X-Chatwoot-Account-Id' => account.id.to_s,
                 'X-Chatwoot-Conversation-Id' => conversation.id.to_s,
                 'X-Chatwoot-Conversation-Display-Id' => conversation.display_id.to_s
               }
             )
             .to_return(status: 200, body: context_body, headers: { 'Content-Type' => 'application/json' })

      context = client.payment_context
      expect(stub).to have_been_requested
      expect(context.payment_context_id).to eq('ctx_1')
      expect(context.version).to eq(4)
      expect(context).to be_pending
      expect(context.can_send_cta).to be(true)
    end

    it 'refuses to run with a blank secret' do
      with_modified_env(CHATWIT_WEBHOOK_SECRET: '') do
        expect { client.payment_context }.to raise_error(described_class::ConfigurationError)
      end
    end

    it 'returns nil when the platform has no context (404)' do
      stub_request(:get, "#{base}/payment-context").with(query: hash_including({})).to_return(status: 404)
      expect(client.payment_context).to be_nil
    end

    it 'raises ContextConflict on 409' do
      stub_request(:get, "#{base}/payment-context")
        .with(query: hash_including({}))
        .to_return(status: 409, body: { result: 'context_conflict' }.to_json)
      expect { client.payment_context }.to raise_error(described_class::ContextConflict)
    end

    it 'raises a retryable Unavailable on timeout without leaking a public message' do
      stub_request(:get, "#{base}/payment-context").with(query: hash_including({})).to_timeout
      expect { client.payment_context }.to raise_error(described_class::Unavailable)
    end
  end

  describe '#authorize' do
    let(:envelope_body) do
      {
        result: 'authorized', action: 'cta', paymentContextId: 'ctx_1', version: 4,
        message: { 'content' => 'Pague aqui', 'content_type' => 'integrations',
                   'content_attributes' => { 'interactive' => { 'type' => 'cta_url' } } },
        issuedAt: 30.seconds.ago.utc.iso8601,
        expiresAt: 25.seconds.from_now.utc.iso8601,
        receipt: { status: 'pending', reasonCode: 'provider_reports_unpaid' }
      }.to_json
    end

    it 'maps send_cta to the cta action route and parses the envelope' do
      stub = stub_request(:post, "#{base}/payment-actions/cta")
             .with(body: hash_including('paymentContextId' => 'ctx_1', 'version' => 4, 'captainRunId' => run.id))
             .to_return(status: 200, body: envelope_body, headers: { 'Content-Type' => 'application/json' })

      envelope = client.authorize('send_cta')
      expect(stub).to have_been_requested
      expect(envelope).to be_authorized
      expect(envelope).not_to be_expired
      expect(envelope.message['content']).to eq('Pague aqui')
    end

    it 'reports paid_noop envelopes' do
      stub_request(:post, "#{base}/payment-actions/pix-key")
        .to_return(status: 200, body: { result: 'paid_noop', action: 'pix-key' }.to_json)
      envelope = client.authorize('send_pix_key')
      expect(envelope).to be_paid_noop
      expect(envelope).not_to be_authorized
    end

    it 'flags expired envelopes' do
      stub_request(:post, "#{base}/payment-actions/status")
        .to_return(status: 200, body: {
          result: 'authorized', action: 'status', message: { 'content' => 'status' },
          issuedAt: 90.seconds.ago.utc.iso8601, expiresAt: 60.seconds.ago.utc.iso8601
        }.to_json)
      expect(client.authorize('send_status')).to be_expired
    end

    it 'raises Unavailable on 5xx' do
      stub_request(:post, "#{base}/payment-actions/cta").to_return(status: 503)
      expect { client.authorize('send_cta') }.to raise_error(described_class::Unavailable)
    end
  end
end
