# Chatwit: "Captain Whisper" — canonical audio transcription through the
# platform LiteLLM proxy (OpenAI chat completions + input_audio, base64 mp3).
#
# Model comes from CAPTAIN_WITDEV_TRANSCRIPTION_MODEL (super admin → Captain),
# defaulting to the tested legal-grade alias. Only witdev_antigravity/* aliases
# carry audio for real — copilot routes hallucinate transcriptions and codex
# routes reject input_audio (see witdev-platform-core
# docs/agent-memory/witdev-audio-transcription.md).
#
# Result is cached in attachment.meta['transcribed_text'], same slot the legacy
# Messages::AudioTranscriptionService uses, so both paths reuse each other.
class Chatwit::AudioTranscriptionService
  RECOMMENDED_MODEL = 'witdev_antigravity/gemini-3.1-pro-low'.freeze
  # Only these alias families actually carry audio through the proxy. Copilot
  # returns 200 OK with a fully hallucinated transcription (audio dropped),
  # codex rejects input_audio (HTTP 400) and Claude models have no audio input.
  AUDIO_ALIAS_ALLOWLIST = %w[witdev_antigravity/ gemini-].freeze
  # Doc: inline base64 is reliable up to ~15-20MB of audio; larger files need chunking.
  MAX_AUDIO_BYTES = 15.megabytes
  REQUEST_TIMEOUT_SECONDS = 180

  TRANSCRIPTION_PROMPT = <<~PROMPT.freeze
    Transcreva este áudio na íntegra, em português, de forma literal (verbatim),
    sem corrigir gramática nem parafrasear. Regras:
    - Marque trechos incompreensíveis como [inaudível].
    - Se houver mais de um falante, identifique como Falante 1, Falante 2...
    - Preserve gírias e regionalismos exatamente como falados; se um termo for
      regional/ambíguo, adicione nota entre colchetes explicando o significado provável.
    - Responda somente com a transcrição, sem comentários adicionais.
  PROMPT

  pattr_initialize [:attachment!]

  def self.available?
    Chatwit::LlmProxy.api_key.present?
  end

  def self.model
    InstallationConfig.find_by(name: 'CAPTAIN_WITDEV_TRANSCRIPTION_MODEL')&.value.presence || RECOMMENDED_MODEL
  end

  def self.resolved_model
    Chatwit::LlmProxy.resolve_model!(model)
  end

  def self.audio_capable?(alias_name)
    AUDIO_ALIAS_ALLOWLIST.any? { |prefix| alias_name.to_s.start_with?(prefix) }
  end

  def perform
    existing = attachment.meta&.[]('transcribed_text')
    return { success: true, transcriptions: existing } if existing.present?

    gate_error = precondition_error
    return { error: gate_error } if gate_error.present?

    transcribe
  rescue StandardError => e
    Rails.logger.warn("[CHATWIT][CAPTAIN_WHISPER] transcription failed for attachment ##{attachment.id}: #{e.message}")
    { error: e.message }
  end

  private

  def precondition_error
    return 'WitDev proxy API key not configured' unless self.class.available?
    return "model #{resolved_model} does not support audio (use witdev_antigravity/*)" unless self.class.audio_capable?(resolved_model)

    nil
  end

  def transcribe
    audio_base64 = encode_audio
    return { error: "audio larger than #{MAX_AUDIO_BYTES / 1.megabyte}MB" } if audio_base64.blank?

    text = request_transcription(audio_base64)
    return { error: 'proxy returned an empty transcription' } if text.blank?

    cache_transcription(text)
    { success: true, transcriptions: text }
  end

  # Reuses the dossier mp3 pipeline (cached playback_file / ffmpeg fallback)
  # so the proxy always receives mp3, whatever the original codec was.
  def encode_audio
    Conversations::DossierAudioService.new(attachment: attachment).open_mp3 do |io|
      data = io.read
      data.bytesize > MAX_AUDIO_BYTES ? nil : Base64.strict_encode64(data)
    end
  end

  def request_transcription(audio_base64)
    response = HTTParty.post(
      "#{Chatwit::LlmProxy.api_base}/chat/completions",
      timeout: REQUEST_TIMEOUT_SECONDS,
      headers: {
        'Content-Type' => 'application/json',
        'Authorization' => "Bearer #{Chatwit::LlmProxy.api_key}"
      },
      body: request_body(audio_base64)
    )
    raise "LiteLLM proxy returned HTTP #{response.code}" unless response.success?

    response.parsed_response.dig('choices', 0, 'message', 'content').to_s.strip
  end

  def request_body(audio_base64)
    {
      model: resolved_model,
      messages: [{
        role: 'user',
        content: [
          { type: 'text', text: TRANSCRIPTION_PROMPT },
          { type: 'input_audio', input_audio: { data: audio_base64, format: 'mp3' } }
        ]
      }]
    }.to_json
  end

  def cache_transcription(text)
    attachment.update!(meta: (attachment.meta || {}).merge('transcribed_text' => text))
  end

  def resolved_model
    @resolved_model ||= self.class.resolved_model
  end
end
