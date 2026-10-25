# frozen_string_literal: true

require 'agents'

module Chatwit::AiAgentsConfiguration
  def self.configure_witdev
    Agents.configure do |config|
      config.openai_api_key = Chatwit::LlmProxy.api_key
      config.openai_api_base = Chatwit::LlmProxy.api_base
      config.openai_protocol = :chat_completions
      config.debug = false
      config.default_model = nil
      begin
        config.default_model = Chatwit::LlmProxy.resolve_model!(Chatwit::LlmProxy.model)
      rescue Chatwit::LlmProxy::CatalogUnavailableError, Chatwit::LlmProxy::ModelUnavailableError => e
        Rails.logger.error "Failed to configure AI Agents SDK default WitDev model: #{e.message}"
      end
    end
  end
end

Rails.application.config.after_initialize do
  # Chatwit: WitDev route drives the Agents SDK through the platform LiteLLM
  # proxy (OpenAI-compatible) with the canonical model alias.
  if Chatwit::LlmProxy.route_witdev?
    Chatwit::AiAgentsConfiguration.configure_witdev
  else
    api_key = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_API_KEY')&.value
    gemini_api_key = InstallationConfig.find_by(name: 'CAPTAIN_GEMINI_API_KEY')&.value
    model = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value.presence || LlmConstants::DEFAULT_MODEL
    api_endpoint = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_ENDPOINT')&.value || LlmConstants::OPENAI_API_ENDPOINT

    Agents.configure do |config|
      config.openai_api_key = api_key if api_key.present?
      config.gemini_api_key = gemini_api_key if gemini_api_key.present?
      if api_key.present? && api_endpoint.present?
        api_base = "#{api_endpoint.chomp('/')}/v1"
        config.openai_api_base = api_base
      end
      config.default_model = model
      config.openai_protocol = :chat_completions
      config.model_registry_file = Rails.root.join('config/llm_models.json').to_s
      config.debug = false
    end
  end
rescue StandardError => e
  Rails.logger.error "Failed to configure AI Agents SDK: #{e.message}"
end
