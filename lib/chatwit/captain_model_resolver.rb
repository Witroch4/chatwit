# frozen_string_literal: true

class Chatwit::CaptainModelResolver
  GENERATIVE_FEATURES = %w[editor assistant copilot label_suggestion].freeze

  def initialize(account:)
    @account = account
  end

  def self.generative_feature?(feature)
    GENERATIVE_FEATURES.include?(feature.to_s)
  end

  def selected_alias(feature)
    stored_models[feature.to_s].presence || Chatwit::LlmProxy.model
  end

  def resolve!(feature)
    Chatwit::LlmProxy.resolve_model!(selected_alias(feature))
  end

  def validate!(feature, alias_name)
    return unless self.class.generative_feature?(feature)

    Chatwit::LlmProxy.resolve_model!(alias_name)
  end

  def feature_config(feature)
    feature_name = feature.to_s
    return legacy_feature_config(feature_name) unless self.class.generative_feature?(feature_name)

    selected = selected_alias(feature_name)
    {
      models: model_options,
      default: Chatwit::LlmProxy.model,
      selected: selected,
      selection_valid: Chatwit::LlmProxy.operational_models.any? { |entry| entry['value'] == selected },
      enabled: account.captain_preferences[:features][feature_name] == true
    }
  end

  def model_options
    Chatwit::LlmProxy.operational_models.map { |entry| model_option(entry) }
  end

  def models_payload
    model_options.index_by { |option| option.fetch(:id) }
  end

  def providers_payload
    Chatwit::LlmProxy.operational_models.each_with_object({}) do |entry, providers|
      provider = entry['provider'].presence || 'unknown'
      providers[provider] ||= { display_name: entry['provider_label'].presence || provider }
    end
  end

  private

  attr_reader :account

  def stored_models
    account.captain_models || {}
  end

  def legacy_feature_config(feature)
    config = Llm::Models.feature_config(feature)
    preferences = account.captain_preferences
    config.merge(
      enabled: preferences[:features][feature] == true,
      selected: preferences[:models][feature],
      selection_valid: true
    )
  end

  def model_option(entry)
    {
      id: entry['value'],
      display_name: entry['label'],
      provider: entry['provider'],
      provider_label: entry['provider_label'],
      coming_soon: false,
      credit_multiplier: nil
    }
  end
end
