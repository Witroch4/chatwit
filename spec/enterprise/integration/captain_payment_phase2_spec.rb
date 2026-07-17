require 'rails_helper'

# rubocop:disable RSpec/DescribeClass, RSpec/LetSetup, RSpec/MultipleExpectations

RSpec.describe 'Captain Payment Phase 2 end-to-end wiring' do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let!(:captain_inbox) do
    create(:captain_inbox, captain_assistant: assistant, inbox: inbox, mode: :phase2_only,
                           phase2_prompt: 'Atenda com cordialidade.')
  end
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:label) { Captain::PaymentReviewTrigger::CANONICAL_LABEL }
  let!(:account_label) { create(:label, account: account, title: label) }
  let(:context_url) { 'http://platform-api:8000/api/v1/socialwise/integrations/captain/payment-context' }

  around do |example|
    with_modified_env(CAPTAIN_PAYMENT_PHASE2_ENABLED: 'true',
                      CAPTAIN_PAYMENT_PHASE2_INBOX_IDS: inbox.id.to_s,
                      CHATWIT_WEBHOOK_SECRET: 'shared-secret',
                      CAPTAIN_PAYMENT_PLATFORM_URL: 'http://platform-api:8000') do
      example.run
    end
  end

  before do
    create(:message, conversation: conversation, message_type: :incoming, content: 'não consegui pagar')
    InstallationConfig.find_or_initialize_by(name: 'CAPTAIN_OPEN_AI_ENDPOINT').update!(value: 'http://llm.test')
    InstallationConfig.find_or_initialize_by(name: 'CAPTAIN_OPEN_AI_API_KEY').update!(value: 'test-key')
  end

  def add_canonical_label!
    Captain::PaymentReview::LabelMutationService.new(
      conversation: conversation, labels: [label], source: :platform_bot,
      payment_context: { id: 'ctx_1', version: 4 }
    ).add!
  end

  def stub_platform_context(status:, can_send_cta: true)
    stub_request(:get, context_url)
      .with(query: hash_including({}), headers: { 'X-Chatwit-Secret' => 'shared-secret' })
      .to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: {
        paymentContextId: 'ctx_1', version: 4, status: status, provider: 'infinitepay',
        orderNsu: 'sw-abc', amountCents: 2790, canSendCta: can_send_cta,
        hasOfficialPixKey: true, canSendStatus: true,
        checkedAt: Time.current.utc.iso8601, reasonCode: 'x'
      }.to_json)
  end

  def stub_llm_reply(action:, response: nil)
    stub_request(:post, /llm\.test/)
      .to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: {
        choices: [{ message: { content: { action: action, response: response,
                                          reason_code: 'faq_answer' }.compact.to_json } }]
      }.to_json)
  end

  it 'runs one full cycle: label -> trigger -> fence -> run -> reply -> atomic terminal' do
    add_canonical_label!
    trigger = conversation.captain_payment_review_triggers.last
    expect(trigger).to be_eligible
    expect(Integrations::SocialwiseFlow::OwnershipGuard.new(conversation.reload).socialwise_owned?).to be(false)

    Captain::PaymentReview::WakeService.new(conversation).call
    run = Captain::PaymentReviewRun.last
    expect(run).to be_queued
    expect(trigger.reload).to be_claimed

    stub_platform_context(status: 'pending')
    stub_llm_reply(action: 'reply', response: 'Claro! Posso te ajudar com o pagamento.')

    Captain::PaymentReviewJob.perform_now(run.id)

    run.reload
    expect(run).to be_completed
    expect(run.outcome).to eq('replied')
    message = conversation.messages.find(run.response_message_id)
    expect(message.content).to eq('Claro! Posso te ajudar com o pagamento.')
    expect(message.idempotency_key).to eq("captain-payment-review:#{run.id}:reply")
    expect(trigger.reload).to be_consumed
    expect(conversation.reload.label_list).not_to include(label)
    expect(conversation.status).to eq('open')
    expect(conversation.waiting_since).to be_nil
  end

  it 'verified paid context finishes silently without calling the LLM and enqueues reconciliation' do
    add_canonical_label!
    Captain::PaymentReview::WakeService.new(conversation).call
    run = Captain::PaymentReviewRun.last
    run.update!(payment_order_nsu: 'sw-abc')
    stub_platform_context(status: 'paid')
    llm = stub_request(:post, /llm\.test/)

    expect { Captain::PaymentReviewJob.perform_now(run.id) }
      .to have_enqueued_job(Integrations::Infinitepay::VerifyWebhookJob)

    expect(run.reload.outcome).to eq('paid')
    expect(conversation.messages.outgoing.where(private: false).count).to eq(0)
    expect(llm).not_to have_been_requested
    expect(InfinitepayWebhookEvent.last.source).to eq('captain_polling')
  end

  it 'refuses the canonical label outside the gate with phase2_disabled' do
    with_modified_env(CAPTAIN_PAYMENT_PHASE2_ENABLED: 'false') do
      expect { add_canonical_label! }
        .to raise_error(Captain::PaymentReview::LabelMutationService::Phase2DisabledError)
    end
    expect(conversation.reload.label_list).not_to include(label)
  end

  it 're-adding after a completed cycle creates a new generation and a new run' do
    add_canonical_label!
    Captain::PaymentReview::WakeService.new(conversation).call
    first_run = Captain::PaymentReviewRun.last
    stub_platform_context(status: 'pending')
    stub_llm_reply(action: 'no_action')
    Captain::PaymentReviewJob.perform_now(first_run.id)
    expect(first_run.reload.outcome).to eq('no_action')

    add_canonical_label!
    Captain::PaymentReview::WakeService.new(conversation).call

    second_run = Captain::PaymentReviewRun.order(:id).last
    expect(second_run.id).not_to eq(first_run.id)
    expect(second_run.generation).to be > first_run.generation
  end
end
# rubocop:enable RSpec/DescribeClass, RSpec/LetSetup, RSpec/MultipleExpectations
