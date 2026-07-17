# Closed decision schema for the phase-2 review. The LLM output is parsed and
# validated against exactly one action; anything outside the contract fails
# closed at the caller.
module Captain::PaymentReview::DecisionSchema
  ACTIONS = %w[no_action reply send_cta send_pix_key send_status send_payment_preset handoff_required].freeze
  FINANCIAL_ACTIONS = %w[send_cta send_pix_key send_status].freeze

  class InvalidDecisionError < StandardError; end

  Decision = Struct.new(:action, :response, :reason_code, :preset_id, keyword_init: true) do
    def no_action?
      action == 'no_action'
    end

    def reply?
      action == 'reply'
    end

    def handoff_required?
      action == 'handoff_required'
    end

    def payment_preset?
      action == 'send_payment_preset'
    end

    def financial_action?
      FINANCIAL_ACTIONS.include?(action)
    end
  end

  def self.parse(raw)
    data = raw.is_a?(Hash) ? raw : JSON.parse(raw.to_s)
    raise InvalidDecisionError, 'decision must be a JSON object' unless data.is_a?(Hash)

    decision = Decision.new(
      action: data['action'].to_s,
      response: data['response'].presence,
      reason_code: data['reason_code'].to_s,
      preset_id: data['preset_id']
    )
    validate!(decision)
    decision
  rescue JSON::ParserError
    raise InvalidDecisionError, 'decision is not valid JSON'
  end

  def self.validate!(decision)
    raise InvalidDecisionError, "unknown action #{decision.action.inspect}" unless ACTIONS.include?(decision.action)
    raise InvalidDecisionError, 'reason_code is required' if decision.reason_code.blank?
    raise InvalidDecisionError, 'reply requires a non-empty response' if decision.reply? && decision.response.blank?
    raise InvalidDecisionError, 'only reply may carry a response' if !decision.reply? && decision.response.present?

    validate_preset_id!(decision)
  end

  def self.validate_preset_id!(decision)
    if decision.payment_preset?
      raise InvalidDecisionError, 'send_payment_preset requires an integer preset_id' unless decision.preset_id.is_a?(Integer)
    elsif decision.preset_id.present?
      raise InvalidDecisionError, 'only send_payment_preset may carry preset_id'
    end
  end
end
