require 'open3'

# Chatwit: audio handling for the dossier export — mp3 conversion and transcription lookup.
# Reuses the fork's Audio::Mp3TranscodeService (cached playback_file) and the enterprise
# Messages::AudioTranscriptionService (Captain/Whisper) when available.
class Conversations::DossierAudioService
  TRANSCRIPTION_UNAVAILABLE = '[transcrição indisponível]'.freeze

  pattr_initialize [:attachment!]

  # Yields an IO positioned at mp3 content.
  # Raises Audio::Mp3TranscodeService::TranscodeError when conversion fails.
  def open_mp3(&)
    blob = attachment.file.blob
    return blob.open(&) if mp3_blob?(blob)
    return Audio::Mp3TranscodeService.new(attachment: attachment).perform.open(&) if Audio::Mp3TranscodeService.requires_transcode?(attachment)

    adhoc_transcode(blob, &)
  end

  def transcription
    existing = attachment.meta&.[]('transcribed_text')
    return quoted(existing) if existing.present?

    # Canonical flow: "Captain Whisper" via the platform LiteLLM proxy.
    # Legacy Whisper (OpenAI key + Captain account gates) stays as fallback.
    return format_transcription_result(Chatwit::AudioTranscriptionService.new(attachment: attachment).perform) if witdev_transcription?
    return TRANSCRIPTION_UNAVAILABLE unless defined?(Messages::AudioTranscriptionService)

    format_transcription_result(Messages::AudioTranscriptionService.new(attachment).perform)
  rescue StandardError => e
    Rails.logger.warn("[DOSSIER] transcription failed for attachment ##{attachment.id}: #{e.message}")
    TRANSCRIPTION_UNAVAILABLE
  end

  private

  def witdev_transcription?
    Chatwit::AudioTranscriptionService.available?
  end

  def mp3_blob?(blob)
    blob.content_type.to_s.downcase.include?('mpeg') || blob.filename.extension_without_delimiter.to_s.casecmp('mp3').zero?
  end

  # ffmpeg fallback for audio formats Audio::Mp3TranscodeService does not cover (m4a, wav, ...)
  def adhoc_transcode(blob, &)
    blob.open do |source|
      output = Tempfile.new(['chatwit-dossie-audio', '.mp3'])
      begin
        run_ffmpeg(source.path, output.path)
        File.open(output.path, 'rb', &)
      ensure
        output.close
        output.unlink
      end
    end
  end

  def run_ffmpeg(source_path, output_path)
    _stdout, stderr, status = Open3.capture3(
      'ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-i', source_path,
      '-vn', '-acodec', 'libmp3lame', '-ar', '44100', '-ac', '1', '-b:a', '64k', output_path
    )
    return if status.success? && File.size?(output_path)

    raise Audio::Mp3TranscodeService::TranscodeError, stderr.presence || 'ffmpeg failed'
  end

  def format_transcription_result(result)
    return TRANSCRIPTION_UNAVAILABLE unless result.is_a?(Hash)
    return quoted(result[:transcriptions]) if result[:success] && result[:transcriptions].present?
    return "[transcrição indisponível: #{result[:error]}]" if result[:error].present?

    TRANSCRIPTION_UNAVAILABLE
  end

  def quoted(text)
    "\"#{text}\""
  end
end
