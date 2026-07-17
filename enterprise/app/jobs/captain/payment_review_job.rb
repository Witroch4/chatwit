# Executes a durable payment-review run under an atomic lease.
#
# Task 10: acquire/renew the lease, refuse stale ownership and supersede when a
# human/external echo landed after the trigger watermark. Task 11: the decision
# branches — paid short-circuit, closed-schema decision, official envelopes and
# the atomic finalizer. Failures follow spec §16: transient reasons retry with
# backoff and never produce a public message; terminal reasons fail closed with
# a sanitized private note and the label kept.
class Captain::PaymentReviewJob < ApplicationJob
  queue_as :default

  RETRY_BACKOFF_BASE = 30.seconds

  def perform(run_id)
    run = Captain::PaymentReviewRun.find_by(id: run_id)
    return if run.nil? || terminal?(run)

    token = Captain::PaymentReview::LeaseService.new(run).acquire!
    return if token.blank?

    return supersede!(run) if superseded_by_human?(run.reload)

    execute_review(run, token)
  end

  private

  def execute_review(run, token)
    finalizer = Captain::PaymentReview::Finalizer.new(run: run, token: token)
    client = Captain::PaymentReview::PlatformClient.new(run)

    context = client.payment_context
    return finalizer.paid! if context&.paid?

    decide_and_finalize(run, finalizer, client, context)
  rescue Captain::PaymentReview::PlatformClient::Unavailable
    schedule_retry(run, finalizer, reason_code: 'platform_timeout')
  rescue Captain::PaymentReview::PlatformClient::ContextConflict
    schedule_retry(run, finalizer, reason_code: 'context_not_committed')
  rescue Captain::PaymentReview::Finalizer::EnvelopeExpiredError
    schedule_retry(run, finalizer, reason_code: 'envelope_expired')
  rescue Captain::PaymentReview::DecisionService::DecisionFailed => e
    finalizer.fail!(reason_code: 'decision_invalid', error_message: e.message)
  rescue Captain::PaymentReview::Finalizer::PresetNotAllowedError => e
    finalizer.fail!(reason_code: 'invalid_official_value', error_message: e.message)
  rescue Captain::PaymentReview::Finalizer::StaleRunError
    nil
  end

  def decide_and_finalize(run, finalizer, client, context)
    decision = Captain::PaymentReview::DecisionService.new(run: run, context: context).call

    case decision.action
    when 'no_action' then finalizer.no_action!
    when 'handoff_required' then finalizer.handoff!(decision)
    when 'reply' then finalizer.reply!(decision)
    when 'send_payment_preset' then finalizer.send_payment_preset!(decision)
    when 'send_pix_key'
      finalize_pix_key(run, finalizer, client, context, decision)
    else finalize_financial_action(run, finalizer, client, context, decision)
    end
  end

  # The operator-configured pix key (captain_inboxes.phase2_pix_key) wins; the
  # Platform envelope remains the fallback for installations without it.
  def finalize_pix_key(run, finalizer, client, context, decision)
    pix_key = run.conversation.inbox.captain_inbox&.phase2_pix_key
    return finalize_financial_action(run, finalizer, client, context, decision) if pix_key.blank?

    finalizer.send_pix_key!(decision, pix_key)
  end

  def finalize_financial_action(run, finalizer, client, context, decision)
    envelope = client.authorize(decision.action, context: context)

    case envelope.result
    when 'paid_noop' then finalizer.paid!
    when 'authorized' then finalizer.complete_with_envelope!(decision, envelope)
    when 'context_conflict', 'temporarily_unavailable'
      schedule_retry(run, finalizer, reason_code: 'platform_timeout')
    else
      finalizer.fail!(reason_code: 'invalid_official_value', error_message: envelope.result)
    end
  end

  def schedule_retry(run, finalizer, reason_code:)
    attempts = run.attempts + 1
    if attempts >= max_attempts
      finalizer.fail!(reason_code: reason_code)
      return
    end

    wait = RETRY_BACKOFF_BASE * (2**(attempts - 1))
    run.update!(attempts: attempts, next_attempt_at: wait.from_now)
    self.class.set(wait: wait).perform_later(run.id)
  end

  def max_attempts
    ENV.fetch('CAPTAIN_PAYMENT_PHASE2_MAX_ATTEMPTS', '5').to_i
  end

  def terminal?(run)
    run.completed? || run.failed? || run.superseded?
  end

  def superseded_by_human?(run)
    scope = run.conversation.messages
    scope = if run.trigger_message_id.present?
              scope.where('messages.id > ?', run.trigger_message_id)
            else
              scope.where('messages.created_at > ?', run.triggered_at)
            end
    scope.any? { |message| human_response?(message) }
  end

  # Mirrors Message#human_response? (private): a genuine agent reply or a native-app
  # external echo after the watermark supersedes the run.
  def human_response?(message)
    message.outgoing? &&
      message.content_attributes['automation_rule_id'].blank? &&
      message.additional_attributes['campaign_id'].blank? &&
      (message.sender.is_a?(User) || message.content_attributes['external_echo'].present?)
  end

  def supersede!(run)
    run.update!(status: :superseded, outcome: :superseded, reason_code: 'human_response', completed_at: Time.current)
    Captain::PaymentReview::WakeService.new(run.conversation).call
  end
end
