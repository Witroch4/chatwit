# CHATWIT: faixa de comando administrativo do Socialwise.
#
# Mensagem de texto recebida que começa com "/palavra" vai direto ao Socialwise,
# sem ownership guard, handoff, debounce nem indicador de digitação, e sem
# alterar a conversa. Quem decide se é comando válido — e quem pode usá-lo — é o
# Socialwise (FastAPI). O padrão é o MESMO de
# domains/socialwise/services/om_access/commands.py (COMMAND_RE).
# Clique de botão/lista/quick reply/postback nunca é comando, mesmo com título "/...".
# Ver chatwitdocs/socialwise-command-lane.md.
class Integrations::SocialwiseFlow::CommandLane
  COMMAND_PATTERN = %r{\A/[a-z][a-z0-9-]*(\s|\z)}i
  INTERACTION_KEYS = %w[button_reply list_reply quick_reply_payload postback_payload].freeze

  def self.eligible?(event_name:, message:)
    return false unless event_name == 'message.created' && plain_incoming_text?(message)

    COMMAND_PATTERN.match?(message.content.to_s.lstrip)
  end

  def self.plain_incoming_text?(message)
    return false if message.blank? || message.private? || !message.incoming?
    return false unless message.content_type.to_s == 'text' && message.attachments.none?

    message.content_attributes.to_h.with_indifferent_access.slice(*INTERACTION_KEYS).values.none?(&:present?)
  end
  private_class_method :plain_incoming_text?
end
