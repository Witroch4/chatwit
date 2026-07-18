# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Captain::Llm::EmbeddingService do
  let(:service) { described_class.new(account_id: 123) }
  let(:embedding) { instance_double(RubyLLM::Embedding, vectors: [[0.1, 0.2]]) }

  before do
    allow(Llm::Config).to receive(:initialize!)
    allow(ChatwootApp).to receive(:otel_enabled?).and_return(false)
  end

  it 'uses an explicit legacy context on the WitDev route even when the proxy is not enabled' do
    allow(Chatwit::LlmProxy).to receive_messages(route_witdev?: true, enabled?: false)
    create(:installation_config, name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'legacy-key')
    create(:installation_config, name: 'CAPTAIN_OPEN_AI_ENDPOINT', value: 'https://legacy.example/')
    context = instance_double(RubyLLM::Context)

    expect(RubyLLM).not_to receive(:embed)
    expect(Llm::Config).to receive(:with_api_key).with('legacy-key', api_base: 'https://legacy.example').and_yield(context)
    expect(context).to receive(:embed).with('hello', model: LlmConstants::DEFAULT_EMBEDDING_MODEL).and_return(embedding)

    expect(service.get_embedding('hello')).to eq([[0.1, 0.2]])
  end

  it 'preserves the global RubyLLM embedding path on the Chatwoot route' do
    allow(Chatwit::LlmProxy).to receive(:route_witdev?).and_return(false)
    expect(Llm::Config).not_to receive(:with_api_key)
    expect(RubyLLM).to receive(:embed).with('hello', model: LlmConstants::DEFAULT_EMBEDDING_MODEL).and_return(embedding)

    expect(service.get_embedding('hello')).to eq([[0.1, 0.2]])
  end
end
