# frozen_string_literal: true

# Requests the official verification receipt from the Platform
# (`/payment-events/verify`, spec §12.3) for a locally persisted PaymentLink.
# Only expected authenticated metadata is sent; raw webhook identifiers stay
# quarantined and never direct the provider query.
class Integrations::Infinitepay::VerifyEventService
  class ConfigurationError < StandardError; end
  class Unavailable < StandardError; end

  VERIFY_PATH = '/api/v1/socialwise/integrations/captain/payment-events/verify'
  TIMEOUT = 10

  def initialize(payment_link:)
    @payment_link = payment_link
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
        amountCents: @payment_link.amount_cents
      }
    }
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
