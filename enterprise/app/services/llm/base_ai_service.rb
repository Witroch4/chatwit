# frozen_string_literal: true

# Base service for LLM operations using RubyLLM.
# New features should inherit from this class.
class Llm::BaseAiService
  DEFAULT_MODEL = Llm::Config::DEFAULT_MODEL
  DEFAULT_TEMPERATURE = 1.0

  attr_reader :model, :temperature

  def initialize(feature: nil, account: nil, fallback_model: nil)
    @llm_feature = feature
    @llm_account = account
    @fallback_model = fallback_model

    Llm::Config.initialize!
    setup_model
    setup_temperature
  end

  def chat(model: @model, temperature: @temperature)
    RubyLLM.chat(model: model).with_temperature(temperature)
  end

  private

  # Strips markdown code fences (```json ... ``` or ``` ... ```) that some
  # LLM providers/gateways wrap around JSON responses despite response_format hints.
  def sanitize_json_response(response)
    return response if response.nil?

    response.strip.sub(/\A```(?:\w*)\s*\n?/, '').sub(/\n?\s*```\s*\z/, '').strip
  end

  def setup_model
    @model = resolved_model
  end

  def resolved_model
    return Chatwit::LlmProxy.resolve_model!(Chatwit::LlmProxy.model) if witdev_global_route?

    route = feature_route
    return route[:model] if preferred_feature_route?(route)

    @fallback_model.presence || installation_model.presence || route&.dig(:model) || DEFAULT_MODEL
  end

  def witdev_global_route?
    Chatwit::LlmProxy.route_witdev? && @llm_feature.blank?
  end

  def preferred_feature_route?(route)
    (Chatwit::LlmProxy.route_witdev? && witdev_generative_feature?) || account_override_route?(route) || captain_v2_assistant?
  end

  def feature_route
    return if @llm_feature.blank?

    Llm::FeatureRouter.resolve(feature: @llm_feature, account: @llm_account)
  end

  def account_override_route?(route)
    route&.dig(:source) == :account_override
  end

  def captain_v2_assistant?
    @llm_feature.to_s == 'assistant' && @llm_account&.feature_enabled?('captain_integration_v2')
  end

  def installation_model
    InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value
  end

  def witdev_generative_feature?
    Chatwit::CaptainModelResolver.generative_feature?(@llm_feature)
  end

  def setup_temperature
    @temperature = DEFAULT_TEMPERATURE
  end
end
