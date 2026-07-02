# Chatwit: builds the dossier ZIP in background (fire-and-forget) and delivers it
# as a private note on the conversation. The requesting agent does not need to
# keep the chat open: the ZIP is attached to the note (MinIO via ActiveStorage)
# and stays downloadable from the message history anywhere. Failures are also
# reported as a private note.
class Conversations::DossierExportJob < ApplicationJob
  queue_as :default

  # user_id defaults to nil so jobs enqueued before the fire-and-forget rollout
  # still deserialize.
  def perform(conversation_id, message_ids, dossier_id, user_id = nil)
    conversation = Conversation.find(conversation_id)
    user = User.find_by(id: user_id)
    write_status(conversation, dossier_id, status: 'processing')

    blob = Conversations::DossierBuilderService.new(conversation: conversation, message_ids: message_ids).perform
    message = deliver_dossier_note(conversation, user, blob, message_ids.size)

    write_status(conversation, dossier_id, status: 'completed', message_id: message.id, filename: blob.filename.to_s)
  rescue StandardError => e
    handle_failure(conversation, user, dossier_id, e)
  end

  private

  def deliver_dossier_note(conversation, user, blob, count)
    content = with_account_locale(conversation) do
      I18n.t('conversations.dossier.ready_note', filename: blob.filename.to_s, count: count)
    end
    message = build_private_note(conversation, user, content)
    attachment = message.attachments.new(account_id: conversation.account_id, file_type: :file)
    attachment.file.attach(blob)
    message.save!
    message
  end

  def handle_failure(conversation, user, dossier_id, error)
    ChatwootExceptionTracker.new(error, account: conversation&.account).capture_exception
    return if conversation.blank?

    write_status(conversation, dossier_id, status: 'failed', error: error.message)
    deliver_error_note(conversation, user, error)
  rescue StandardError => e
    Rails.logger.error("[DOSSIER] failed to deliver error note: #{e.message}")
  end

  def deliver_error_note(conversation, user, error)
    content = with_account_locale(conversation) do
      I18n.t('conversations.dossier.failed_note', error: error.message)
    end
    build_private_note(conversation, user, content).save!
  end

  def build_private_note(conversation, user, content)
    conversation.messages.build(
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      message_type: :outgoing,
      private: true,
      sender: user,
      content: content
    )
  end

  def with_account_locale(conversation, &)
    locale = conversation.account.locale.presence || I18n.default_locale
    I18n.with_locale(locale, &)
  rescue I18n::InvalidLocale
    yield
  end

  def write_status(conversation, dossier_id, payload)
    Conversations::DossierStatus.write(conversation.account_id, conversation.display_id, dossier_id, payload)
  end
end
