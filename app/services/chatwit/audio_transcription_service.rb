# Chatwit: "Captain Whisper" — canonical audio transcription through the
# platform LiteLLM proxy.
#
# Model comes from CAPTAIN_WITDEV_TRANSCRIPTION_MODEL (super admin → Captain),
# defaulting to OpenAI's gpt-4o-transcribe through the direct API. Two transports:
# - OpenAI transcription models (gpt-4o-transcribe, gpt-4o-mini-transcribe) only
#   exist on /audio/transcriptions (multipart mp3); they are not chat models.
# - gemini-* aliases take the audio inside chat completions (input_audio, base64 mp3)
#   with the verbatim prompt below.
# Chat models without audio input are refused: Luna and Claude reject input_audio,
# copilot routes hallucinate the transcription (audio dropped) and the old
# witdev_antigravity/* aliases were retired on 23/10/2026 (see witdev-platform-core
# docs/agent-memory/witdev-audio-transcription.md).
#
# Result is cached in attachment.meta['transcribed_text'], same slot the legacy
# Messages::AudioTranscriptionService uses, so both paths reuse each other.
class Chatwit::AudioTranscriptionService
  RECOMMENDED_MODEL = 'gpt-4o-transcribe'.freeze
  # OpenAI speech-to-text models served on /audio/transcriptions (direct API).
  OPENAI_TRANSCRIPTION_MODELS = %w[gpt-4o-transcribe gpt-4o-mini-transcribe].freeze
  # Chat aliases that really carry input_audio through the proxy.
  AUDIO_ALIAS_ALLOWLIST = %w[gemini-].freeze
  TRANSCRIPTION_LANGUAGE = 'pt'.freeze
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

  def self.transcription_endpoint?(alias_name)
    OPENAI_TRANSCRIPTION_MODELS.include?(alias_name.to_s)
  end

  def self.audio_capable?(alias_name)
    transcription_endpoint?(alias_name) || AUDIO_ALIAS_ALLOWLIST.any? { |prefix| alias_name.to_s.start_with?(prefix) }
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
    return "model #{resolved_model} does not support audio (use gpt-4o-transcribe or gemini-*)" unless self.class.audio_capable?(resolved_model)

    nil
  end

  def transcribe
    text = if self.class.transcription_endpoint?(resolved_model)
             mp3 = read_mp3
             return audio_too_large if mp3.nil?

             request_audio_transcription(mp3)
           else
             audio_base64 = encode_audio
             return audio_too_large if audio_base64.blank?

             request_transcription(audio_base64)
           end
    return { error: 'proxy returned an empty transcription' } if text.blank?

    cache_transcription(text)
    { success: true, transcriptions: text }
  end

  def audio_too_large
    { error: "audio larger than #{MAX_AUDIO_BYTES / 1.megabyte}MB" }
  end

  # Reuses the dossier mp3 pipeline (cached playback_file / ffmpeg fallback)
  # so the proxy always receives mp3, whatever the original codec was.
  def read_mp3
    Conversations::DossierAudioService.new(attachment: attachment).open_mp3 do |io|
      data = io.read
      data.bytesize > MAX_AUDIO_BYTES ? nil : data
    end
  end

  def encode_audio
    mp3 = read_mp3
    mp3 && Base64.strict_encode64(mp3)
  end

  # Multipart via Net::HTTP: the LiteLLM proxy rejects HTTParty's multipart body
  # ("There was an error parsing the body").
  def request_audio_transcription(mp3)
    uri = URI("#{Chatwit::LlmProxy.api_base}/audio/transcriptions")
    request = Net::HTTP::Post.new(uri)
    request['Authorization'] = "Bearer #{Chatwit::LlmProxy.api_key}"
    request.set_form(transcription_form(mp3), 'multipart/form-data')
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 10,
                                                   read_timeout: REQUEST_TIMEOUT_SECONDS) { |http| http.request(request) }
    raise "LiteLLM proxy returned HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body).fetch('text', '').to_s.strip
  end

  def transcription_form(mp3)
    [
      ['model', resolved_model],
      ['language', TRANSCRIPTION_LANGUAGE],
      ['file', StringIO.new(mp3), { filename: 'audio.mp3', content_type: 'audio/mpeg' }]
    ]
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
