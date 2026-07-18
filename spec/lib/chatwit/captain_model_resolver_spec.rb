# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Chatwit::CaptainModelResolver do
  let(:account) { build(:account, captain_models: { 'editor' => 'witdev/gpt-5.5' }) }
  let(:resolver) { described_class.new(account: account) }
  let(:models) do
    [{ 'value' => 'witdev/gpt-5.5', 'label' => 'GPT-5.5', 'provider' => 'witdev',
       'provider_label' => 'WitDev Codex', 'active' => true, 'hidden' => false }]
  end

  before do
    allow(Chatwit::LlmProxy).to receive(:model).and_return('witdev_claude/sonnet')
    allow(Chatwit::LlmProxy).to receive(:operational_models).and_return(models)
    allow(Chatwit::LlmProxy).to receive(:resolve_model!) { |alias_name| alias_name }
  end

  it 'uses the account alias before the global alias' do
    expect(resolver.selected_alias(:editor)).to eq('witdev/gpt-5.5')
    expect(resolver.resolve!(:editor)).to eq('witdev/gpt-5.5')
  end

  it 'uses the global alias when the account has no feature selection' do
    expect(resolver.selected_alias(:assistant)).to eq('witdev_claude/sonnet')
  end

  it 'builds feature options from central descriptors' do
    expect(resolver.feature_config(:editor)).to include(
      default: 'witdev_claude/sonnet',
      selected: 'witdev/gpt-5.5',
      selection_valid: true
    )
    expect(resolver.feature_config(:editor)[:models].first).to include(
      id: 'witdev/gpt-5.5', display_name: 'GPT-5.5', provider: 'witdev'
    )
  end

  it 'delegates exact alias validation to the proxy catalog' do
    expect(Chatwit::LlmProxy).to receive(:resolve_model!).with('witdev/gpt-5.5')
    resolver.validate!(:editor, 'witdev/gpt-5.5')
  end
end
