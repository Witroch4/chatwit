class SendReplyJob < ApplicationJob
  queue_as :high

  CHANNEL_SERVICES = {
    'Channel::TwitterProfile' => ::Twitter::SendOnTwitterService,
    'Channel::TwilioSms' => ::Twilio::SendOnTwilioService,
    'Channel::Line' => ::Line::SendOnLineService,
    'Channel::Telegram' => ::Telegram::SendOnTelegramService,
    'Channel::Whatsapp' => ::Whatsapp::SendOnWhatsappService,
    'Channel::Sms' => ::Sms::SendOnSmsService,
    'Channel::Instagram' => ::Instagram::SendOnInstagramService,
    'Channel::Tiktok' => ::Tiktok::SendOnTiktokService,
    'Channel::Email' => ::Email::SendOnEmailService,
    'Channel::WebWidget' => ::Messages::SendEmailNotificationService,
    'Channel::Api' => ::Messages::SendEmailNotificationService
  }.freeze

  def perform(message_id)
    message = Message.find(message_id)
    return if socialwise_ownership_fence_blocks?(message)

    channel_name = message.conversation.inbox.channel.class.to_s

    return if send_meta_rich_message(message)

    return send_on_facebook_page(message) if channel_name == 'Channel::FacebookPage'

    service_class = CHANNEL_SERVICES[channel_name]
    return unless service_class

    service_class.new(message: message).perform
  end

  private

  # Permit fence for the async delivery path: a message tagged with the Socialwise
  # ownership epoch it was composed under must not reach the provider if ownership
  # has since moved (phase-2 handoff, an eligible trigger or an active run). Messages
  # without the marker — including already-authorized phase-2 composites — deliver
  # normally.
  def socialwise_ownership_fence_blocks?(message)
    epoch = message.additional_attributes&.dig('socialwise_ownership_epoch')
    return false if epoch.blank?

    !Integrations::SocialwiseFlow::OwnershipGuard.new(message.conversation).can_publish?(epoch: epoch)
  end

  # Mensagens interativas criadas pela API REST (SocialWise Flow no caminho async)
  # chegam com `content_attributes.interactive` no formato WhatsApp, que so o
  # WhatsappCloudService sabe ler. Em Instagram/Facebook o send service padrao
  # monta apenas `message: { text: ... }` e os botoes somem em silencio (HTTP 200).
  # Quando a plataforma anexa `content_attributes.meta_interactive` — o payload ja
  # convertido para BUTTON_TEMPLATE/QUICK_REPLIES — roteamos para o RichMessageService,
  # o mesmo caminho que a resposta sincrona do webhook ja usava.
  def send_meta_rich_message(message)
    rich_payload = message.content_attributes&.dig('meta_interactive')
    return false if rich_payload.blank?

    service = meta_rich_service(message, rich_payload)
    return false if service.nil?

    Rails.logger.info(
      "[SOCIALWISE-FLOW-ASYNC] Routing message #{message.id} to #{service.class} " \
      "(format: #{rich_payload['message_format']})"
    )
    service.perform
    true
  end

  def meta_rich_service(message, rich_payload)
    channel = message.conversation.inbox.channel

    return ::Instagram::RichMessageService.new(message: message, rich_payload: rich_payload) if channel.is_a?(Channel::Instagram)
    return ::Facebook::RichMessageService.new(message: message, rich_payload: rich_payload) if channel.is_a?(Channel::FacebookPage)

    nil
  end

  def send_on_facebook_page(message)
    if message.conversation.additional_attributes['type'] == 'instagram_direct_message'
      ::Instagram::Messenger::SendOnInstagramService.new(message: message).perform
    else
      ::Facebook::SendOnFacebookService.new(message: message).perform
    end
  end
end
