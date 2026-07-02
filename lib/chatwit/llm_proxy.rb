# frozen_string_literal: true

# Chatwit: WitDev LLM proxy route for Captain.
#
# When CAPTAIN_LLM_ROUTE is set to 'witdev', every Captain chat call is routed
# through the platform LiteLLM proxy (OpenAI-compatible) over the shared Docker
# network, using a canonical model alias (e.g. witdev_claude/sonnet). The model
# catalog comes from platform-api /api/v1/llm/models, which is the canonical
# contract for listing models (see witdev-platform-core
# docs/agent-memory/llm-model-catalog-contract.md).
#
# The legacy Chatwoot route (OpenAI/Gemini keys + RubyLLM registry) stays fully
# intact and is used whenever the route is 'chatwoot' or the WitDev config is
# incomplete. Embeddings and the OpenAI files API always stay on the legacy path.
module Chatwit::LlmProxy
  DEFAULT_PROXY_URL = 'http://platform-litellm:4000'
  DEFAULT_CATALOG_URL = 'http://platform-api:8000/api/v1/llm/models'
  CATALOG_CACHE_KEY = 'chatwit:witdev_llm_catalog'
  CATALOG_CACHE_TTL = 5.minutes
  CATALOG_TIMEOUT_SECONDS = 5

  class << self
    def enabled?
      route_witdev? && api_key.present? && model.present?
    end

    def route_witdev?
      config_value('CAPTAIN_LLM_ROUTE') == 'witdev'
    end

    # Fields still missing for the witdev route to activate — used by the super
    # admin warning so an incomplete route never falls back to legacy silently.
    def missing_requirements
      requirements = []
      requirements << 'WitDev Model' if model.blank?
      requirements << 'WitDev Proxy API Key' if api_key.blank?
      requirements
    end

    def model
      config_value('CAPTAIN_WITDEV_MODEL').presence
    end

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

    # Central catalog entries: [{ 'value' => alias, 'label' => ..., 'provider_label' => ... }]
    # Returns [] when platform-api is unreachable or the payload is empty.
    def catalog_models
      Rails.cache.fetch(CATALOG_CACHE_KEY, expires_in: CATALOG_CACHE_TTL) { fetch_catalog_models }
    rescue StandardError => e
      Rails.logger.error "[CHATWIT][LLM_PROXY] catalog fetch failed: #{e.message}"
      []
    end

    # Registers proxy aliases in RubyLLM's in-memory registry as OpenAI-compatible
    # chat models, so both engines (RubyLLM services and the Agents SDK) resolve
    # them without ModelNotFoundError. The selected model is always registered,
    # even if the central catalog is unreachable at boot.
    def register_models!
      return unless enabled?

      aliases = catalog_models.filter_map { |entry| entry['value'] }
      aliases |= [model]
      registry = RubyLLM.models.all
      aliases.each do |model_id|
        next if registry.any? { |registered| registered.id == model_id }

        registry << RubyLLM::Model::Info.default(model_id, 'openai')
      end
    end

    private

    def fetch_catalog_models
      response = HTTParty.get(catalog_url, timeout: CATALOG_TIMEOUT_SECONDS)
      return [] unless response.success?

      models = response.parsed_response.is_a?(Hash) ? response.parsed_response['models'] : nil
      return [] unless models.is_a?(Array)

      models.filter_map { |entry| catalog_entry(entry) }
    end

    def catalog_entry(entry)
      value = entry['value'].presence || entry['alias'].presence
      return if value.blank?

      {
        'value' => value,
        'label' => entry['label'].presence || value,
        'provider_label' => entry['providerLabel'].presence || entry['provider']
      }
    end

    def config_value(name)
      InstallationConfig.find_by(name: name)&.value
    end
  end
end
