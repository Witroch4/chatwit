# frozen_string_literal: true

# Push PWA for flow charges (sw-*). The Platform verifies the payment with the
# provider and answers the forward with the conversation; Chatwit only owns the
# agents' browser subscriptions. One push per order, whatever the re-forwards
# (Chatwit retries, InfinitePay re-deliveries, the Platform "skipped" answer).
class Integrations::Infinitepay::FlowPaymentPushService
  DEDUP_TTL = 7.days.to_i

  pattr_initialize [:order_nsu!, :answer!]

  def perform
    return unless ActiveModel::Type::Boolean.new.cast(answer['verified'])

    conversation = Conversation.find_by(id: answer['conversationId'])
    return if conversation.nil?
    return unless first_push?

    Integrations::Infinitepay::PushNotificationService.new(
      account: conversation.account,
      notification_payload: notification_payload(conversation),
      log_reference: "order_nsu=#{order_nsu}"
    ).perform
  end

  private

  def first_push?
    Redis::Alfred.set("infinitepay:flow_payment_push:#{order_nsu}", 1, nx: true, ex: DEDUP_TTL)
  end

  def notification_payload(conversation)
    contact_name = conversation.contact&.name.presence || 'Cliente'
    {
      title: 'Pagamento Confirmado!',
      body: "Olá, #{contact_name}! Pagamento#{amount_label} recebido com sucesso.",
      tag: "infinitepay_payment_confirmed_#{order_nsu}",
      url: conversation_url(conversation)
    }
  end

  def amount_label
    cents = answer['paidAmountCents'].to_i
    return '' unless cents.positive?

    " de #{ActiveSupport::NumberHelper.number_to_currency(cents / 100.0, unit: 'R$ ', separator: ',', delimiter: '.')}"
  end

  def conversation_url(conversation)
    base_url = ENV.fetch('FRONTEND_URL', 'https://chatwit.witdev.com.br').chomp('/')
    "#{base_url}/app/accounts/#{conversation.account_id}/conversations/#{conversation.display_id}"
  end
end
