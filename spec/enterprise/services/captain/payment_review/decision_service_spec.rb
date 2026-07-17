require 'rails_helper'

RSpec.describe Captain::PaymentReview::DecisionService do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let!(:captain_inbox) do
    create(:captain_inbox, captain_assistant: assistant, inbox: inbox, mode: :phase2_only,
                           phase2_model: 'witdev_claude/sonnet',
                           phase2_prompt: operator_prompt,
                           phase2_payment_preset_ids: [preset.id])
  end
  let(:operator_prompt) { 'Atenda com cordialidade.' }
  let(:preset) { create(:payment_preset, account: account, name: 'Análise OAB', amount_cents: 2790) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:run) do
    create(:captain_payment_review_run, conversation: conversation, captain_assistant: assistant,
                                        trigger_message_id: watermark)
  end
  let(:watermark) do
    create(:message, conversation: conversation, message_type: :incoming, content: 'quero pagar').id
  end
  let(:platform_context) do
    Captain::PaymentReview::PlatformClient::PaymentContext.new(
      payment_context_id: 'ctx_1', version: 4, status: 'pending', order_nsu: 'sw-abc',
      amount_cents: 2790, can_send_cta: true, has_official_pix_key: true,
      can_send_status: true, reason_code: 'provider_not_paid'
    )
  end
  let(:service) { described_class.new(run: run, context: platform_context) }
  let(:llm_output) { { 'action' => 'no_action', 'reason_code' => 'no_unresolved_question' }.to_json }
  let(:captured_prompts) { [] }

  before do
    allow(service).to receive(:complete) do |messages:, model:|
      captured_prompts << { messages: messages, model: model }
      llm_output
    end
  end

  describe 'model resolution' do
    it 'uses the captain inbox phase2_model' do
      service.call
      expect(captured_prompts.first[:model]).to eq('witdev_claude/sonnet')
    end

    it 'falls back to the installation chain when phase2_model is blank' do
      captain_inbox.update!(phase2_model: nil)
      allow(Chatwit::LlmProxy).to receive(:enabled?).and_return(true)
      allow(Chatwit::LlmProxy).to receive(:model).and_return('proxy-default')
      service.call
      expect(captured_prompts.first[:model]).to eq('proxy-default')
    end
  end

  describe 'effective prompt safety' do
    it 'includes the operator prompt, capabilities and preset names without any financial value' do
      service.call
      prompt_text = captured_prompts.first[:messages].map { |m| m[:content] }.join("\n")
      expect(prompt_text).to include('Atenda com cordialidade.')
      expect(prompt_text).to include('Análise OAB')
      expect(prompt_text).to include(preset.id.to_s)
      expect(prompt_text).not_to include('2790')
      expect(prompt_text).not_to include('27,90')
      expect(prompt_text).not_to include('sw-abc')
      expect(prompt_text).not_to include('checkout')
    end

    it 'uses the default prompt when the operator left it blank' do
      captain_inbox.update!(phase2_prompt: nil)
      service.call
      prompt_text = captured_prompts.first[:messages].map { |m| m[:content] }.join("\n")
      expect(prompt_text).to include(Captain::PaymentReview::DEFAULT_PROMPT.lines.first.strip)
    end

    it 'feeds the sanitized history, never raw checkout URLs' do
      create(:message, conversation: conversation, message_type: :outgoing,
                       content: 'https://checkout.infinitepay.io/h/slug-999')
      run.update!(trigger_message_id: conversation.messages.maximum(:id))
      service.call
      prompt_text = captured_prompts.first[:messages].map { |m| m[:content] }.join("\n")
      expect(prompt_text).not_to include('slug-999')
    end
  end

  describe 'schema validation (fail closed)' do
    context 'when the model returns an unknown action' do
      let(:llm_output) { { 'action' => 'send_money', 'reason_code' => 'faq_answer' }.to_json }

      it 'retries once and then fails closed' do
        expect { service.call }.to raise_error(Captain::PaymentReview::DecisionService::DecisionFailed)
        expect(captured_prompts.size).to eq(2)
      end
    end

    context 'when reply comes without text' do
      let(:llm_output) { { 'action' => 'reply', 'response' => '', 'reason_code' => 'faq_answer' }.to_json }

      it 'fails closed' do
        expect { service.call }.to raise_error(Captain::PaymentReview::DecisionService::DecisionFailed)
      end
    end

    context 'when send_payment_preset carries a preset outside the allowlist' do
      let(:llm_output) do
        { 'action' => 'send_payment_preset', 'preset_id' => preset.id + 999, 'reason_code' => 'asks_payment_link' }.to_json
      end

      it 'fails closed' do
        expect { service.call }.to raise_error(Captain::PaymentReview::DecisionService::DecisionFailed)
      end
    end

    context 'when send_payment_preset is allowlisted' do
      let(:llm_output) do
        { 'action' => 'send_payment_preset', 'preset_id' => preset.id, 'reason_code' => 'asks_payment_link' }.to_json
      end

      it 'returns the decision with the preset id' do
        decision = service.call
        expect(decision.action).to eq('send_payment_preset')
        expect(decision.preset_id).to eq(preset.id)
      end
    end
  end

  describe 'reply leak validation' do
    context 'when the reply leaks a checkout URL' do
      let(:llm_output) do
        { 'action' => 'reply', 'response' => 'Pague em https://checkout.infinitepay.io/h/x', 'reason_code' => 'faq_answer' }.to_json
      end

      it 'fails closed even after retry' do
        expect { service.call }.to raise_error(Captain::PaymentReview::DecisionService::DecisionFailed)
      end
    end

    context 'when the reply contains a CNPJ the operator put in the prompt' do
      let(:operator_prompt) { 'Se o lead não conseguir pagar pelo link, envie o CNPJ 57.944.155/0001-01.' }
      let(:llm_output) do
        { 'action' => 'reply', 'response' => 'Pode pagar via Pix no CNPJ 57.944.155/0001-01.', 'reason_code' => 'faq_answer' }.to_json
      end

      it 'accepts the operator-authorized value' do
        expect(service.call.response).to include('57.944.155/0001-01')
      end
    end

    context 'when the reply contains a CNPJ the operator never authorized' do
      let(:llm_output) do
        { 'action' => 'reply', 'response' => 'Pague no CNPJ 11.222.333/0001-44.', 'reason_code' => 'faq_answer' }.to_json
      end

      it 'fails closed' do
        expect { service.call }.to raise_error(Captain::PaymentReview::DecisionService::DecisionFailed)
      end
    end
  end

  describe 'usage accounting' do
    it 'counts exactly one captain response per successful decision' do
      expect { service.call }.to change { account.reload.custom_attributes['captain_responses_usage'].to_i }.by(1)
    end

    it 'does not count when the decision fails closed' do
      allow(service).to receive(:complete).and_return('not-json')
      expect do
        expect { service.call }.to raise_error(Captain::PaymentReview::DecisionService::DecisionFailed)
      end.not_to(change { account.reload.custom_attributes['captain_responses_usage'].to_i })
    end
  end
end
