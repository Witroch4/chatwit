# Fire-and-forget fan-out: repassa o payload cru do webhook `feed` da Pagina
# (corpo + x-hub-signature-256 byte-a-byte) para o receptor do Socialwise, que
# revalida o HMAC com FB_APP_SECRET como se a request tivesse vindo da Meta.
# Mesmo contrato do InstagramSocialwiseForwarderJob — o App e o secret sao os
# mesmos nos dois lados.

require 'httparty'

class Webhooks::FacebookFeedSocialwiseForwarderJob < ApplicationJob
  queue_as :low

  retry_on(
    Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH,
    Net::OpenTimeout, Net::ReadTimeout, HTTParty::Error,
    wait: :exponentially_longer, attempts: 5
  )

  USER_AGENT = 'Chatwit-FB-Feed-Forwarder/1.0'.freeze
  OPEN_TIMEOUT_S = 3
  READ_TIMEOUT_S = 8

  def perform(raw_body:, signature:)
    target = ENV.fetch('SOCIALWISE_FACEBOOK_WEBHOOK_URL', '').to_s
    if target.empty?
      Rails.logger.info('[FB-FEED-FORWARD] skipped — SOCIALWISE_FACEBOOK_WEBHOOK_URL not set')
      return
    end

    handle_response(post_payload(target, raw_body, signature))
  end

  private

  def post_payload(target, raw_body, signature)
    HTTParty.post(
      target,
      body: raw_body.to_s,
      headers: {
        'Content-Type' => 'application/json',
        'X-Hub-Signature-256' => signature.to_s,
        'User-Agent' => USER_AGENT
      },
      open_timeout: OPEN_TIMEOUT_S,
      timeout: READ_TIMEOUT_S
    )
  end

  def handle_response(response)
    return Rails.logger.info("[FB-FEED-FORWARD] ok status=#{response.code}") if response.success?

    # 401/403 = divergencia de segredo entre o app Meta e o Socialwise. Retry
    # nao conserta env divergente — loga alto e para para nao entupir a fila.
    return log_signature_mismatch(response) if [401, 403].include?(response.code.to_i)

    Rails.logger.error(
      "[FB-FEED-FORWARD] non-2xx status=#{response.code} body=#{response.body.to_s[0, 500]}"
    )
    raise "Socialwise facebook forwarder non-2xx: #{response.code}"
  end

  def log_signature_mismatch(response)
    Rails.logger.error(
      '[FB-FEED-FORWARD] signature mismatch — verifique paridade de FB_APP_SECRET ' \
      "entre o app Meta e SOCIALWISE_FACEBOOK_APP_SECRET no platform-api. body=#{response.body.to_s[0, 200]}"
    )
  end
end
