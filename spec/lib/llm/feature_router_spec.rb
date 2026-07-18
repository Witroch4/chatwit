# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Llm::FeatureRouter do
  let(:account) { create(:account) }

  before do
    allow(Chatwit::LlmProxy).to receive(:route_witdev?).and_return(false)
  end

  describe '.resolve' do
    it 'returns the feature default without an account' do
      resolved = described_class.resolve(feature: 'editor')

      expect(resolved).to eq(
        feature: 'editor',
        provider: 'openai',
        model: 'gpt-4.1-mini',
        source: :default
      )
    end

    it 'uses a valid account model override' do
      account.update!(captain_models: { 'editor' => 'gpt-4.1' })

      resolved = described_class.resolve(feature: 'editor', account: account)

      expect(resolved).to include(
        feature: 'editor',
        provider: 'openai',
        model: 'gpt-4.1',
        source: :account_override
      )
    end

    it 'resolves GPT-5.2 as the assistant default when Captain V2 is enabled without storing an account override' do
      account.enable_features!('captain_integration_v2')

      resolved = described_class.resolve(feature: 'assistant', account: account)

      expect(resolved).to include(
        feature: 'assistant',
        provider: 'openai',
        model: 'gpt-5.2',
        source: :default
      )
      expect(account.reload.captain_models).to be_nil
    end

    it 'keeps account model overrides ahead of the Captain V2 default' do
      account.enable_features!('captain_integration_v2')
      account.update!(captain_models: { 'assistant' => 'gpt-5.1' })

      resolved = described_class.resolve(feature: 'assistant', account: account)

      expect(resolved).to include(
        model: 'gpt-5.1',
        source: :account_override
      )
    end

    it 'falls back to the feature default when the account override is invalid' do
      account.captain_models = { 'editor' => 'invalid-model' }

      resolved = described_class.resolve(feature: 'editor', account: account)

      expect(resolved).to include(
        model: 'gpt-4.1-mini',
        source: :default
      )
    end

    it 'falls back to the feature default when the account override is blank' do
      account.update!(captain_models: { 'editor' => '' })

      resolved = described_class.resolve(feature: 'editor', account: account)

      expect(resolved).to include(
        model: 'gpt-4.1-mini',
        source: :default
      )
    end

    it 'raises for unknown features' do
      expect { described_class.resolve(feature: 'unknown_feature') }
        .to raise_error(described_class::UnknownFeatureError, 'Unknown LLM feature: unknown_feature')
    end

    context 'when the WitDev route is enabled' do
      let(:operational_models) do
        [
          { 'value' => 'witdev_claude/sonnet', 'provider' => 'anthropic' },
          { 'value' => 'witdev/gpt-5.5', 'provider' => 'openai' }
        ]
      end

      before do
        allow(Chatwit::LlmProxy).to receive(:route_witdev?).and_return(true)
        allow(Chatwit::LlmProxy).to receive(:model).and_return('witdev_claude/sonnet')
        allow(Chatwit::LlmProxy).to receive(:operational_models).and_return(operational_models)
        allow(Chatwit::LlmProxy).to receive(:resolve_model!) { |model| model }
      end

      it 'resolves an account override through the canonical catalog' do
        account.update!(captain_models: { 'editor' => 'witdev/gpt-5.5' })

        expect(Chatwit::LlmProxy).to receive(:resolve_model!).with('witdev/gpt-5.5').and_return('witdev/gpt-5.5')

        expect(described_class.resolve(feature: 'editor', account: account)).to eq(
          feature: 'editor',
          provider: 'openai',
          model: 'witdev/gpt-5.5',
          source: :account_override
        )
      end

      it 'routes newly added generative features through the canonical catalog' do
        expect(Chatwit::LlmProxy).to receive(:resolve_model!).with('witdev_claude/sonnet').and_return('witdev_claude/sonnet')

        expect(described_class.resolve(feature: 'document_faq_generation', account: account)).to eq(
          feature: 'document_faq_generation',
          provider: 'anthropic',
          model: 'witdev_claude/sonnet',
          source: :witdev_default
        )
      end

      it 'keeps transcription and embeddings on the legacy model route' do
        expect(Chatwit::LlmProxy).not_to receive(:resolve_model!)

        expect(described_class.resolve(feature: 'audio_transcription', account: account)).to include(
          model: 'gpt-4o-mini-transcribe', source: :default
        )
        expect(described_class.resolve(feature: 'help_center_search', account: account)).to include(
          model: 'text-embedding-3-small', source: :default
        )
      end

      it 'propagates canonical catalog errors instead of falling back to legacy models' do
        allow(Chatwit::LlmProxy).to receive(:resolve_model!)
          .and_raise(Chatwit::LlmProxy::CatalogUnavailableError, 'catalog unavailable')

        expect { described_class.resolve(feature: 'assistant', account: account) }
          .to raise_error(Chatwit::LlmProxy::CatalogUnavailableError, 'catalog unavailable')
      end
    end
  end
end
