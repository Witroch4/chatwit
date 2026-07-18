# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Agents do
  let(:agents_config) do
    Struct.new(:openai_api_key, :gemini_api_key, :openai_api_base, :default_model, :debug).new.tap do |config|
      config.default_model = 'gpt-4o-mini'
    end
  end

  before do
    allow(Rails.application.config).to receive(:after_initialize).and_yield
    allow(described_class).to receive(:configure).and_yield(agents_config)
  end

  it 'configures only the resolved proxy model and proxy credentials on the WitDev route' do
    allow(Chatwit::LlmProxy).to receive(:route_witdev?).and_return(true)
    allow(Chatwit::LlmProxy).to receive_messages(
      api_key: nil,
      api_base: 'http://platform-litellm:4000/v1',
      model: 'witdev/global'
    )
    expect(Chatwit::LlmProxy).to receive(:resolve_model!).with('witdev/global').and_return('witdev/global')
    expect(InstallationConfig).not_to receive(:find_by)

    load Rails.root.join('config/initializers/ai_agents.rb')

    expect(agents_config.openai_api_key).to be_nil
    expect(agents_config.openai_api_base).to eq('http://platform-litellm:4000/v1')
    expect(agents_config.default_model).to eq('witdev/global')
  end

  it 'keeps proxy credentials configured when the catalog is unavailable at boot' do
    allow(Chatwit::LlmProxy).to receive(:route_witdev?).and_return(true)
    allow(Chatwit::LlmProxy).to receive_messages(
      api_key: 'witdev-key',
      api_base: 'http://platform-litellm:4000/v1',
      model: 'witdev/global'
    )
    allow(Chatwit::LlmProxy).to receive(:resolve_model!)
      .with('witdev/global')
      .and_raise(Chatwit::LlmProxy::CatalogUnavailableError, 'catalog unavailable')
    expect(InstallationConfig).not_to receive(:find_by)

    load Rails.root.join('config/initializers/ai_agents.rb')

    expect(agents_config.openai_api_key).to eq('witdev-key')
    expect(agents_config.openai_api_base).to eq('http://platform-litellm:4000/v1')
    expect(agents_config.default_model).to be_nil
  end

  it 'retains the legacy Agents configuration on the Chatwoot route' do
    allow(Chatwit::LlmProxy).to receive(:route_witdev?).and_return(false)
    values = {
      'CAPTAIN_OPEN_AI_API_KEY' => 'legacy-key',
      'CAPTAIN_GEMINI_API_KEY' => nil,
      'CAPTAIN_OPEN_AI_MODEL' => 'gpt-4-turbo',
      'CAPTAIN_OPEN_AI_ENDPOINT' => 'https://legacy.example'
    }
    allow(InstallationConfig).to receive(:find_by) do |name:|
      value = values.fetch(name)
      instance_double(InstallationConfig, value: value)
    end

    load Rails.root.join('config/initializers/ai_agents.rb')

    expect(agents_config.openai_api_key).to eq('legacy-key')
    expect(agents_config.openai_api_base).to eq('https://legacy.example/v1')
    expect(agents_config.default_model).to eq('gpt-4-turbo')
  end
end
