# frozen_string_literal: true

# Chatwit: WitDev LLM proxy route for Captain.
#
# When CAPTAIN_LLM_ROUTE is set to 'witdev', every Captain chat call is routed
# through the platform LiteLLM proxy (OpenAI-compatible) over the shared Docker
# network, using a canonical model alias (e.g. witdev_claude/sonnet). The model
# catalog comes from platform-api /api/v1/llm/models, which is the canonical
# contract for listing models (see
# /home/wital/witdev-platform-core/docs/LLM-CANONICAL-FLOW-ALL-APPS.md).
#
# The legacy Chatwoot route (OpenAI/Gemini keys + RubyLLM registry) stays fully
# intact only when the route is 'chatwoot'. An incomplete WitDev route fails
# closed. Embeddings and the OpenAI files API always stay on the legacy path.
module Chatwit::LlmProxy
  DEFAULT_PROXY_URL = 'http://platform-litellm:4000'
  DEFAULT_CATALOG_URL = 'http://platform-api:8000/api/v1/llm/models'
  OPERATIONAL_CATALOG_SOURCE = 'litellm_proxy'
  CATALOG_CACHE_KEY = 'chatwit:witdev_llm_catalog:v2'
  CATALOG_CACHE_TTL = 5.minutes
  CATALOG_TIMEOUT_SECONDS = 5

  CatalogUnavailableError = Class.new(StandardError)
  ModelUnavailableError = Class.new(StandardError)
  MODEL_REGISTRY_MUTEX = Mutex.new.freeze

  class << self
    def enabled?
      route_witdev? && api_key.present? && model.present?
    end

    def route_witdev?
      config_value('CAPTAIN_LLM_ROUTE') == 'witdev'
    end

    # Fields still missing for the witdev route to activate — used by the super
    # admin warning so an incomplete route never falls back to legacy silently.
    def missing_requirements = [('WitDev Model' if model.blank?), ('WitDev Proxy API Key' if api_key.blank?)].compact

    def model = config_value('CAPTAIN_WITDEV_MODEL').presence

    def api_key
      config_value('CAPTAIN_WITDEV_PROXY_API_KEY').presence
    end

    def proxy_url
      config_value('CAPTAIN_WITDEV_PROXY_URL').presence || DEFAULT_PROXY_URL
    end

    def api_base
      "#{proxy_url.chomp('/')}/v1"
    end

    def catalog_url
      config_value('CAPTAIN_WITDEV_CATALOG_URL').presence || DEFAULT_CATALOG_URL
    end

    # The normalized central catalog. It is unavailable unless platform-api
    # returned a non-empty valid model payload.
    def catalog
      Rails.cache.fetch(CATALOG_CACHE_KEY, expires_in: CATALOG_CACHE_TTL) { fetch_catalog }
    rescue StandardError => e
      Rails.logger.error "[CHATWIT][LLM_PROXY] catalog cache failed: #{e.message}"
      unavailable_catalog
    end

    def catalog_models = catalog.fetch('models')

    def catalog_source = catalog.fetch('source')

    def operational_catalog? = catalog_source == OPERATIONAL_CATALOG_SOURCE

    def operational_models
      return [] unless operational_catalog?

      catalog_models.select { |entry| entry['active'] != false && entry['hidden'] != true }
    end

    def resolve_model!(alias_name)
      raise CatalogUnavailableError, 'The canonical LLM catalog is unavailable' unless operational_catalog?

      candidate = alias_name.to_s.presence
      entry = operational_models.find { |model_entry| model_entry['value'] == candidate }
      raise ModelUnavailableError, "LLM model alias is unavailable: #{candidate.presence || '(blank)'}" unless entry

      resolved_alias = entry.fetch('value')
      register_model!(resolved_alias)
      resolved_alias
    end

    # Registers proxy aliases in RubyLLM's in-memory registry as OpenAI-compatible
    # chat models, so both engines (RubyLLM services and the Agents SDK) resolve
    # them without ModelNotFoundError.
    def register_models!
      return unless route_witdev?

      operational_models.filter_map { |entry| entry['value'] }.each { |model_id| register_model!(model_id) }
    end

    private

    def register_model!(model_id)
      MODEL_REGISTRY_MUTEX.synchronize do
        registry = RubyLLM.models.all
        registry << RubyLLM::Model::Info.default(model_id, 'openai') unless registry.any? { |registered| registered.id == model_id }
      end
    end

    def fetch_catalog
      response = HTTParty.get(catalog_url, timeout: CATALOG_TIMEOUT_SECONDS)
      return unavailable_catalog unless response.success?

      payload = response.parsed_response
      return unavailable_catalog unless valid_catalog_payload?(payload)

      models = payload['models'].filter_map { |entry| catalog_entry(entry) }
      return unavailable_catalog if models.empty?

      { 'models' => models, 'source' => payload['source'].presence || 'unavailable' }
    rescue StandardError => e
      Rails.logger.error "[CHATWIT][LLM_PROXY] catalog fetch failed: #{e.message}"
      unavailable_catalog
    end

    def valid_catalog_payload?(payload) = payload.is_a?(Hash) && payload['models'].is_a?(Array)

    def unavailable_catalog = { 'models' => [], 'source' => 'unavailable' }

    def catalog_entry(entry)
      return if (value = entry['value'].presence || entry['alias'].presence).blank?

      {
        'value' => value,
        'label' => entry['label'].presence || entry['displayName'].presence || value,
        **entry.slice('provider', 'source'),
        'provider_label' => provider_label(entry),
        'active' => entry.fetch('active', true),
        'hidden' => entry.fetch('hidden', false),
        'supports_reasoning' => entry['supportsReasoning'] == true,
        'supports_vision' => entry['supportsVision'] == true,
        'supports_json_schema' => entry['supportsJsonSchema'] == true,
        'supports_tools' => entry['supportsTools'] == true,
        'supports_embeddings' => entry['supportsEmbeddings'] == true,
        'recommended_for' => Array(entry['recommendedFor']),
        'input_cost_per_1m' => entry['inputCostPer1M'],
        'output_cost_per_1m' => entry['outputCostPer1M'],
        'context_window' => entry['contextWindow']
      }
    end

    def provider_label(entry) = entry['providerLabel'].presence || entry['provider']

    def config_value(name) = InstallationConfig.find_by(name: name)&.value
  end
end
