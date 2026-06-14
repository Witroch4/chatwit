class Stickers::ConvertJob < ApplicationJob
  queue_as :medium

  # Converts a processing sticker's original upload into a WhatsApp-compliant webp
  # in the background, then flips it to :ready. The original stays attached as a
  # preview until the converted file replaces it, so the UI shows it instantly.
  def perform(sticker_id)
    sticker = Sticker.find_by(id: sticker_id)
    return if sticker.nil? || sticker.ready?

    bytes = sticker.file.blob.open(&:read)
    webp, animated = Stickers::ConverterService.new(bytes: bytes).to_webp
    sticker.file.attach(io: StringIO.new(webp), filename: 'sticker.webp', content_type: 'image/webp')
    sticker.update!(animated: animated, status: :ready)
  rescue Stickers::ConverterService::InvalidSource => e
    Rails.logger.error "[STICKER] convert job failed (#{sticker_id}): #{e.message}"
    sticker&.update!(status: :failed)
  end
end
