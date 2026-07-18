# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Llm::Config do
  describe '.configure_openai' do
    let(:config) { Struct.new(:openai_api_key, :openai_api_base).new }

    it 'uses only proxy configuration when the WitDev route is selected' do
      allow(Chatwit::LlmProxy).to receive(:route_witdev?).and_return(true)
      allow(Chatwit::LlmProxy).to receive_messages(api_key: nil, api_base: 'http://platform-litellm:4000/v1')
      expect(described_class).not_to receive(:system_api_key)
      expect(described_class).not_to receive(:openai_endpoint)

      described_class.send(:configure_openai, config)

      expect(config.openai_api_key).to be_nil
      expect(config.openai_api_base).to eq('http://platform-litellm:4000/v1')
    end

    it 'retains the legacy key and endpoint on the Chatwoot route' do
      allow(Chatwit::LlmProxy).to receive(:route_witdev?).and_return(false)
      allow(described_class).to receive_messages(system_api_key: 'legacy-key', openai_endpoint: 'https://legacy.example/')

      described_class.send(:configure_openai, config)

      expect(config.openai_api_key).to eq('legacy-key')
      expect(config.openai_api_base).to eq('https://legacy.example')
    end
  end
end
