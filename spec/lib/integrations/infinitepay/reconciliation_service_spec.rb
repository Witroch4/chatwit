require 'rails_helper'

# rubocop:disable RSpec/AnyInstance

RSpec.describe Integrations::Infinitepay::ReconciliationService do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:order_nsu) { 'chatwit-1-2-abc123' }
  let!(:payment_link) do
    PaymentLink.create!(account: account, conversation: conversation, order_nsu: order_nsu,
                        amount_cents: 500, description: 'Análise', checkout_url: 'x', status: 'pending')
  end
  let(:receipt) do
    {
      'status' => 'paid', 'source' => 'infinitepay_payment_check', 'orderNsu' => order_nsu,
      'expectedAmountCents' => 500, 'providerAmountCents' => 500, 'paidAmountCents' => 500,
      'checkedAt' => Time.current.utc.iso8601, 'reasonCode' => 'provider_confirmed'
    }
  end
  let(:raw_payload) { { 'receipt_url' => 'https://recibo.example/r/1', 'capture_method' => 'pix', 'paid_amount' => 999_999 } }

  def service(custom_receipt: receipt)
    described_class.new(order_nsu: order_nsu, receipt: custom_receipt, raw_payload: raw_payload)
  end

  before do
    allow_any_instance_of(Integrations::Infinitepay::WebhookProcessorService)
      .to receive(:send_payment_push!)
    stub_request(:post, %r{/api/v1/socialwise/admin/leads-chatwit/recebearquivos})
      .to_return(status: 200, body: '{}')
    allow(Integrations::Jusmonitoria::WebhookForwarderService).to receive(:forward_event)
      .and_return(instance_double(HTTParty::Response, success?: true, code: 200))
  end

  around { |example| with_modified_env(SOCIALWISE_WEBHOOK_URL: 'http://platform-api:8000') { example.run } }

  it 'refuses anything but a paid official receipt' do
    expect { service(custom_receipt: receipt.merge('status' => 'pending')).perform }
      .to raise_error(described_class::UnverifiedReceiptError)
    expect { service(custom_receipt: receipt.merge('source' => 'raw_webhook')).perform }
      .to raise_error(described_class::UnverifiedReceiptError)
    expect(payment_link.reload.status).to eq('pending')
  end

  it 'applies every milestone once with verified amounts' do
    reconciliation = service.perform

    expect(PaymentReconciliation::MILESTONES.all? { |m| reconciliation.milestone_done?(m) }).to be(true)
    link = payment_link.reload
    expect(link.status).to eq('paid')
    expect(link.paid_amount_cents).to eq(500) # receipt value, not the lying raw 999_999
    expect(conversation.messages.outgoing.count).to eq(1)
  end

  it 'resumes after a crash without duplicating earlier effects' do
    # Simulate a crash right after the confirmation message milestone.
    recon = PaymentReconciliation.create!(provider: 'infinitepay', order_nsu: order_nsu)
    %w[verified chatwit_payment_link_applied confirmation_message_accepted].each { |m| recon.record_milestone!(m) }
    conversation.messages.create!(account: account, inbox_id: conversation.inbox_id, message_type: :outgoing,
                                  content: 'já enviada',
                                  additional_attributes: { payment_link_id: payment_link.id,
                                                           infinitepay_event: 'payment_confirmed' })

    service.perform

    expect(conversation.messages.outgoing.count).to eq(1)
    expect(recon.reload.milestone_done?('completed')).to be(true)
  end

  it 'does not skip later milestones when the link is already paid' do
    payment_link.update!(status: 'paid')

    reconciliation = service.perform

    expect(reconciliation.milestone_done?('socialwise_forwarded')).to be(true)
    expect(reconciliation.milestone_done?('jusmonitoria_forwarded')).to be(true)
    expect(conversation.messages.outgoing.count).to eq(1)
  end

  it 'stops at a failing milestone and leaves earlier ones recorded for resume' do
    stub_request(:post, %r{/api/v1/socialwise/admin/leads-chatwit/recebearquivos}).to_return(status: 503)

    expect { service.perform }.to raise_error(/SocialWise forward failed/)

    recon = PaymentReconciliation.find_by!(order_nsu: order_nsu)
    expect(recon.milestone_done?('chatwit_payment_link_applied')).to be(true)
    expect(recon.milestone_done?('session_reconciled')).to be(false)
    expect(recon.milestone_done?('completed')).to be(false)
  end
end
# rubocop:enable RSpec/AnyInstance
