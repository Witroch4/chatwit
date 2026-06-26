# Serves a browser-compatible (MP3) playback version of an audio attachment.
#
# WhatsApp audio arrives as OGG/Opus, which iOS WebKit (every browser on iPhone)
# cannot decode. The MP3 is produced on demand by Audio::Mp3TranscodeService.
#
# This endpoint is intentionally NOT under the authenticated API namespace:
# a native <audio> element cannot send the devise-token-auth headers the API
# requires, so it would always get 401. Instead we authorize via a signed_id
# capability token (same security model as ActiveStorage's public blob URLs that
# already serve the raw attachment via `data_url`). Inherits from
# ActionController::Base to skip all middleware/authentication, like HealthController.
class AudioPlaybackController < ActionController::Base # rubocop:disable Rails/ApplicationController
  def show
    attachment = Attachment.find_signed!(params[:signed_id], purpose: :audio_playback)
    return head :not_found unless attachment.audio? && attachment.file.attached?

    blob = Audio::Mp3TranscodeService.new(attachment: attachment).perform
    redirect_to playable_url(blob), allow_other_host: true
  rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
    head :not_found
  rescue Audio::Mp3TranscodeService::TranscodeError => e
    Rails.logger.warn("[AUDIO_PLAYBACK] MP3 transcode failed for signed attachment: #{e.message}")
    fallback_to_original
  end

  private

  # Inline (not attachment) disposition so the <audio> element plays it instead
  # of triggering a download, and a direct presigned service URL so iOS gets a
  # single Range-capable response.
  def playable_url(blob)
    ActiveStorage::Current.url_options = Rails.application.routes.default_url_options if ActiveStorage::Current.url_options.blank?
    blob.url(disposition: :inline)
  end

  # Last resort when transcoding fails: serve the original file so non-iOS
  # clients can still play it (iOS cannot decode Opus regardless).
  def fallback_to_original
    attachment = Attachment.find_signed(params[:signed_id], purpose: :audio_playback)
    return head :unprocessable_entity unless attachment&.file&.attached?

    redirect_to playable_url(attachment.file.blob), allow_other_host: true
  end
end
