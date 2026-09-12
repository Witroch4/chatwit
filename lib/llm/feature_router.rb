module Llm::FeatureRouter
  class UnknownFeatureError < StandardError; end

  CAPTAIN_V2_ASSISTANT_MODEL = 'gpt-5.2'.freeze

  class << self
    def resolve(feature:, account: nil)
      feature_key = feature.to_s
      raise UnknownFeatureError, "Unknown LLM feature: #{feature_key}" unless Llm::Models.feature?(feature_key)

      return resolve_witdev(feature_key, account) if witdev_generative_feature?(feature_key)

      model, source = model_and_source(account, feature_key)

      {
        feature: feature_key,
        provider: provider_for(model, source),
        model: model,
        source: source
      }
    end

    private

    def resolve_witdev(feature_key, account)
      resolver = Chatwit::CaptainModelResolver.new(account: account)
      selected_by_account = account&.captain_models&.[](feature_key).present?
      model = resolver.resolve!(feature_key)
      descriptor = Chatwit::LlmProxy.operational_models.find { |entry| entry['value'] == model }
      raise Chatwit::LlmProxy::ModelUnavailableError, "LLM model alias is unavailable: #{model}" unless descriptor

      {
        feature: feature_key,
        provider: descriptor['provider'],
        model: model,
        source: selected_by_account ? :account_override : :witdev_default
      }
    end

    def witdev_generative_feature?(feature_key)
      Chatwit::LlmProxy.route_witdev? && Chatwit::CaptainModelResolver.generative_feature?(feature_key)
    end

    def model_and_source(account, feature_key)
      account_model = account_model_override(account, feature_key)
      return [account_model, :account_override] if account_model.present?

      installation_model = installation_model_override(feature_key)
      return [installation_model, :installation_override] if installation_model.present?

      [captain_v2_assistant_model(account, feature_key) || Llm::Models.default_model_for(feature_key), :default]
    end

    def account_model_override(account, feature_key)
      model = account&.captain_models&.[](feature_key).presence
      return unless model
      return model if Llm::Models.valid_model_for?(feature_key, model)
    end

    def installation_model_override(feature_key)
      return unless feature_key == 'conversation_completion'
      return unless ChatwootApp.self_hosted_paid?

      InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value.presence
    end

    def provider_for(model, source)
      Llm::Models.provider_for(model) || ('openai' if source == :installation_override)
    end

    def captain_v2_assistant_model(account, feature_key)
      return unless feature_key == 'assistant'
      return unless account&.feature_enabled?('captain_integration_v2')

      CAPTAIN_V2_ASSISTANT_MODEL
    end
  end
end
