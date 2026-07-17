# Job to process debounced messages for SocialWise Flow integration
# This job implements a "reset timer" debounce with max timeout using inline sleep:
# - Job executes immediately and sleeps for the debounce period
# - Each new message resets the silence timer (tracked in Redis)
# - Job wakes up, checks if silence achieved, sleeps again if not
# - Processing happens after X ms of silence OR after max timeout (whichever comes first)
#
# This approach avoids Sidekiq's scheduled job polling delay (~5s) for precise timing.
class SocialwiseDebounceJob < ApplicationJob
  COMPARE_DELETE_SCRIPT = <<~LUA.freeze
    if redis.call('get', KEYS[1]) == ARGV[1] then
      return redis.call('del', KEYS[1])
    end
    return 0
  LUA

  CLAIM_SCRIPT = <<~LUA.freeze
    local expected_epoch = tonumber(ARGV[1])
    local cutoff = tonumber(ARGV[2])
    local expiry = tonumber(ARGV[3])
    local buffered = redis.call('lrange', KEYS[1], 0, -1)
    local claimed = {}
    local retained = {}
    local retained_first = nil
    local retained_last = nil

    for _, raw in ipairs(buffered) do
      local decoded, item = pcall(cjson.decode, raw)
      if decoded and type(item) == 'table' then
        local item_epoch = tonumber(item['ownership_epoch'])
        local timestamp = tonumber(item['timestamp'])
        local valid_epoch = item_epoch and item_epoch >= 0 and item_epoch == math.floor(item_epoch)

        if valid_epoch and timestamp then
          if item_epoch == expected_epoch and timestamp <= cutoff then
            table.insert(claimed, raw)
          elseif item_epoch > expected_epoch or (item_epoch == expected_epoch and timestamp > cutoff) then
            table.insert(retained, raw)
            retained_first = retained_first and math.min(retained_first, timestamp) or timestamp
            retained_last = retained_last and math.max(retained_last, timestamp) or timestamp
          end
        end
      end
    end

    redis.call('del', KEYS[1], KEYS[2], KEYS[3])
    if #retained > 0 then
      for _, raw in ipairs(retained) do
        redis.call('rpush', KEYS[1], raw)
      end
      redis.call('set', KEYS[2], tostring(retained_first))
      redis.call('set', KEYS[3], tostring(retained_last))
      redis.call('expire', KEYS[1], expiry)
      redis.call('expire', KEYS[2], expiry)
      redis.call('expire', KEYS[3], expiry)
    end

    return claimed
  LUA

  queue_as :critical

  def perform(conversation_id, hook_id, event_name, debounce_ms = 5000, max_timeout_ms = 30_000, ownership_epoch = nil)
    Rails.logger.info "[SOCIALWISE-DEBOUNCE] Job started for conversation #{conversation_id}"
    return unless valid_ownership_epoch?(ownership_epoch)

    conversation = Conversation.find_by(id: conversation_id)
    hook = Integrations::Hook.find_by(id: hook_id)

    unless conversation && hook
      Rails.logger.warn "[SOCIALWISE-DEBOUNCE] Conversation or hook not found: conversation=#{conversation_id}, hook=#{hook_id}"
      return
    end

    ownership_guard = Integrations::SocialwiseFlow::OwnershipGuard.new(conversation)
    return unless ownership_guard.can_publish?(epoch: ownership_epoch)

    active_key = format(Redis::Alfred::SOCIALWISE_DEBOUNCE_ACTIVE, conversation_id: conversation_id)
    active_token = acquire_active(active_key, (max_timeout_ms / 1000.0).ceil + 30)
    return unless active_token

    begin
      return unless ownership_guard.can_publish?(epoch: ownership_epoch)

      debounce_seconds = debounce_ms / 1000.0
      max_timeout_seconds = max_timeout_ms / 1000.0
      start_time = Time.current.to_f

      # Sleep-check loop until silence achieved or max timeout
      loop do
        return unless ownership_guard.can_publish?(epoch: ownership_epoch)

        Rails.logger.info "[SOCIALWISE-DEBOUNCE] Sleeping for #{debounce_seconds}s..."
        sleep(debounce_seconds)
        return unless ownership_guard.can_publish?(epoch: ownership_epoch)

        # Check if we should process now
        if should_process_now?(conversation_id, debounce_seconds, max_timeout_seconds)
          Rails.logger.info '[SOCIALWISE-DEBOUNCE] Ready to process, exiting sleep loop'
          break
        end

        # Safety: max timeout check (in case Redis data is inconsistent)
        elapsed = Time.current.to_f - start_time
        if elapsed >= max_timeout_seconds
          Rails.logger.info "[SOCIALWISE-DEBOUNCE] Max timeout reached after #{elapsed.round(2)}s, forcing process"
          break
        end

        Rails.logger.info '[SOCIALWISE-DEBOUNCE] New messages detected during sleep, looping...'
      end
      batch_cutoff = Time.current.to_f

      # Acquire lock to prevent race conditions during processing
      lock_key = format(Redis::Alfred::SOCIALWISE_DEBOUNCE_LOCK, conversation_id: conversation_id)
      lock_token = acquire_lock(lock_key)
      unless lock_token
        Rails.logger.info "[SOCIALWISE-DEBOUNCE] Could not acquire lock for conversation #{conversation_id}, skipping"
        return
      end

      begin
        return unless ownership_guard.can_publish?(epoch: ownership_epoch)

        process_debounced_messages(
          conversation,
          hook,
          event_name,
          ownership_guard: ownership_guard,
          ownership_epoch: ownership_epoch,
          cutoff: batch_cutoff,
          expiry_seconds: debounce_expiry_seconds(max_timeout_ms)
        )
      ensure
        release_lock(lock_key, lock_token)
      end
    ensure
      active_released = release_active(active_key, active_token).to_i.positive?
      if active_released || Redis::Alfred.get(active_key).blank?
        schedule_successor_if_pending(
          conversation_id: conversation_id,
          hook_id: hook_id,
          event_name: event_name,
          debounce_ms: debounce_ms,
          max_timeout_ms: max_timeout_ms,
          ownership_guard: ownership_guard
        )
      end
      Rails.logger.info "[SOCIALWISE-DEBOUNCE] Active marker release completed for conversation #{conversation_id}"
    end
  end

  private

  # Determine if this job should process now based on silence time and max timeout
  def should_process_now?(conversation_id, debounce_seconds, max_timeout_seconds)
    current_time = Time.current.to_f

    first_at_key = format(Redis::Alfred::SOCIALWISE_DEBOUNCE_FIRST_AT, conversation_id: conversation_id)
    last_at_key = format(Redis::Alfred::SOCIALWISE_DEBOUNCE_LAST_AT, conversation_id: conversation_id)

    first_at = Redis::Alfred.get(first_at_key)&.to_f
    last_at = Redis::Alfred.get(last_at_key)&.to_f

    # If no timestamps, something went wrong - process anyway
    if first_at.nil? || last_at.nil?
      Rails.logger.warn '[SOCIALWISE-DEBOUNCE] Missing timestamps, processing anyway'
      return true
    end

    time_since_first = current_time - first_at
    time_since_last = current_time - last_at

    Rails.logger.info "[SOCIALWISE-DEBOUNCE] Silence: #{time_since_last.round(2)}s, Total: #{time_since_first.round(2)}s"

    # Check 1: Has max timeout been reached? Process immediately
    if time_since_first >= max_timeout_seconds
      Rails.logger.info "[SOCIALWISE-DEBOUNCE] MAX TIMEOUT reached (#{time_since_first.round(2)}s >= #{max_timeout_seconds}s)"
      return true
    end

    # Check 2: Has enough silence passed since last message?
    if time_since_last >= debounce_seconds
      Rails.logger.info "[SOCIALWISE-DEBOUNCE] SILENCE reached (#{time_since_last.round(2)}s >= #{debounce_seconds}s)"
      return true
    end

    # Not ready yet - a newer message reset the timer
    false
  end

  def process_debounced_messages(conversation, hook, event_name, ownership_guard:, ownership_epoch:, cutoff:, expiry_seconds:)
    messages_key = format(Redis::Alfred::SOCIALWISE_DEBOUNCE_MESSAGES, conversation_id: conversation.id)
    first_at_key = format(Redis::Alfred::SOCIALWISE_DEBOUNCE_FIRST_AT, conversation_id: conversation.id)
    last_at_key = format(Redis::Alfred::SOCIALWISE_DEBOUNCE_LAST_AT, conversation_id: conversation.id)

    return unless ownership_guard.can_publish?(epoch: ownership_epoch)

    pending_messages_json = claim_pending_messages(
      messages_key: messages_key,
      first_at_key: first_at_key,
      last_at_key: last_at_key,
      ownership_epoch: ownership_epoch,
      cutoff: cutoff,
      expiry_seconds: expiry_seconds
    )

    if pending_messages_json.blank?
      Rails.logger.info "[SOCIALWISE-DEBOUNCE] No pending messages for conversation #{conversation.id}"
      return
    end

    return unless ownership_guard.can_publish?(epoch: ownership_epoch)

    pending_messages = pending_messages_json.map { |json| JSON.parse(json) }
    pending_messages.sort_by! { |m| m['timestamp'] }

    Rails.logger.info "[SOCIALWISE-DEBOUNCE] Found #{pending_messages.count} pending messages for conversation #{conversation.id}"

    # Get the last message to use as reference for the response
    last_message_id = pending_messages.last['message_id']
    last_message = Message.find_by(id: last_message_id)

    unless last_message
      Rails.logger.warn "[SOCIALWISE-DEBOUNCE] Last message not found: #{last_message_id}"
      return
    end

    # Concatenate all message contents
    concatenated_content = pending_messages.filter_map { |m| m['content'] }.join("\n")

    Rails.logger.info "[SOCIALWISE-DEBOUNCE] Concatenated #{pending_messages.count} messages for conversation #{conversation.id}"
    Rails.logger.info "[SOCIALWISE-DEBOUNCE] Content: #{concatenated_content.truncate(200)}"

    # Build event_data with concatenated content
    event_data = {
      message: last_message,
      conversation: conversation,
      contact: conversation.contact,
      inbox: conversation.inbox
    }

    # Process with the SocialWise Flow processor using concatenated content
    return unless ownership_guard.can_publish?(epoch: ownership_epoch)

    processor = Integrations::SocialwiseFlow::DebounceProcessorService.new(
      event_name: event_name,
      hook: hook,
      event_data: event_data,
      concatenated_content: concatenated_content,
      ownership_epoch: ownership_epoch
    )
    return unless ownership_guard.can_publish?(epoch: ownership_epoch)

    processor.perform

    Rails.logger.info "[SOCIALWISE-DEBOUNCE] Processing completed for conversation #{conversation.id}"
  end

  def acquire_lock(key)
    # Try to acquire lock with 60 second expiry (longer than debounce to be safe)
    token = SecureRandom.uuid
    Redis::Alfred.set(key, token, nx: true, ex: 60) ? token : nil
  end

  def acquire_active(key, expiry_seconds)
    token = SecureRandom.uuid
    Redis::Alfred.set(key, token, nx: true, ex: expiry_seconds) ? token : nil
  end

  def claim_pending_messages(messages_key:, first_at_key:, last_at_key:, ownership_epoch:, cutoff:, expiry_seconds:)
    with_redis do |connection|
      connection.eval(
        CLAIM_SCRIPT,
        keys: [messages_key, first_at_key, last_at_key],
        argv: [ownership_epoch, cutoff, expiry_seconds]
      )
    end
  end

  def debounce_expiry_seconds(max_timeout_ms)
    ((max_timeout_ms / 1000.0) * 1.5).ceil + 60
  end

  def schedule_successor_if_pending(conversation_id:, hook_id:, event_name:, debounce_ms:, max_timeout_ms:, ownership_guard:)
    messages_key = format(Redis::Alfred::SOCIALWISE_DEBOUNCE_MESSAGES, conversation_id: conversation_id)
    pending_epochs(messages_key).each do |pending_epoch|
      next unless ownership_guard.can_publish?(epoch: pending_epoch)

      self.class.perform_later(conversation_id, hook_id, event_name, debounce_ms, max_timeout_ms, pending_epoch)
      return true
    end

    false
  end

  def pending_epochs(messages_key)
    with_redis { |connection| connection.lrange(messages_key, 0, -1) }
      .filter_map { |raw| buffered_epoch(raw) }
      .uniq
  end

  def buffered_epoch(raw)
    value = JSON.parse(raw)['ownership_epoch']
    value if valid_ownership_epoch?(value)
  rescue JSON::ParserError, TypeError
    nil
  end

  def valid_ownership_epoch?(value)
    value.is_a?(Integer) && value >= 0
  end

  def release_lock(key, token)
    release_owned_key(key, token)
  end

  def release_active(key, token)
    release_owned_key(key, token)
  end

  def release_owned_key(key, token)
    with_redis do |connection|
      connection.eval(COMPARE_DELETE_SCRIPT, keys: [key], argv: [token])
    end
  end

  def with_redis(&)
    # rubocop:disable Style/GlobalVars
    $alfred.with(&)
    # rubocop:enable Style/GlobalVars
  end
end
