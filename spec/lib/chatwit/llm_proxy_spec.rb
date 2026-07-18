# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Chatwit::LlmProxy do
  around do |example|
    previous_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
  ensure
    Rails.cache = previous_cache
  end

  let(:response) { instance_double(HTTParty::Response, success?: true, parsed_response: payload) }
  let(:model) do
    {
      'value' => 'witdev_claude/sonnet',
      'label' => 'Claude Sonnet',
      'provider' => 'witdev_claude',
      'providerLabel' => 'WitDev Claude Code',
      'source' => 'litellm_proxy',
      'active' => true,
      'hidden' => false,
      'supportsTools' => true,
      'supportsJsonSchema' => true,
      'recommendedFor' => ['captain']
    }
  end
  let(:payload) { { 'source' => 'litellm_proxy', 'models' => [model] } }

  before do
    allow(described_class).to receive(:catalog_url).and_return('http://platform-api:8000/api/v1/llm/models')
    allow(HTTParty).to receive(:get).and_return(response)
  end

  it 'preserves the central source and authorization metadata' do
    expect(described_class.catalog_source).to eq('litellm_proxy')
    expect(described_class.catalog_models.first).to include(
      'value' => 'witdev_claude/sonnet',
      'provider' => 'witdev_claude',
      'provider_label' => 'WitDev Claude Code',
      'source' => 'litellm_proxy',
      'active' => true,
      'hidden' => false,
      'supports_tools' => true,
      'supports_json_schema' => true,
      'recommended_for' => ['captain']
    )
  end

  it 'resolves an active visible alias from the operational catalog' do
    expect(described_class.resolve_model!('witdev_claude/sonnet')).to eq('witdev_claude/sonnet')
  end

  it 'does not authorize a non-operational fallback source' do
    payload['source'] = 'legacy_socialwise'

    expect(described_class.operational_models).to eq([])
    expect { described_class.resolve_model!('witdev_claude/sonnet') }
      .to raise_error(Chatwit::LlmProxy::CatalogUnavailableError)
  end

  it 'rejects a hidden alias' do
    model['hidden'] = true

    expect { described_class.resolve_model!('witdev_claude/sonnet') }
      .to raise_error(Chatwit::LlmProxy::ModelUnavailableError)
  end

  it 'rejects an inactive alias' do
    model['active'] = false

    expect { described_class.resolve_model!('witdev_claude/sonnet') }
      .to raise_error(Chatwit::LlmProxy::ModelUnavailableError)
  end

  it 'rejects an absent alias' do
    expect { described_class.resolve_model!('witdev_claude/missing') }
      .to raise_error(Chatwit::LlmProxy::ModelUnavailableError)
  end

  it 'rejects a blank alias' do
    expect { described_class.resolve_model!('') }
      .to raise_error(Chatwit::LlmProxy::ModelUnavailableError, /\(blank\)/)
  end

  it 'treats a catalog without a top-level source as unavailable' do
    payload.delete('source')

    expect(described_class.catalog_source).to eq('unavailable')
    expect { described_class.resolve_model!('witdev_claude/sonnet') }
      .to raise_error(Chatwit::LlmProxy::CatalogUnavailableError)
  end

  it 'does not register a configured alias when the catalog is non-operational' do
    payload['source'] = 'legacy_socialwise'
    registry = []
    allow(described_class).to receive(:route_witdev?).and_return(true)
    allow(described_class).to receive(:enabled?).and_return(true)
    allow(described_class).to receive(:model).and_return('configured-but-unverified')
    allow(RubyLLM.models).to receive(:all).and_return(registry)

    described_class.register_models!

    expect(registry).to be_empty
  end

  it 'registers an exact alias only after the catalog recovers and authorizes it' do
    registry = []
    allow(described_class).to receive_messages(route_witdev?: true, enabled?: true)
    allow(RubyLLM.models).to receive(:all).and_return(registry)
    allow(HTTParty).to receive(:get).and_raise(Net::OpenTimeout, 'execution expired')

    described_class.register_models!
    expect(registry).to be_empty

    allow(HTTParty).to receive(:get).and_return(response)
    travel_to(Time.current + described_class::CATALOG_CACHE_TTL + 1.second) do
      expect(described_class.resolve_model!('witdev_claude/sonnet')).to eq('witdev_claude/sonnet')
    end

    expect(registry.map(&:id)).to contain_exactly('witdev_claude/sonnet')
  end

  it 'does not register an alias that fails operational authorization' do
    registry = []
    model['hidden'] = true
    allow(RubyLLM.models).to receive(:all).and_return(registry)

    expect { described_class.resolve_model!('witdev_claude/sonnet') }
      .to raise_error(Chatwit::LlmProxy::ModelUnavailableError)
    expect(registry).to be_empty
  end

  it 'registers an authorized alias idempotently across repeated resolutions' do
    registry = []
    allow(RubyLLM.models).to receive(:all).and_return(registry)

    2.times { expect(described_class.resolve_model!('witdev_claude/sonnet')).to eq('witdev_claude/sonnet') }

    expect(registry.map(&:id)).to contain_exactly('witdev_claude/sonnet')
  end

  it 'returns an unavailable catalog for HTTP failure' do
    allow(response).to receive(:success?).and_return(false)

    expect(described_class.catalog).to eq('models' => [], 'source' => 'unavailable')
  end

  it 'caches an unavailable catalog when the HTTP client raises' do
    expect(HTTParty).to receive(:get).once.and_raise(Net::OpenTimeout, 'execution expired')

    2.times do
      expect(described_class.catalog).to eq('models' => [], 'source' => 'unavailable')
    end
  end

  it 'returns an unavailable catalog when the cache store raises' do
    allow(Rails.cache).to receive(:fetch).and_raise(StandardError, 'cache unavailable')

    expect(described_class.catalog).to eq('models' => [], 'source' => 'unavailable')
  end
end
