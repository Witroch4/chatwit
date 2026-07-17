# frozen_string_literal: true

# lib/integrations/jusmonitoria/webhook_forwarder_service.rb
# Fire-and-forget HTTP forwarder to JusMonitorIA (platform-api).
# Prefers the internal docker network (http://platform-api:8000); override with
# JUSMONITORIA_WEBHOOK_URL. Auth: HMAC-SHA256 signature in X-Chatwit-Signature.
#
# Two platform routes live on the same platform-api service:
#   DEFAULT_PATH (message.*/tag.*/contact.*/conversation.resolved) → chatwit_webhook
#   PAYMENT_PATH (payment.confirmed) → chatwit_unified_webhook (process_payment_confirmed)
# Payment MUST target PAYMENT_PATH — chatwit_webhook does not handle payments.

class Integrations::Jusmonitoria::WebhookForwarderService
  TIMEOUT = 15
  DEFAULT_PATH = '/webhooks/chatwit'
  PAYMENT_PATH = '/api/v1/jusmonitoria/integrations/chatwit'

  class << self
    def forward_event(event_type:, payload:, account: nil, path: DEFAULT_PATH)
      endpoint = jusmonitoria_endpoint
      return if endpoint.blank?

      json_body = build_request_body(event_type, payload, account).to_json
      Rails.logger.info "[JUSMONITORIA-FORWARD] Sending #{event_type} to #{endpoint}#{path}"
      post_event(endpoint, path, json_body)
    rescue StandardError => e
      Rails.logger.error "[JUSMONITORIA-FORWARD] Failed to forward #{event_type}: #{e.class}: #{e.message}"
      nil
    end

    private

    def jusmonitoria_endpoint
      ENV.fetch('JUSMONITORIA_WEBHOOK_URL', 'http://platform-api:8000')
    end

    def build_request_body(event_type, payload, account)
      {
        event_type: event_type,
        data: payload,
        metadata: build_metadata(account)
      }
    end

    def post_event(endpoint, path, json_body)
      response = HTTParty.post(
        "#{endpoint.to_s.chomp('/')}#{path}",
        headers: request_headers(json_body),
        body: json_body,
        timeout: TIMEOUT
      )
      Rails.logger.info "[JUSMONITORIA-FORWARD] Response: #{response.code}"
      response
    end

    def request_headers(body)
      headers = { 'Content-Type' => 'application/json' }
      secret = ENV.fetch('CHATWIT_WEBHOOK_SECRET', nil)
      if secret.present?
        headers['x-webhook-secret'] = secret
        signature = OpenSSL::HMAC.hexdigest('SHA256', secret, body)
        headers['X-Chatwit-Signature'] = signature
      end
      headers
    end

    def build_metadata(account)
      {
        account_id: account&.id,
        account_name: account&.name,
        chatwit_base_url: ENV.fetch('FRONTEND_URL', 'https://chatwit.witdev.com.br'),
        chatwit_agent_bot_token: Chatwit::PlatformBot.token,
        timestamp: Time.current.iso8601
      }
    end
  end
end
