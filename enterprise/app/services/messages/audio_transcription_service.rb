class Messages::AudioTranscriptionService
  attr_reader :attachment, :message, :account

  def initialize(attachment)
    @attachment = attachment
    @message = attachment.message
    @account = message&.account
  end

  def perform
    return { error: 'Message not found' } if message.blank?
    return { error: 'Transcription disabled for this inbox' } if call_recording_transcription_disabled?

    gate_error = transcription_gate_error
    return { error: gate_error } if gate_error.present?
    return { error: 'Audio too large for transcription' } if Llm::SpeechToTextService.too_large?(attachment.file&.blob)

    transcriptions = transcribe_audio
    Rails.logger.info "Audio transcription successful: #{transcriptions}"
    { success: true, transcriptions: transcriptions }
  rescue Faraday::UnauthorizedError
    Rails.logger.warn('Skipping audio transcription: OpenAI configuration is invalid or disabled (401 Unauthorized).')
    { error: 'OpenAI configuration is invalid or disabled (401)' }
  end

  private

  # Chatwit: distinct error per gate — the shared 'Transcription limit exceeded' covers
  # three unrelated causes and misled diagnostics twice.
  def transcription_gate_error
    return 'Captain feature disabled for this account' unless account.feature_enabled?('captain_integration')
    return 'Audio transcription disabled in account settings' if account.audio_transcriptions.blank?
    return 'Captain responses quota exhausted' unless account.usage_limits[:captain][:responses][:current_available].positive?

    nil
  end

  # Call recordings honour the inbox's "Transcribe recordings" setting; ordinary voice notes don't.
  def call_recording_transcription_disabled?
    message.voice_call? && !message.inbox.channel.transcription_enabled?
  end

  def transcribe_audio
    transcribed_text = attachment.meta&.[]('transcribed_text') || ''
    return transcribed_text if transcribed_text.present?

    transcribed_text = Llm::SpeechToTextService.new(blob: attachment.file.blob, account: account).perform
    update_transcription(transcribed_text)
    transcribed_text
  end

  def update_transcription(transcribed_text)
    return if transcribed_text.blank?

    attachment.update!(meta: { transcribed_text: transcribed_text })
    message.reload.send_update_event

    return unless ChatwootApp.advanced_search_allowed?

    message.reindex
  end
end
