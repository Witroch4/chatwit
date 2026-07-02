# Chatwit: builds the dossier ZIP in background and publishes status via Redis
class Conversations::DossierExportJob < ApplicationJob
  queue_as :default

  def perform(conversation_id, message_ids, dossier_id)
    conversation = Conversation.find(conversation_id)
    write_status(conversation, dossier_id, status: 'processing')

    blob = Conversations::DossierBuilderService.new(conversation: conversation, message_ids: message_ids).perform
    url = Rails.application.routes.url_helpers.rails_blob_url(blob, disposition: 'attachment')

    write_status(conversation, dossier_id, status: 'completed', url: url, filename: blob.filename.to_s)
    Conversations::DossierCleanupJob.set(wait: Conversations::DossierStatus::EXPIRY).perform_later(blob.id)
  rescue StandardError => e
    write_status(conversation, dossier_id, status: 'failed', error: e.message) if conversation.present?
    ChatwootExceptionTracker.new(e, account: conversation&.account).capture_exception
  end

  private

  def write_status(conversation, dossier_id, payload)
    Conversations::DossierStatus.write(conversation.account_id, conversation.display_id, dossier_id, payload)
  end
end
