# Sanitized public-history projection for the phase-2 decision prompt.
#
# Projects at most the last 30 public (incoming/outgoing, non-private) messages
# up to the run watermark, replacing official financial values with semantic
# markers. Raw content_attributes, attachments and private notes never reach
# the LLM.
class Captain::PaymentReview::HistoryProjector
  LIMIT = 30
  CTA_MARKER = '[CTA de pagamento enviado]'.freeze
  PIX_MARKER = '[chave Pix oficial]'.freeze
  RECEIPT_MARKER = '[comprovante de pagamento]'.freeze

  RECEIPT_URL_PATTERN = %r{https?://\S*(?:recibo|receipt|comprovante)\S*}i
  CHECKOUT_URL_PATTERN = %r{https?://\S*(?:checkout|infinitepay|pay\.)\S*}i
  DOCUMENT_PATTERN = %r{\b\d{2}\.?\d{3}\.?\d{3}/?\d{4}-?\d{2}\b|\b\d{3}\.\d{3}\.\d{3}-\d{2}\b}

  def initialize(run)
    @run = run
  end

  def project
    scoped_messages.map do |message|
      {
        role: message.incoming? ? 'lead' : 'agent',
        content: sanitized_content(message)
      }
    end
  end

  private

  def scoped_messages
    scope = @run.conversation.messages
                .where(message_type: [:incoming, :outgoing], private: false)
    scope = scope.where(messages: { id: ..watermark_id }) if watermark_id.present?
    scope.reorder(id: :desc).limit(LIMIT).to_a.reverse
  end

  def watermark_id
    @run.decision_watermark_message_id.presence || @run.trigger_message_id
  end

  def sanitized_content(message)
    return CTA_MARKER if interactive_payment?(message)

    text = message.content.to_s
    text = text.gsub(RECEIPT_URL_PATTERN, RECEIPT_MARKER)
    text = text.gsub(CHECKOUT_URL_PATTERN, CTA_MARKER)
    text.gsub(DOCUMENT_PATTERN, PIX_MARKER)
  end

  def interactive_payment?(message)
    message.content_type == 'integrations' && message.content_attributes['interactive'].present?
  end
end
