class Api::V1::Accounts::Captain::PreferencesController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :authorize_account_update, only: [:update]

  def show
    render json: preferences_payload
  end

  def update
    params_to_update = captain_params
    @current_account.captain_models = params_to_update[:captain_models] if params_to_update[:captain_models]
    @current_account.captain_features = params_to_update[:captain_features] if params_to_update[:captain_features]
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
    existing_models.merge(models)
  end

  def merged_captain_features
    existing_features = @current_account.captain_features || {}
    existing_features.merge(permitted_captain_features)
  end

  def permitted_captain_models
    params.require(:captain_models).permit(
      :editor, :assistant, :copilot, :label_suggestion,
      :audio_transcription, :help_center_search
    ).to_h.stringify_keys
  end

  def permitted_captain_features
    params.require(:captain_features).permit(
      :editor, :assistant, :copilot, :label_suggestion,
      :audio_transcription, :help_center_search
    ).to_h.stringify_keys
  end

  def validate_witdev_models!(models)
    return unless Chatwit::LlmProxy.route_witdev?

    resolver = Chatwit::CaptainModelResolver.new(account: @current_account)
    models.each { |feature, alias_name| resolver.validate!(feature, alias_name) }
  end

  def features_with_account_preferences
    preferences = Current.account.captain_preferences
    account_features = preferences[:features] || {}
    account_models = preferences[:models] || {}

    Llm::Models.feature_keys.index_with do |feature_key|
      config = Llm::Models.feature_config(feature_key)
      config.merge(
        enabled: account_features[feature_key] == true,
        selected: account_models[feature_key] || config[:default]
      )
    end
  end
end
