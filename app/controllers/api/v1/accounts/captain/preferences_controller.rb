class Api::V1::Accounts::Captain::PreferencesController < Api::V1::Accounts::BaseController
  before_action :authorize_account_update, only: [:update]

  def show
    render json: preferences_payload
  end

  def update
    params_to_update = captain_params
    @current_account.captain_models = params_to_update[:captain_models] if params_to_update.key?(:captain_models)
    @current_account.captain_features = params_to_update[:captain_features] if params_to_update.key?(:captain_features)
    @current_account.save!

    render json: preferences_payload
  rescue Chatwit::LlmProxy::CatalogUnavailableError, Chatwit::LlmProxy::ModelUnavailableError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def preferences_payload
    return legacy_preferences_payload unless Chatwit::LlmProxy.route_witdev?

    resolver = Chatwit::CaptainModelResolver.new(account: @current_account)
    {
      providers: resolver.providers_payload,
      models: resolver.models_payload,
      features: Llm::Models.feature_keys.index_with { |feature| resolver.feature_config(feature) },
      catalog: {
        route: 'witdev',
        source: Chatwit::LlmProxy.catalog_source,
        operational: Chatwit::LlmProxy.operational_catalog?
      }
    }
  end

  def legacy_preferences_payload
    {
      providers: Llm::Models.providers,
      models: Llm::Models.models,
      features: features_with_account_preferences
    }
  end

  def authorize_account_update
    authorize @current_account, :update?
  end

  def captain_params
    permitted = {}
    if params[:captain_models].present?
      models = permitted_captain_models
      validate_witdev_models!(models)
      permitted[:captain_models] = merged_captain_models(models)
    end
    permitted[:captain_features] = merged_captain_features if params[:captain_features].present?
    permitted
  end

  def merged_captain_models(models)
    existing_models = @current_account.captain_models || {}
    existing_models.merge(models).compact_blank.presence
  end

  def merged_captain_features
    existing_features = @current_account.captain_features || {}
    existing_features.merge(permitted_captain_features)
  end

  def permitted_captain_models
    params.require(:captain_models).permit(*captain_feature_keys).to_h.stringify_keys
  end

  def permitted_captain_features
    params.require(:captain_features).permit(*captain_feature_keys).to_h.stringify_keys
  end

  def captain_feature_keys
    Llm::Models.feature_keys.map(&:to_sym)
  end

  def validate_witdev_models!(models)
    return unless Chatwit::LlmProxy.route_witdev?

    resolver = Chatwit::CaptainModelResolver.new(account: @current_account)
    models.each { |feature, alias_name| resolver.validate!(feature, alias_name) if alias_name.present? }
  end

  def features_with_account_preferences
    preferences = Current.account.captain_preferences
    account_features = preferences[:features] || {}

    Llm::Models.feature_keys.index_with do |feature_key|
      config = Llm::Models.feature_config(feature_key)
      route = Llm::FeatureRouter.resolve(feature: feature_key, account: Current.account)
      config.merge(
        default: default_model_for(feature_key),
        enabled: account_features[feature_key] == true,
        model: route[:model],
        selected: route[:model],
        provider: route[:provider],
        source: route[:source]
      )
    end
  end

  def default_model_for(feature_key)
    return Llm::FeatureRouter::CAPTAIN_V2_ASSISTANT_MODEL if feature_key == 'assistant' && Current.account.feature_enabled?('captain_integration_v2')

    Llm::Models.default_model_for(feature_key)
  end
end
