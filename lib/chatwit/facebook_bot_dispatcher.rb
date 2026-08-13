# Rack wrapper na frente do `Facebook::Messenger::Server` montado em /bot.
#
# POR QUE EXISTE
# --------------
# A Meta permite UMA URL de callback por objeto. O objeto `page` deste app ja
# aponta para /bot e serve o Messenger (campos messages, message_echoes,
# message_reads, messaging_postbacks). Assinar `feed` no mesmo objeto — que e
# como chega comentario em post e em ANUNCIO da Pagina — faz esses eventos
# caírem no mesmo /bot.
#
# A gem so entende entries com `messaging`; evento de `feed` vem em `changes[]`
# e ela ignora (ou estoura). Este dispatcher separa os dois:
#
#   POST /bot com entry[].changes[field=feed]  -> valida HMAC e repassa ao
#                                                 Socialwise (dono da moderacao)
#   qualquer outra coisa (incl. GET handshake) -> gem do Messenger, intocada
#
# Trocar a URL do objeto `page` para uma rota dedicada NAO era opcao: derrubaria
# o Messenger em producao.
class Chatwit::FacebookBotDispatcher
  SIGNATURE_HEADER = 'HTTP_X_HUB_SIGNATURE_256'.freeze
  SIGNATURE_PREFIX = 'sha256='.freeze

  def initialize(messenger_app)
    @messenger_app = messenger_app
  end

  def call(env)
    return @messenger_app.call(env) unless env['REQUEST_METHOD'] == 'POST'

    raw_body = read_body(env)
    payload = parse_json(raw_body)
    return @messenger_app.call(env) unless feed_event?(payload)

    handle_feed(raw_body, env[SIGNATURE_HEADER])
  end

  private

  # A gem le `rack.input` depois de nos; rebobinar e obrigatorio, senao o
  # Messenger recebe corpo vazio.
  def read_body(env)
    input = env['rack.input']
    return '' if input.nil?

    body = input.read
    input.rewind
    body
  end

  def parse_json(raw_body)
    JSON.parse(raw_body)
  rescue JSON::ParserError, TypeError
    nil
  end

  def feed_event?(payload)
    return false unless payload.is_a?(Hash) && payload['object'] == 'page'

    Array(payload['entry']).any? do |entry|
      next false unless entry.is_a?(Hash)

      Array(entry['changes']).any? { |change| change.is_a?(Hash) && change['field'] == 'feed' }
    end
  end

  def handle_feed(raw_body, signature)
    unless valid_signature?(raw_body, signature)
      Rails.logger.warn('[FB-FEED] assinatura invalida — evento descartado')
      return [401, { 'Content-Type' => 'application/json' }, [{ error: 'invalid_signature' }.to_json]]
    end

    ::Webhooks::FacebookFeedSocialwiseForwarderJob.perform_later(
      raw_body: raw_body,
      signature: signature.to_s
    )
    [200, { 'Content-Type' => 'application/json' }, [{ ok: true }.to_json]]
  end

  def valid_signature?(raw_body, signature)
    secret = GlobalConfigService.load('FB_APP_SECRET', nil)
    return false if secret.blank?
    return false unless signature.to_s.start_with?(SIGNATURE_PREFIX)

    expected = "#{SIGNATURE_PREFIX}#{OpenSSL::HMAC.hexdigest('SHA256', secret, raw_body)}"
    ActiveSupport::SecurityUtils.secure_compare(expected, signature.to_s)
  end
end
