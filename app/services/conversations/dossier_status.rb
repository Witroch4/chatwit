# Chatwit: shared status store for dossier exports (see chatwitdocs/baixar-dossie.md)
class Conversations::DossierStatus
  EXPIRY = 12.hours

  class << self
    def write(account_id, conversation_display_id, dossier_id, payload)
      Redis::Alfred.setex(key(account_id, conversation_display_id, dossier_id), payload.to_json, EXPIRY)
    end

    def read(account_id, conversation_display_id, dossier_id)
      raw = Redis::Alfred.get(key(account_id, conversation_display_id, dossier_id))
      return if raw.blank?

      JSON.parse(raw)
    rescue JSON::ParserError
      nil
    end

    private

    def key(account_id, conversation_display_id, dossier_id)
      format('CHATWIT::DOSSIER::%<account>s::%<conversation>s::%<dossier>s',
             account: account_id, conversation: conversation_display_id, dossier: dossier_id)
    end
  end
end
