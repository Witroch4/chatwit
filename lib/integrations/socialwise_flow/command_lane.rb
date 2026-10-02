# CHATWIT: faixa de comando administrativo do Socialwise (bot de acesso OmniRoute).
#
# Mensagem de texto recebida cuja primeira linha começa com um comando CONHECIDO
# (/om-windows ou /om-linux) vai direto ao Socialwise, sem ownership guard, handoff,
# debounce nem indicador de digitação, e sem alterar a conversa. Qualquer outro
# "/palavra" (ex.: /start) segue o fluxo normal: o Socialwise assume TODA mensagem
# com metadata.command_lane, então marcar "/palavra" genérico silenciaria leads.
# Espelha COMMANDS/parse_command de domains/socialwise/services/om_access/commands.py;
# comando novo lá = entrada nova em COMMANDS aqui.
# Clique de botão/lista/quick reply/postback nunca é comando, mesmo com título "/...".
# Ver chatwitdocs/socialwise-command-lane.md.
class Integrations::SocialwiseFlow::CommandLane
  COMMANDS = %w[om-windows om-linux].freeze
  COMMAND_PATTERN = %r{\A/(#{COMMANDS.join('|')})(\s|\z)}i
  FORWARD_TIMEOUT_SECONDS = 10
  INTERACTION_KEYS = %w[button_reply list_reply quick_reply_payload postback_payload].freeze

  # O regex vem antes das guardas de propósito: mensagem comum de lead sai aqui sem
  # consultar anexos.
  def self.eligible?(event_name:, message:)
    return false unless event_name == 'message.created' && message.present?
    return false unless COMMAND_PATTERN.match?(message.content.to_s.lstrip)

    plain_incoming_text?(message)
  end

  def self.plain_incoming_text?(message)
    return false if message.private? || !message.incoming?
    return false unless message.content_type.to_s == 'text' && message.attachments.none?

    message.content_attributes.to_h.with_indifferent_access.slice(*INTERACTION_KEYS).values.none?(&:present?)
  end
  private_class_method :plain_incoming_text?
end
