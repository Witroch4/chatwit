class Captain::PaymentReview::FeatureGate
  ENABLED_ENV = 'CAPTAIN_PAYMENT_PHASE2_ENABLED'.freeze
  INBOX_ALLOWLIST_ENV = 'CAPTAIN_PAYMENT_PHASE2_INBOX_IDS'.freeze
  ACCOUNT_ATTRIBUTE = 'captain_payment_phase2'.freeze

  def initialize(conversation)
    @conversation = conversation
  end

  def eligible?
    reason == :eligible
  end

  def reason
    @reason ||= begin
      failed_check = eligibility_checks.find { |allowed, _reason| !allowed }
      failed_check&.last || :eligible
    end
  end

  private

  attr_reader :conversation

  delegate :inbox, to: :conversation

  def enabled?
    env_enabled? || account_feature_enabled?
  end

  def env_enabled?
    ActiveModel::Type::Boolean.new.cast(ENV.fetch(ENABLED_ENV, false))
  end

  # Fail-closed booleano estrito: só o boolean JSON `true` liga a feature.
  # Ausência ou lixo (string, número) no jsonb ⇒ desabilitado.
  def account_feature_enabled?
    conversation.account.internal_attributes[ACCOUNT_ATTRIBUTE] == true
  end

  def allowlisted_inbox?
    # Ativação por conta sem allowlist ENV ⇒ granularidade fica por CaptainInbox#phase2_only.
    return true if account_feature_enabled? && allowlisted_inbox_ids.empty?

    allowlisted_inbox_ids.include?(inbox.id)
  end

  def allowlisted_inbox_ids
    ENV.fetch(INBOX_ALLOWLIST_ENV, '').split(',').filter_map do |value|
      Integer(value.strip, exception: false)
    end
  end

  def assistant
    inbox.captain_assistant
  end

  def eligibility_checks
    [
      [enabled?, :kill_switch_disabled],
      [allowlisted_inbox?, :inbox_not_allowlisted],
      [inbox.captain_inbox&.phase2_only?, :phase2_mode_disabled],
      [assistant.present?, :assistant_missing],
      [assistant&.account_id == conversation.account_id, :assistant_tenant_mismatch],
      [inbox.captain_payment_review_available?, :quota_exhausted]
    ]
  end
end
