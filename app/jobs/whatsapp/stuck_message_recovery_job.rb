# Chatwit customization (not native Chatwoot).
#
# Recovers outgoing WhatsApp Cloud messages that the Meta API *accepted*
# (returned a wamid, no error) but then silently never delivered: they stay
# stuck at status `sent` forever, with no `delivered` and no `failed` webhook.
#
# WhatsApp normally delivers within seconds and reports a `failed` status when
# it can't. When it goes silent after `sent`, nothing else in the app notices,
# so the message just sits at a single grey check and the agent only finds out
# when the customer complains.
#
# Strategy (chosen with the team): resend once automatically; if it is still
# stuck after the resend, flag it as `failed` so the agent sees the red badge +
# resend button and knows delivery failed.
class Whatsapp::StuckMessageRecoveryJob < ApplicationJob
  queue_as :low

  # A message must sit in `sent` at least this long before we treat it as stuck.
  STUCK_AFTER = 10.minutes
  # Don't resurrect very old sends (e.g. after a long outage/backfill).
  MAX_AGE = 6.hours

  def perform
    inbox_ids = whatsapp_cloud_inbox_ids
    return if inbox_ids.blank?

    stuck_messages(inbox_ids).find_each do |message|
      process(message)
    rescue StandardError => e
      Rails.logger.error("[WA-STUCK-RECOVERY] Error processing message #{message.id}: #{e.message}")
    end
  end

  private

  def whatsapp_cloud_inbox_ids
    channel_ids = Channel::Whatsapp.where(provider: 'whatsapp_cloud').ids
    Inbox.where(channel_type: 'Channel::Whatsapp', channel_id: channel_ids).ids
  end

  def stuck_messages(inbox_ids)
    # message_type: :outgoing already excludes official templates (message_type :template).
    Message.where(inbox_id: inbox_ids, message_type: :outgoing, status: :sent, private: false)
           .where(created_at: (Time.current - MAX_AGE)..(Time.current - STUCK_AFTER))
  end

  def process(message)
    message.reload
    # A delivery/read/failed webhook may have landed since the query was built.
    return unless message.status == 'sent'
    return if nothing_to_send?(message)
    # Never auto-resend anything that would re-trigger a paid WhatsApp template.
    return if template_message?(message)

    if message.additional_attributes&.dig('stuck_recovery_resent_at').blank?
      resend(message)
    else
      flag_failed(message)
    end
  end

  def resend(message)
    channel = message.inbox.channel
    recipient = message.conversation.contact_inbox.source_id

    # Record the attempt first: even if the send raises (network error), we must
    # never resend the same message again — the next run flags it instead.
    record_resend_attempt(message)
    new_source_id = channel.send_message(recipient, message)

    if new_source_id.present?
      # Point the message at the new wamid so its delivery webhook matches.
      message.update!(source_id: new_source_id)
      Rails.logger.info("[WA-STUCK-RECOVERY] Resent stuck message #{message.id}, new wamid=#{new_source_id}")
    else
      # channel.send_message already marked it failed via handle_error when the API errored.
      Rails.logger.warn("[WA-STUCK-RECOVERY] Resend of message #{message.id} returned no id (send failed)")
    end
  end

  def flag_failed(message)
    resent_at = Time.zone.parse(message.additional_attributes['stuck_recovery_resent_at'].to_s)
    # Give the resend its own grace period before declaring it failed.
    return if resent_at.present? && Time.current - resent_at < STUCK_AFTER

    message.update!(
      status: :failed,
      external_error: 'Entrega não confirmada pela WhatsApp após reenvio automático. Reenvie manualmente.'
    )
    Rails.logger.warn("[WA-STUCK-RECOVERY] Flagged message #{message.id} as failed (undelivered after resend)")
  end

  def record_resend_attempt(message)
    attrs = (message.additional_attributes || {}).merge('stuck_recovery_resent_at' => Time.current.iso8601)
    message.update!(additional_attributes: attrs)
  end

  def nothing_to_send?(message)
    message.content.blank? && message.attachments.blank? && message.content_attributes.blank?
  end

  def template_message?(message)
    attrs = message.content_attributes || {}
    attrs['template_payload'].present? || attrs['template'].present? ||
      message.additional_attributes&.dig('template_params').present?
  end
end
