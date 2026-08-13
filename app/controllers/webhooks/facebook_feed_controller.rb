# Recebe o webhook do objeto `page` / campo `feed` da Meta.
#
# Por que uma rota propria e nao o `/bot`: aquele mount e o
# `Facebook::Messenger::Server`, que so parseia entries de `messaging`. Evento
# de `feed` chega em `changes[]` e a gem descarta — alem de nao ter para onde
# rotear moderacao. Aqui o Chatwit segue como carteiro: valida a Meta e
# repassa o corpo cru para o Socialwise, que detem toda a inteligencia.
#
# A Meta documenta para o campo `feed`: "Webhooks are not sent for Ad Posts,
# but are sent for Comments on Ad Posts" — e por isso que comentario de
# propaganda (inclusive dark post) chega por aqui.
class Webhooks::FacebookFeedController < ActionController::API
  include MetaTokenVerifyConcern

  before_action :verify_meta_signature!, only: :events

  def events
    if params['object'] != 'page'
      Rails.logger.warn("Message is not received from the page webhook event: #{params['object']}")
      return head :unprocessable_entity
    end

    Rails.logger.info('Facebook feed webhook received events')

    # Fan-out para o Socialwise (dono da moderacao de comentarios). Corpo +
    # x-hub-signature-256 seguem byte-a-byte para o receptor revalidar o HMAC
    # como se a Meta tivesse chamado direto.
    ::Webhooks::FacebookFeedSocialwiseForwarderJob.perform_later(
      raw_body: request.raw_post,
      signature: request.headers['x-hub-signature-256']
    )

    render json: :ok
  end

  private

  def valid_token?(token)
    # FB_FEED_VERIFY_TOKEN permite girar o token do `feed` sem derrubar o
    # Messenger, que usa FB_VERIFY_TOKEN no mount /bot. Os dois sao aceitos
    # para nao exigir configuracao nova em instalacao existente.
    expected = [
      GlobalConfigService.load('FB_FEED_VERIFY_TOKEN', ''),
      GlobalConfigService.load('FB_VERIFY_TOKEN', '')
    ].compact_blank

    expected.any? { |candidate| ActiveSupport::SecurityUtils.secure_compare(candidate.to_s, token.to_s) }
  end

  def meta_app_secrets
    # Webhook de Pagina e assinado com o app secret do app Meta (nao com o do
    # app do Instagram).
    [GlobalConfigService.load('FB_APP_SECRET', nil)]
  end
end
