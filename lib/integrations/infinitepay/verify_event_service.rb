# frozen_string_literal: true

# Requests the official verification receipt from the Platform
# (`/payment-events/verify`, spec §12.3) for a locally persisted PaymentLink.
#
# The quarantined webhook identifiers (transaction_nsu/invoice_slug) are sent
# ONLY as query pointers: InfinitePay's payment_check needs them to locate a
# card transaction, but the payment decision remains the provider's verified
# answer (success+paid+exact base amount). A forged pointer simply fails the
# check — it can never mark anything paid by itself.
class Integrations::Infinitepay::VerifyEventService
  class ConfigurationError < StandardError; end
  class Unavailable < StandardError; end

  VERIFY_PATH = '/api/v1/socialwise/integrations/captain/payment-events/verify'
  TIMEOUT = 10

  def initialize(payment_link:, raw_payload: {})
    @payment_link = payment_link
    @raw_payload = raw_payload.to_h
  end

  def receipt
    response = HTTParty.post(
      "#{base_url}#{VERIFY_PATH}",
      headers: headers,
      body: body.to_json,
      timeout: TIMEOUT
    )
    raise Unavailable, "platform responded #{response.code}" unless response.code == 200

    parsed = response.parsed_response
    parsed = JSON.parse(parsed) if parsed.is_a?(String)
    parsed.to_h.fetch('receipt', {})
  rescue Timeout::Error, Errno::ECONNREFUSED, SocketError, HTTParty::Error => e
    raise Unavailable, e.class.name
  end

  private

  def body
    {
      expectedLink: {
        handle: official_handle,
        orderNsu: @payment_link.order_nsu,
        amountCents: @payment_link.amount_cents,
        transactionNsu: query_pointer('transaction_nsu'),
        invoiceSlug: query_pointer('invoice_slug')
      }.compact
    }
  end

  def query_pointer(key)
    @raw_payload[key].to_s.strip.presence
  end

  def official_handle
    handle = @payment_link.account.custom_attributes&.dig('infinitepay_handle').to_s
    raise ConfigurationError, 'InfinitePay handle not configured for this account' if handle.blank?

    handle
  end

  def headers
    secret = ENV.fetch('CHATWIT_WEBHOOK_SECRET', '').strip
    raise ConfigurationError, 'CHATWIT_WEBHOOK_SECRET is required' if secret.blank?

    conversation = @payment_link.conversation
    {
      'Content-Type' => 'application/json',
      'X-Chatwit-Secret' => secret,
      'X-Chatwoot-Account-Id' => @payment_link.account_id.to_s,
      'X-Chatwoot-Conversation-Id' => conversation.id.to_s,
      'X-Chatwoot-Conversation-Display-Id' => conversation.display_id.to_s
    }
  end

  def base_url
    ENV.fetch('CAPTAIN_PAYMENT_PLATFORM_URL', 'http://platform-api:8000').chomp('/')
  end
end
