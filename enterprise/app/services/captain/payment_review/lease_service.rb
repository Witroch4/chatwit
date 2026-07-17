# Atomic lease protocol for a durable payment-review run.
#
# acquire! is a compare-and-swap: it promotes a queued run — or a running run
# whose lease has expired — to running with a fresh execution_token. The old
# owner can never publish once its lease is gone. heartbeat! only renews while
# the caller's token still owns an unexpired lease.
class Captain::PaymentReview::LeaseService
  def initialize(run)
    @run = run
  end

  def acquire!
    token = SecureRandom.uuid
    # Atomic compare-and-swap on the durable run; update_all is intentional here.
    updated = acquirable_scope.update_all( # rubocop:disable Rails/SkipsModelValidations
      status: running_value,
      execution_token: token,
      lease_expires_at: Captain::PaymentReviewRun::LEASE_DURATION.from_now,
      heartbeat_at: Time.current,
      started_at: Arel.sql('COALESCE(started_at, now())')
    )
    return unless updated == 1

    @run.reload
    token
  end

  def heartbeat!(token)
    return false if token.blank?

    # Atomic lease renewal guarded by the owning token; update_all is intentional here.
    renewable_scope(token).update_all( # rubocop:disable Rails/SkipsModelValidations
      lease_expires_at: Captain::PaymentReviewRun::LEASE_DURATION.from_now,
      heartbeat_at: Time.current
    ) == 1
  end

  private

  def running_value
    Captain::PaymentReviewRun.statuses[:running]
  end

  def acquirable_scope
    base_scope
      .where(status: Captain::PaymentReviewRun.statuses.values_at('queued', 'running'))
      .where('lease_expires_at IS NULL OR lease_expires_at < ?', Time.current)
  end

  def renewable_scope(token)
    base_scope
      .where(status: running_value, execution_token: token)
      .where('lease_expires_at IS NULL OR lease_expires_at >= ?', Time.current)
  end

  def base_scope
    Captain::PaymentReviewRun.where(id: @run.id)
  end
end
