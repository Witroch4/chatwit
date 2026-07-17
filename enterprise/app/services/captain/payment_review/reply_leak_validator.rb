# Deterministic output guard for phase-2 replies.
#
# Financial URLs (payment links, receipts) are always rejected. CPF/CNPJ-like
# values are rejected unless the exact value appears verbatim in the operator
# configured prompt (operator-authorized content, Emenda 1 E3). The default
# prompt carries no values, so nothing is authorized implicitly.
class Captain::PaymentReview::ReplyLeakValidator
  BLOCKED_URL_PATTERN = %r{https?://\S*(?:infinitepay|checkout|recibo|receipt|comprovante|pay\.)\S*}i
  DOCUMENT_PATTERN = %r{\b\d{2}\.?\d{3}\.?\d{3}/?\d{4}-?\d{2}\b|\b\d{3}\.\d{3}\.\d{3}-\d{2}\b}

  def initialize(operator_prompt:)
    @operator_prompt = operator_prompt.to_s
  end

  def valid?(text)
    value = text.to_s
    return false if value.match?(BLOCKED_URL_PATTERN)

    value.scan(DOCUMENT_PATTERN).all? { |document| @operator_prompt.include?(document) }
  end
end
