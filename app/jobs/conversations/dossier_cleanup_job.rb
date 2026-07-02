# Chatwit: purges the dossier ZIP blob after the download window (judicial data must not linger)
class Conversations::DossierCleanupJob < ApplicationJob
  queue_as :low

  def perform(blob_id)
    ActiveStorage::Blob.find_by(id: blob_id)&.purge
  end
end
