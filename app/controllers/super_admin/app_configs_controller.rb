class SuperAdmin::AppConfigsController < SuperAdmin::ApplicationController
  # Chatwit: WitDev LLM proxy route configs (Captain via platform LiteLLM proxy)
  CHATWIT_WITDEV_LLM_CONFIGS = %w[
    CAPTAIN_LLM_ROUTE
    CAPTAIN_WITDEV_MODEL
    CAPTAIN_WITDEV_PROXY_API_KEY
    CAPTAIN_WITDEV_PROXY_URL
    CAPTAIN_WITDEV_CATALOG_URL
    CAPTAIN_WITDEV_TRANSCRIPTION_MODEL
  ].freeze

  before_action :set_config
  before_action :allowed_configs
  def show
    # ref: https://github.com/rubocop/rubocop/issues/7767
    # rubocop:disable Style/HashTransformValues
    @app_config = InstallationConfig.where(name: @allowed_configs)
                                    .pluck(:name, :serialized_value)
                                    .map { |name, serialized_value| [name, serialized_value['value']] }
                                    .to_h
    # rubocop:enable Style/HashTransformValues
    @installation_configs = ConfigLoader.new.general_configs.each_with_object({}) do |config_hash, result|
      result[config_hash['name']] = config_hash.except('name')
    end
    inject_witdev_model_options
    set_witdev_route_warning
  end

  def create
    errors = []
    params['app_config'].each do |key, value|
      next unless @allowed_configs.include?(key)

      i = InstallationConfig.where(name: key).first_or_create(value: value, locked: false)
      i.value = value
      errors.concat(i.errors.full_messages) unless i.save
    end

    if errors.any?
      redirect_to super_admin_app_config_path(config: @config), alert: errors.join(', ')
    else
      redirect_to super_admin_settings_path, notice: "App Configs - #{@config.titleize} updated successfully"
    end
  end

  private

  def set_config
    @config = params[:config] || 'general'
  end

  def allowed_configs
    mapping = {
      'facebook' => %w[FB_APP_ID FB_VERIFY_TOKEN FB_APP_SECRET IG_VERIFY_TOKEN FACEBOOK_API_VERSION ENABLE_MESSENGER_CHANNEL_HUMAN_AGENT],
      'shopify' => %w[SHOPIFY_CLIENT_ID SHOPIFY_CLIENT_SECRET],
      'microsoft' => %w[AZURE_APP_ID AZURE_APP_SECRET],
      'email' => %w[MAILER_INBOUND_EMAIL_DOMAIN ACCOUNT_EMAILS_LIMIT ACCOUNT_EMAILS_PLAN_LIMITS],
      'linear' => %w[LINEAR_CLIENT_ID LINEAR_CLIENT_SECRET],
      'slack' => %w[SLACK_CLIENT_ID SLACK_CLIENT_SECRET],
      'instagram' => %w[INSTAGRAM_APP_ID INSTAGRAM_APP_SECRET INSTAGRAM_VERIFY_TOKEN INSTAGRAM_API_VERSION ENABLE_INSTAGRAM_CHANNEL_HUMAN_AGENT],
      'tiktok' => %w[TIKTOK_APP_ID TIKTOK_APP_SECRET TIKTOK_API_VERSION],
      'whatsapp_embedded' => %w[WHATSAPP_APP_ID WHATSAPP_APP_SECRET WHATSAPP_CONFIGURATION_ID WHATSAPP_API_VERSION],
      'notion' => %w[NOTION_CLIENT_ID NOTION_CLIENT_SECRET],
      'google' => %w[GOOGLE_OAUTH_CLIENT_ID GOOGLE_OAUTH_CLIENT_SECRET GOOGLE_OAUTH_REDIRECT_URI ENABLE_GOOGLE_OAUTH_LOGIN],
      'captain' => %w[CAPTAIN_OPEN_AI_API_KEY CAPTAIN_GEMINI_API_KEY CAPTAIN_OPEN_AI_MODEL CAPTAIN_OPEN_AI_ENDPOINT] + CHATWIT_WITDEV_LLM_CONFIGS
    }

    @allowed_configs = mapping.fetch(
      @config,
      %w[ENABLE_ACCOUNT_SIGNUP FIREBASE_PROJECT_ID FIREBASE_CREDENTIALS WEBHOOK_TIMEOUT MAXIMUM_FILE_UPLOAD_SIZE WIDGET_TOKEN_EXPIRY]
    )
  end

  # Chatwit: turn CAPTAIN_WITDEV_MODEL into a select fed live by the platform
  # LLM catalog. When the catalog is unreachable/empty it stays a text field
  # so the alias can be typed manually (local fallback per platform contract).
  def inject_witdev_model_options
    return unless @allowed_configs.include?('CAPTAIN_WITDEV_MODEL')

    options = Chatwit::LlmProxy.catalog_models.to_h do |entry|
      [entry['value'], "#{entry['label']} — #{entry['provider_label']}"]
    end
    return if options.blank?

    apply_select_options('CAPTAIN_WITDEV_MODEL', options)
    apply_select_options('CAPTAIN_WITDEV_TRANSCRIPTION_MODEL', transcription_options(options))
  end

  # Captain Whisper: only audio-capable aliases (copilot hallucinates audio,
  # codex/claude reject it), recommended (tested) alias always listed first,
  # even if the central catalog does not include it.
  def transcription_options(options)
    audio_options = options.select { |value, _label| Chatwit::AudioTranscriptionService.audio_capable?(value) }
    recommended = Chatwit::AudioTranscriptionService::RECOMMENDED_MODEL
    recommended_label = "#{audio_options[recommended].presence || recommended} (recommended)"
    { recommended => recommended_label }.merge(audio_options.except(recommended))
  end

  def apply_select_options(key, options)
    config = (@installation_configs[key] ||= {})
    config['type'] = 'select'
    config['options'] = options
  end

  # Chatwit: LLM Route = witdev with missing fields silently falls back to the
  # legacy path (zero regression by design) — surface that instead of hiding it.
  def set_witdev_route_warning
    return unless @allowed_configs.include?('CAPTAIN_LLM_ROUTE')
    return unless Chatwit::LlmProxy.route_witdev? && !Chatwit::LlmProxy.enabled?

    missing = Chatwit::LlmProxy.missing_requirements.join(', ')
    @chatwit_witdev_warning = 'LLM Route is set to WitDev LLM Proxy but the route is INACTIVE — Captain is still using the legacy ' \
                              "Chatwoot path. Missing: #{missing}. Fill the field(s) below and restart the app."
  end
end

SuperAdmin::AppConfigsController.prepend_mod_with('SuperAdmin::AppConfigsController')
