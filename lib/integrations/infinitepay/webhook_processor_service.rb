# frozen_string_literal: true

# Applies the local effects of an OFFICIALLY VERIFIED InfinitePay payment.
#
# Task 12b rewrite: this service no longer processes raw webhooks. It is the
# effects collaborator of Integrations::Infinitepay::ReconciliationService —
# each public method is one idempotent milestone. Verified amounts come from
# the payment_check receipt; raw payload values are display-only extras and
# never decide payment state.
class Integrations::Infinitepay::WebhookProcessorService
  SOCIALWISE_PAYMENT_ROUTE = '/api/v1/socialwise/admin/leads-chatwit/recebearquivos'

  # Flow charges (sw-*) have no local anchor: forward the raw event to the
  # Platform, which runs its own official verification (raw ingress closed on
  # the Platform side in Task 12a). No local financial effect happens here.
  def self.forward_raw_flow_event(payload)
    endpoint = ENV.fetch('SOCIALWISE_WEBHOOK_URL', nil)
    if endpoint.blank?
      Rails.logger.warn '[INFINITEPAY] SOCIALWISE_WEBHOOK_URL not configured. Skipping flow event forward'
      return
    end

    body = { event: 'payment_confirmed', data: payload.to_h.merge('event' => 'payment_confirmed') }
    HTTParty.post(
      "#{endpoint.to_s.chomp('/')}#{SOCIALWISE_PAYMENT_ROUTE}",
      headers: forward_headers,
      body: body.to_json,
      timeout: 15
    )
  end

  def self.forward_headers
    secret = ENV.fetch('CHATWIT_WEBHOOK_SECRET', nil)
    base = { 'Content-Type' => 'application/json' }
    secret.present? ? base.merge('x-webhook-secret' => secret, 'X-Chatwit-Secret' => secret) : base
  end

  def initialize(payment_link:, receipt:, raw_payload: {})
    @payment_link = payment_link
    @receipt = receipt.to_h
    @raw_payload = raw_payload.to_h
  end

  def apply_payment_link!
    return if @payment_link.paid?

    @payment_link.mark_as_paid!(
      'invoice_slug' => @raw_payload['invoice_slug'],
      'transaction_nsu' => @raw_payload['transaction_nsu'],
      'capture_method' => @raw_payload['capture_method'],
      'paid_amount' => verified_paid_amount_cents,
      'receipt_url' => @raw_payload['receipt_url'],
      'verified_source' => @receipt['source'],
      'raw' => @raw_payload
    )
  end

  def send_confirmation_message!
    return if confirmation_message_sent?

    conversation = @payment_link.conversation
    conversation.messages.create!(
      account: @payment_link.account,
      inbox_id: conversation.inbox_id,
      message_type: :outgoing,
      content: notification_payload[:content],
      additional_attributes: {
        payment_link_id: @payment_link.id,
        infinitepay_event: 'payment_confirmed'
      }
    )
  end

  def send_payment_push!
    Integrations::Infinitepay::PushNotificationService.new(
      payment_link: @payment_link,
      notification_payload: notification_payload.slice(:title, :body, :tag, :url)
    ).perform
  end

  def forward_to_socialwise!
    endpoint = ENV.fetch('SOCIALWISE_WEBHOOK_URL', nil)
    if endpoint.blank?
      Rails.logger.warn "[INFINITEPAY] SOCIALWISE_WEBHOOK_URL not configured. Skipping forward order_nsu=#{@payment_link.order_nsu}"
      return
    end

    body = { event: 'payment_confirmed', data: event_payload.merge(event: 'payment_confirmed') }
    response = HTTParty.post(
      "#{endpoint.to_s.chomp('/')}#{SOCIALWISE_PAYMENT_ROUTE}",
      headers: self.class.forward_headers,
      body: body.to_json,
      timeout: 15
    )
    raise "SocialWise forward failed with #{response.code}" unless response.success?

    response
  end

  def forward_to_jusmonitoria!
    Integrations::Jusmonitoria::WebhookForwarderService.forward_event(
      event_type: 'payment.confirmed',
      payload: event_payload,
      account: @payment_link.account,
      path: Integrations::Jusmonitoria::WebhookForwarderService::PAYMENT_PATH
    )
  end

  private

  def verified_paid_amount_cents
    @receipt['paidAmountCents'] || @receipt['providerAmountCents'] || @payment_link.amount_cents
  end

  def event_payload
    conversation = @payment_link.conversation
    {
      payment_link_id: @payment_link.id,
      order_nsu: @payment_link.order_nsu,
      amount_cents: @payment_link.amount_cents,
      paid_amount_cents: verified_paid_amount_cents,
      capture_method: @payment_link.capture_method,
      receipt_url: @payment_link.receipt_url,
      conversation_id: @payment_link.conversation_id,
      verified_source: @receipt['source'],
      contact: contact_payload(conversation.contact),
      conversation: conversation_payload(conversation),
      inbox: inbox_payload(conversation.inbox)
    }
  end

  def contact_payload(contact)
    contact.blank? ? { id: nil, name: nil, phone_number: nil } : contact.webhook_data
  end

  def conversation_payload(conversation)
    return {} if conversation.blank?

    conversation.webhook_data.merge(
      labels: conversation.cached_label_list_array,
      contact: conversation.contact&.webhook_data,
      inbox: inbox_payload(conversation.inbox)
    )
  end

  def inbox_payload(inbox)
    inbox.blank? ? {} : { id: inbox.id, name: inbox.name, channel_type: inbox.channel_type }
  end

  def notification_payload = @notification_payload ||= build_notification_payload

  def build_notification_payload
    conversation = @payment_link.conversation
    contact_name = conversation.contact&.name || 'Cliente'
    amount_formatted = format_brl(verified_paid_amount_cents / 100.0)
    transaction_code = @raw_payload['transaction_nsu'].presence || @payment_link.transaction_nsu.presence || @payment_link.order_nsu
    receipt_url = @raw_payload['receipt_url'].presence || @payment_link.receipt_url

    {
      title: 'Pagamento Confirmado!',
      body: "Olá, #{contact_name}! Pagamento de #{amount_formatted} recebido com sucesso.",
      content: confirmation_content(contact_name, amount_formatted, transaction_code, receipt_url),
      tag: "infinitepay_payment_confirmed_#{@payment_link.id}",
      url: conversation_url(conversation)
    }
  end

  def confirmation_content(contact_name, amount_formatted, transaction_code, receipt_url)
    <<~MSG.strip
      ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
      ┃ 🎉 **PAGAMENTO CONFIRMADO!**   ┃
      ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

      Olá, **#{contact_name}**! 👋
       Seu pagamento foi recebido com sucesso. ✅

      \\> 📄 **Detalhes da transação**
      \\> • **Descrição:** #{@payment_link.description}
      \\> • **Valor:** #{amount_formatted} 💰
      \\> • **Pagamento:** #{capture_detail}
      \\> • **Código:** #{transaction_code}

      🧾 **Comprovante**
      #{receipt_url}

       🙏 Obrigado pela confiança!
       Qualquer dúvida, estamos à disposição.

      ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
    MSG
  end

  def capture_detail
    installments = @raw_payload['installments'].to_i
    if @raw_payload['capture_method'] == 'pix'
      'PIX 🏦'
    elsif installments > 1
      "Cartão #{installments}x 💳"
    else
      'Cartão de Crédito 💳'
    end
  end

  def format_brl(value)
    formatted = format('%.2f', value)
    integer_part, decimal_part = formatted.split('.')
    integer_with_dots = integer_part.reverse.gsub(/(\d{3})(?=\d)/, '\\1.').reverse
    "R$ #{integer_with_dots},#{decimal_part}"
  end

  def conversation_url(conversation)
    base_url = ENV.fetch('FRONTEND_URL', 'https://chatwit.witdev.com.br').chomp('/')
    "#{base_url}/app/accounts/#{conversation.account_id}/conversations/#{conversation.display_id}"
  end

  def confirmation_message_sent?
    @payment_link.conversation.messages.outgoing.exists?(
      ["additional_attributes ->> 'payment_link_id' = ? AND additional_attributes ->> 'infinitepay_event' = ?",
       @payment_link.id.to_s, 'payment_confirmed']
    )
  end
end
