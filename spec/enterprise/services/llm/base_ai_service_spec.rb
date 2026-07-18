require 'rails_helper'

RSpec.describe Llm::BaseAiService do
  subject(:service) { described_class.new }

  before do
    create(:installation_config, name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'test-key')
    allow(Chatwit::LlmProxy).to receive(:route_witdev?).and_return(false)
  end

  describe '#sanitize_json_response' do
    it 'strips ```json fences' do
      input = "```json\n{\"key\": \"value\"}\n```"
      expect(service.send(:sanitize_json_response, input)).to eq('{"key": "value"}')
    end

    it 'strips bare ``` fences' do
      input = "```\n{\"key\": \"value\"}\n```"
      expect(service.send(:sanitize_json_response, input)).to eq('{"key": "value"}')
    end

    it 'passes through plain JSON unchanged' do
      input = '{"key": "value"}'
      expect(service.send(:sanitize_json_response, input)).to eq('{"key": "value"}')
    end

    it 'returns nil for nil input' do
      expect(service.send(:sanitize_json_response, nil)).to be_nil
    end

    it 'strips surrounding whitespace' do
      input = "  \n{\"key\": \"value\"}\n  "
      expect(service.send(:sanitize_json_response, input)).to eq('{"key": "value"}')
    end
  end

  describe 'model setup' do
    it 'retains the installation model on the legacy route' do
      create(:installation_config, name: 'CAPTAIN_OPEN_AI_MODEL', value: 'gpt-4-turbo')

      expect(service.model).to eq('gpt-4-turbo')
    end

    it 'resolves the configured global alias before using the WitDev route' do
      allow(Chatwit::LlmProxy).to receive(:route_witdev?).and_return(true)
      allow(Chatwit::LlmProxy).to receive(:model).and_return('witdev/global')
      expect(Chatwit::LlmProxy).to receive(:resolve_model!).with('witdev/global').and_return('witdev/global')

      expect(service.model).to eq('witdev/global')
    end
  end
end
