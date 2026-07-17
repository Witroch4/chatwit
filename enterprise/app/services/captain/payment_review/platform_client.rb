# Signed HTTP client for the Platform captain payment APIs (spec §12).
#
# All requests carry the shared secret plus the tenant headers; responses are
# parsed into small typed structs. Network/5xx problems surface as the
# retryable Unavailable error and never produce a public message.
class Captain::PaymentReview::PlatformClient
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class Unavailable < Error; end
  class ContextConflict < Error; end

  PREFIX = '/api/v1/socialwise/integrations/captain'.freeze
  ACTION_PATHS = { 'send_cta' => 'cta', 'send_pix_key' => 'pix-key', 'send_status' => 'status' }.freeze
  TIMEOUT = 10
  NETWORK_ERRORS = [
    Net::OpenTimeout, Net::ReadTimeout, Timeout::Error, Errno::ECONNREFUSED,
    Errno::ECONNRESET, SocketError, OpenSSL::SSL::SSLError, HTTParty::Error
  ].freeze

  PaymentContext = Struct.new(
    :payment_context_id, :version, :status, :order_nsu, :amount_cents,
    :can_send_cta, :has_official_pix_key, :can_send_status, :reason_code,
    keyword_init: true
  ) do
    def paid?
      status == 'paid'
    end

    def pending?
      status == 'pending'
    end
  end

  ActionEnvelope = Struct.new(:result, :action, :message, :issued_at, :expires_at, keyword_init: true) do
    def authorized?
      result == 'authorized'
    end

    def paid_noop?
      result == 'paid_noop'
    end

    def expired?
      expires_at.blank? || expires_at.past?
    end
  end

  def initialize(run)
    @run = run
  end

  def payment_context
    response = request(:get, '/payment-context', query: context_query)
    case response.code
    when 200 then build_context(response.parsed_response)
    when 404 then nil
    when 409 then raise ContextConflict, 'payment context conflict'
    else raise Unavailable, "platform responded #{response.code}"
    end
  end

  def authorize(action, context: nil)
    path = ACTION_PATHS.fetch(action)
    body = {
      paymentContextId: context&.payment_context_id || @run.payment_context_id,
      version: context&.version || @run.payment_context_version,
      captainRunId: @run.id
    }
    response = request(:post, "/payment-actions/#{path}", body: body)
    raise Unavailable, "platform responded #{response.code}" unless response.code == 200

    build_envelope(response.parsed_response)
  end

  private

  def context_query
    {
      triggered_at: @run.triggered_at.utc.iso8601,
      payment_context_id: @run.payment_context_id.presence,
      payment_context_version: @run.payment_context_version.presence
    }.compact
  end

  def request(verb, path, query: nil, body: nil)
    options = { headers: headers, timeout: TIMEOUT }
    options[:query] = query if query
    options[:body] = body.to_json if body
    HTTParty.public_send(verb, "#{base_url}#{PREFIX}#{path}", options)
  rescue *NETWORK_ERRORS => e
    raise Unavailable, e.class.name
  end

  def headers
    {
      'Content-Type' => 'application/json',
      'X-Chatwit-Secret' => secret,
      'X-Chatwoot-Account-Id' => @run.account_id.to_s,
      'X-Chatwoot-Conversation-Id' => @run.conversation_id.to_s,
      'X-Chatwoot-Conversation-Display-Id' => @run.conversation.display_id.to_s
    }
  end

  def secret
    value = ENV.fetch('CHATWIT_WEBHOOK_SECRET', '').strip
    raise ConfigurationError, 'CHATWIT_WEBHOOK_SECRET is required' if value.blank?

    value
  end

  def base_url
    ENV.fetch('CAPTAIN_PAYMENT_PLATFORM_URL', 'http://platform-api:8000').chomp('/')
  end

  def parse_payload(payload)
    return JSON.parse(payload) if payload.is_a?(String)

    payload.to_h
  rescue JSON::ParserError
    {}
  end

  def build_context(payload)
    data = parse_payload(payload)
    PaymentContext.new(
      payment_context_id: data['paymentContextId'],
      version: data['version'],
      status: data['status'],
      order_nsu: data['orderNsu'],
      amount_cents: data['amountCents'],
      can_send_cta: data['canSendCta'] == true,
      has_official_pix_key: data['hasOfficialPixKey'] == true,
      can_send_status: data['canSendStatus'] == true,
      reason_code: data['reasonCode']
    )
  end

  def build_envelope(payload)
    data = parse_payload(payload)
    ActionEnvelope.new(
      result: data['result'],
      action: data['action'],
      message: data['message'],
      issued_at: parse_time(data['issuedAt']),
      expires_at: parse_time(data['expiresAt'])
    )
  end

  def parse_time(value)
    return if value.blank?

    Time.zone.parse(value.to_s)
  end
end
