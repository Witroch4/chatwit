require 'rails_helper'

# rubocop:disable RSpec/LetSetup

RSpec.describe Captain::PaymentReview::Finalizer do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let!(:captain_inbox) do
    create(:captain_inbox, captain_assistant: assistant, inbox: inbox, mode: :phase2_only,
                           phase2_payment_preset_ids: [preset.id])
  end
  let(:preset) { create(:payment_preset, account: account, name: 'Análise OAB', amount_cents: 2790) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:label) { Captain::PaymentReviewTrigger::CANONICAL_LABEL }
  let!(:account_label) { create(:label, account: account, title: label) }
  let(:trigger) do
    create(:captain_payment_review_trigger, conversation: conversation, account: account,
                                            state: :claimed, generation: 1)
  end
  let(:run) do
    create(:captain_payment_review_run, conversation: conversation, captain_assistant: assistant,
                                        status: :running, execution_token: token,
                                        lease_expires_at: 2.minutes.from_now, generation: 1)
  end
  let(:token) { SecureRandom.uuid }

  before do
    conversation.update!(label_list: [label])
    trigger.update!(run_id: run.id)
  end

  def finalizer(with_token: token)
    described_class.new(run: run, token: with_token)
  end

  describe 'stale ownership' do
    it 'refuses to finalize with a stale token' do
      expect { finalizer(with_token: SecureRandom.uuid).no_action! }
        .to raise_error(described_class::StaleRunError)
      expect(run.reload).to be_running
      expect(conversation.reload.label_list).to include(label)
    end

    it 'refuses to finalize when the lease expired' do
      run.update!(lease_expires_at: 1.minute.ago)
      expect { finalizer.no_action! }.to raise_error(described_class::StaleRunError)
    end
  end

  describe '#no_action!' do
    it 'completes the run, consumes the trigger and removes the label atomically without a message' do
      expect { finalizer.no_action! }.not_to(change { conversation.messages.count })

      expect(run.reload).to be_completed
      expect(run.outcome).to eq('no_action')
      expect(run.completed_at).to be_present
      expect(trigger.reload).to be_consumed
      expect(trigger.deactivated_at).to be_present
      expect(conversation.reload.label_list).not_to include(label)
    end

    it 'preserves the label and promotes the successor generation after the terminal' do
      trigger.update!(state: :cancelled, deactivated_at: Time.current)
      successor = create(:captain_payment_review_trigger, conversation: conversation, account: account,
                                                          state: :eligible, generation: 2)

      finalizer.no_action!

      expect(run.reload).to be_completed
      expect(conversation.reload.label_list).to include(label)
      successor.reload
      expect(successor).to be_claimed
      expect(successor.run_id).to be_present
      expect(successor.run_id).not_to eq(run.id)
      expect(successor.deactivated_at).to be_nil
    end
  end

  describe '#paid!' do
    it 'completes as paid without any public message and without calling the LLM' do
      expect { finalizer.paid! }.not_to(change { conversation.messages.count })
      expect(run.reload.outcome).to eq('paid')
      expect(conversation.reload.label_list).not_to include(label)
    end
  end

  describe '#reply!' do
    let(:decision) do
      Captain::PaymentReview::DecisionSchema::Decision.new(
        action: 'reply', response: 'Claro, posso ajudar!', reason_code: 'faq_answer'
      )
    end

    it 'creates exactly one idempotent assistant message inside the terminal transaction' do
      finalizer.reply!(decision)

      message = conversation.messages.order(:id).last
      expect(message.content).to eq('Claro, posso ajudar!')
      expect(message.idempotency_key).to eq("captain-payment-review:#{run.id}:reply")
      expect(message.sender).to eq(assistant)
      expect(run.reload.outcome).to eq('replied')
      expect(run.response_message_id).to eq(message.id)
      expect(trigger.reload).to be_consumed
      expect(conversation.reload.label_list).not_to include(label)
    end

    it 'does not duplicate the message when finalization retries after a crash between message and run terminal' do
      finalizer.reply!(decision)
      run.update!(status: :running, outcome: nil, completed_at: nil,
                  execution_token: token, lease_expires_at: 2.minutes.from_now)

      expect { finalizer.reply!(decision) }.not_to(change { conversation.messages.count })
      expect(run.reload).to be_completed
    end
  end

  describe '#complete_with_envelope!' do
    let(:decision) do
      Captain::PaymentReview::DecisionSchema::Decision.new(action: 'send_cta', reason_code: 'asks_payment_link')
    end

    def envelope(expires_in: 20.seconds)
      Captain::PaymentReview::PlatformClient::ActionEnvelope.new(
        result: 'authorized', action: 'cta',
        message: { 'content' => 'Pague aqui', 'content_type' => 'integrations',
                   'content_attributes' => { 'interactive' => { 'type' => 'cta_url' } } },
        issued_at: Time.current, expires_at: expires_in.from_now
      )
    end

    it 'creates the official envelope message and finishes as accepted' do
      finalizer.complete_with_envelope!(decision, envelope)

      message = conversation.messages.order(:id).last
      expect(message.content_type).to eq('integrations')
      expect(message.content_attributes['interactive']).to eq({ 'type' => 'cta_url' })
      expect(message.idempotency_key).to eq("captain-payment-review:#{run.id}:send_cta")
      expect(run.reload.outcome).to eq('cta_accepted')
    end

    it 'rejects an expired envelope without any effect' do
      expect { finalizer.complete_with_envelope!(decision, envelope(expires_in: -1.second)) }
        .to raise_error(described_class::EnvelopeExpiredError)
      expect(conversation.messages.count).to eq(0)
      expect(run.reload).to be_running
      expect(conversation.reload.label_list).to include(label)
    end
  end

  describe '#send_payment_preset!' do
    let(:decision) do
      Captain::PaymentReview::DecisionSchema::Decision.new(
        action: 'send_payment_preset', preset_id: preset.id, reason_code: 'asks_payment_link'
      )
    end

    before do
      account.update!(custom_attributes: { 'infinitepay_handle' => 'official-handle' })
      stub_request(:post, Integrations::Infinitepay::CreateLinkService::INFINITEPAY_API)
        .to_return(status: 200, body: { checkout_url: 'https://checkout.infinitepay.io/official-handle/slug-x' }.to_json,
                   headers: { 'Content-Type' => 'application/json' })
    end

    it 'generates the charge and creates one idempotent interactive/plain message with the preset values' do
      finalizer.send_payment_preset!(decision)

      message = conversation.messages.order(:id).last
      expect(message.idempotency_key).to eq("captain-payment-review:#{run.id}:send_payment_preset")
      expect(message.content).to include('checkout.infinitepay.io')
      expect(run.reload.outcome).to eq('payment_preset_accepted')
      link = PaymentLink.order(:id).last
      expect(link.amount_cents).to eq(2790)
      expect(link.conversation_id).to eq(conversation.id)
    end

    it 'fails closed for a preset outside the allowlist' do
      other = create(:payment_preset, account: account)
      bad = Captain::PaymentReview::DecisionSchema::Decision.new(
        action: 'send_payment_preset', preset_id: other.id, reason_code: 'asks_payment_link'
      )
      expect { finalizer.send_payment_preset!(bad) }.to raise_error(described_class::PresetNotAllowedError)
      expect(conversation.messages.count).to eq(0)
      expect(run.reload).to be_running
    end

    it 'fails closed for a preset from another account even when allowlisted' do
      foreign = create(:payment_preset)
      captain_inbox.update_column(:phase2_payment_preset_ids, [foreign.id]) # rubocop:disable Rails/SkipsModelValidations
      bad = Captain::PaymentReview::DecisionSchema::Decision.new(
        action: 'send_payment_preset', preset_id: foreign.id, reason_code: 'asks_payment_link'
      )
      expect { finalizer.send_payment_preset!(bad) }.to raise_error(described_class::PresetNotAllowedError)
    end
  end

  describe '#handoff!' do
    let(:decision) do
      Captain::PaymentReview::DecisionSchema::Decision.new(action: 'handoff_required', reason_code: 'unsupported_question')
    end

    it 'opens the human handoff, keeps the label and records a sanitized private note' do
      finalizer.handoff!(decision)

      expect(run.reload.outcome).to eq('handoff_required')
      expect(conversation.reload.label_list).to include(label)
      note = conversation.messages.where(private: true).last
      expect(note).to be_present
      expect(note.content).not_to include('checkout')
    end
  end
end
# rubocop:enable RSpec/LetSetup
