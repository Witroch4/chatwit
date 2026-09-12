# Chatwit: refresh do App ID / provider config de um canal WhatsApp Cloud.
# Mantido fora de InboxHealthManagement (upstream) para não conflitar em syncs futuros.
module Api::V1::Accounts::Concerns::WhatsappProviderConfigManagement
  extend ActiveSupport::Concern

  included do
    skip_before_action :check_authorization, only: [:refresh_whatsapp_provider_config]
    before_action :check_admin_authorization?, only: [:refresh_whatsapp_provider_config]
    before_action :validate_whatsapp_cloud_channel, only: [:refresh_whatsapp_provider_config]
  end

  def refresh_whatsapp_provider_config
    result = Whatsapp::ProviderConfigRefreshService
             .new(@inbox.channel, whatsapp_app_id: params[:whatsapp_app_id])
             .perform
    return render json: result, status: :ok if result[:success]

    render json: result, status: :unprocessable_entity
  rescue StandardError => e
    Rails.logger.error "[INBOX WHATSAPP CONFIG] Provider config refresh failed: #{e.message}"
    render json: { success: false, error: e.message }, status: :unprocessable_entity
  end

  private

  def validate_whatsapp_cloud_channel
    return if whatsapp_cloud_channel?

    render json: { error: 'Provider config refresh is only available for WhatsApp Cloud API channels' }, status: :bad_request
  end
end
