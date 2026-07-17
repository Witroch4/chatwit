require 'rails_helper'

# rubocop:disable RSpec/AnyInstance

RSpec.describe Captain::PaymentReviewJob do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

  def run_with(status: :queued, **attrs)
    create(:captain_payment_review_run, conversation: conversation, status: status, **attrs)
  end

  describe 'lease and supersede (Task 10 contract)' do
    before do
      allow_any_instance_of(described_class).to receive(:execute_review)
    end

    it 'acquires the lease and marks the run running' do
      run = run_with(trigger_message_id: nil)

      described_class.perform_now(run.id)

      run.reload
      expect(run).to be_running
      expect(run.execution_token).to be_present
      expect(run.lease_expires_at).to be_future
    end

    it 'does nothing when the run is already terminal' do
      run = run_with(status: :completed, outcome: :replied, completed_at: Time.current)

      described_class.perform_now(run.id)

      expect(run.reload).to be_completed
      expect(run.execution_token).to be_nil
    end

    it 'does not steal a run whose lease is still held by another worker' do
      other_token = SecureRandom.uuid
      run = run_with(status: :running, execution_token: other_token, lease_expires_at: 2.minutes.from_now)

      described_class.perform_now(run.id)

      expect(run.reload.execution_token).to eq(other_token)
    end

    it 'supersedes the run when a human responded after the trigger watermark' do
      watermark = create(:message, conversation: conversation, message_type: :incoming)
      run = run_with(trigger_message_id: watermark.id)
      agent = create(:user, account: account)
      create(:message, conversation: conversation, message_type: :outgoing, sender: agent)

      described_class.perform_now(run.id)

      run.reload
      expect(run).to be_superseded
      expect(run.reason_code).to eq('human_response')
    end

    it 'ignores messages at or before the trigger watermark' do
      watermark = create(:message, conversation: conversation, message_type: :incoming)
      run = run_with(trigger_message_id: watermark.id)

      described_class.perform_now(run.id)

      expect(run.reload).to be_running
    end
  end

  describe 'decision branches (Task 11)' do
    let(:run) { run_with(trigger_message_id: nil) }
    let(:finalizer) { instance_double(Captain::PaymentReview::Finalizer) }
    let(:client) { instance_double(Captain::PaymentReview::PlatformClient) }
    let(:decision_service) { instance_double(Captain::PaymentReview::DecisionService) }

    def paid_context
      Captain::PaymentReview::PlatformClient::PaymentContext.new(
        payment_context_id: 'ctx_1', version: 4, status: 'paid', order_nsu: 'sw-abc',
        amount_cents: 1500, can_send_cta: false, has_official_pix_key: true,
        can_send_status: true, reason_code: 'provider_confirmed'
      )
    end

    def pending_context
      Captain::PaymentReview::PlatformClient::PaymentContext.new(
        payment_context_id: 'ctx_1', version: 4, status: 'pending', order_nsu: 'sw-abc',
        amount_cents: 1500, can_send_cta: true, has_official_pix_key: true,
        can_send_status: true, reason_code: 'provider_not_paid'
      )
    end

    def decision(action, **attrs)
      Captain::PaymentReview::DecisionSchema::Decision.new(action: action, reason_code: 'faq_answer', **attrs)
    end

    before do
      allow(Captain::PaymentReview::Finalizer).to receive(:new).and_return(finalizer)
      allow(Captain::PaymentReview::PlatformClient).to receive(:new).and_return(client)
      allow(Captain::PaymentReview::DecisionService).to receive(:new).and_return(decision_service)
    end

    it 'finalizes paid without ever calling the decision service' do
      allow(client).to receive(:payment_context).and_return(paid_context)
      expect(finalizer).to receive(:paid!)

      described_class.perform_now(run.id)

      expect(Captain::PaymentReview::DecisionService).not_to have_received(:new)
    end

    it 'finalizes no_action silently' do
      allow(client).to receive(:payment_context).and_return(pending_context)
      allow(decision_service).to receive(:call).and_return(decision('no_action'))
      expect(finalizer).to receive(:no_action!)

      described_class.perform_now(run.id)
    end

    it 'treats paid_noop envelopes as paid' do
      allow(client).to receive(:payment_context).and_return(pending_context)
      allow(decision_service).to receive(:call).and_return(decision('send_cta'))
      envelope = Captain::PaymentReview::PlatformClient::ActionEnvelope.new(result: 'paid_noop', action: 'cta')
      allow(client).to receive(:authorize).with('send_cta', context: anything).and_return(envelope)
      expect(finalizer).to receive(:paid!)

      described_class.perform_now(run.id)
    end

    it 'completes an authorized envelope' do
      allow(client).to receive(:payment_context).and_return(pending_context)
      allow(decision_service).to receive(:call).and_return(decision('send_cta'))
      envelope = Captain::PaymentReview::PlatformClient::ActionEnvelope.new(
        result: 'authorized', action: 'cta', message: { 'content' => 'x' },
        issued_at: Time.current, expires_at: 20.seconds.from_now
      )
      allow(client).to receive(:authorize).and_return(envelope)
      expect(finalizer).to receive(:complete_with_envelope!)

      described_class.perform_now(run.id)
    end

    it 'retries platform unavailability without any public message and with backoff' do
      allow(client).to receive(:payment_context).and_raise(Captain::PaymentReview::PlatformClient::Unavailable, 'timeout')

      expect { described_class.perform_now(run.id) }
        .to have_enqueued_job(described_class).with(run.id)

      run.reload
      expect(run).to be_running
      expect(run.attempts).to eq(1)
      expect(conversation.messages.where(private: false).count).to eq(0)
    end

    it 'fails terminally after the max attempts with a sanitized private note and the label kept' do
      allow(client).to receive(:payment_context).and_raise(Captain::PaymentReview::PlatformClient::Unavailable, 'timeout')
      run.update!(attempts: 4)
      allow(finalizer).to receive(:fail!) do
        run.update!(status: :failed, error_code: 'platform_timeout', completed_at: Time.current)
      end

      described_class.perform_now(run.id)

      expect(finalizer).to have_received(:fail!).with(hash_including(reason_code: 'platform_timeout'))
      expect(run.reload).to be_failed
    end

    it 'fails closed when the decision is invalid' do
      allow(client).to receive(:payment_context).and_return(pending_context)
      allow(decision_service).to receive(:call)
        .and_raise(Captain::PaymentReview::DecisionService::DecisionFailed, 'invalid')
      expect(finalizer).to receive(:fail!).with(hash_including(reason_code: 'decision_invalid'))

      described_class.perform_now(run.id)
    end

    it 'sends the operator-configured pix key locally without asking the Platform for an envelope' do
      assistant = create(:captain_assistant, account: account)
      create(:captain_inbox, captain_assistant: assistant, inbox: inbox, mode: :phase2_only,
                             phase2_pix_key: 'pix@witdev.com.br')
      allow(client).to receive(:payment_context).and_return(pending_context)
      allow(decision_service).to receive(:call).and_return(decision('send_pix_key'))
      expect(finalizer).to receive(:send_pix_key!).with(anything, 'pix@witdev.com.br')

      described_class.perform_now(run.id)

      expect(client).not_to have_received(:authorize) if client.respond_to?(:authorize)
    end

    it 'falls back to the Platform envelope when no pix key is configured' do
      allow(client).to receive(:payment_context).and_return(pending_context)
      allow(decision_service).to receive(:call).and_return(decision('send_pix_key'))
      envelope = Captain::PaymentReview::PlatformClient::ActionEnvelope.new(result: 'paid_noop', action: 'pix-key')
      allow(client).to receive(:authorize).with('send_pix_key', context: anything).and_return(envelope)
      expect(finalizer).to receive(:paid!)

      described_class.perform_now(run.id)
    end

    it 'stops silently when the finalizer reports stale ownership' do
      allow(client).to receive(:payment_context).and_return(pending_context)
      allow(decision_service).to receive(:call).and_return(decision('no_action'))
      allow(finalizer).to receive(:no_action!).and_raise(Captain::PaymentReview::Finalizer::StaleRunError)

      expect { described_class.perform_now(run.id) }.not_to raise_error
    end
  end
end
# rubocop:enable RSpec/AnyInstance
