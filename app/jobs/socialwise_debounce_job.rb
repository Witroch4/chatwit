# Job to process debounced messages for SocialWise Flow integration
# This job collects multiple rapid messages from a conversation and sends them
# as a single concatenated message to the SocialWise Flow AI for processing.
class SocialwiseDebounceJob < ApplicationJob
  queue_as :medium

  def perform(conversation_id, hook_id, event_name)
    Rails.logger.info "[SOCIALWISE-DEBOUNCE] Processing debounced messages for conversation #{conversation_id}"

    conversation = Conversation.find_by(id: conversation_id)
    hook = Integrations::Hook.find_by(id: hook_id)

    unless conversation && hook
      Rails.logger.warn "[SOCIALWISE-DEBOUNCE] Conversation or hook not found: conversation=#{conversation_id}, hook=#{hook_id}"
      return
    end

    # Acquire lock to prevent race conditions
    lock_key = format(Redis::Alfred::SOCIALWISE_DEBOUNCE_LOCK, conversation_id: conversation_id)
    unless acquire_lock(lock_key)
      Rails.logger.info "[SOCIALWISE-DEBOUNCE] Could not acquire lock for conversation #{conversation_id}, skipping"
      return
    end

    begin
      process_debounced_messages(conversation, hook, event_name)
    ensure
      release_lock(lock_key)
    end
  end

  private

  def process_debounced_messages(conversation, hook, event_name)
    messages_key = format(Redis::Alfred::SOCIALWISE_DEBOUNCE_MESSAGES, conversation_id: conversation.id)

    # Get all pending messages
    pending_messages_json = Redis::Alfred.lrange(messages_key, 0, -1)

    if pending_messages_json.blank?
      Rails.logger.info "[SOCIALWISE-DEBOUNCE] No pending messages for conversation #{conversation.id}"
      return
    end

    # Parse and sort messages by timestamp
    pending_messages = pending_messages_json.map { |json| JSON.parse(json) }
    pending_messages.sort_by! { |m| m['timestamp'] }

    Rails.logger.info "[SOCIALWISE-DEBOUNCE] Found #{pending_messages.count} pending messages for conversation #{conversation.id}"

    # Clear the pending messages from Redis
    Redis::Alfred.delete(messages_key)

    # Get the last message to use as reference for the response
    last_message_id = pending_messages.last['message_id']
    last_message = Message.find_by(id: last_message_id)

    unless last_message
      Rails.logger.warn "[SOCIALWISE-DEBOUNCE] Last message not found: #{last_message_id}"
      return
    end

    # Concatenate all message contents
    concatenated_content = pending_messages.map { |m| m['content'] }.compact.join("\n")

    Rails.logger.info "[SOCIALWISE-DEBOUNCE] Concatenated content for conversation #{conversation.id}: #{concatenated_content.truncate(200)}"

    # Build event_data with concatenated content
    event_data = {
      message: last_message,
      conversation: conversation,
      contact: conversation.contact,
      inbox: conversation.inbox
    }

    # Process with the SocialWise Flow processor using concatenated content
    processor = Integrations::SocialwiseFlow::DebounceProcessorService.new(
      event_name: event_name,
      hook: hook,
      event_data: event_data,
      concatenated_content: concatenated_content
    )
    processor.perform

    Rails.logger.info "[SOCIALWISE-DEBOUNCE] Processing completed for conversation #{conversation.id}"
  end

  def acquire_lock(key)
    # Try to acquire lock with 30 second expiry
    Redis::Alfred.set(key, '1', nx: true, ex: 30)
  end

  def release_lock(key)
    Redis::Alfred.delete(key)
  end
end
