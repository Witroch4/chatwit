require 'zip'

# Chatwit: builds the judicial dossier ZIP for selected messages of a conversation.
# Layout (see chatwitdocs/baixar-dossie.md):
#   transcricao.txt          full transcript (date/time, display name, content, attachment refs)
#   imagens/NNN-<name>       selected images
#   audios/NNN-<name>.mp3    audios converted to mp3
#   audios/transcricoes.txt  per-audio transcriptions keyed by file name
#   arquivos/NNN-<name>      any other attachment (video, documents)
class Conversations::DossierBuilderService
  TIMEZONE = 'America/Sao_Paulo'.freeze
  TIMEZONE_LABEL = 'horário de Brasília'.freeze
  MAX_ATTACHMENT_BYTES = 200.megabytes
  SEPARATOR = ('-' * 72).freeze

  pattr_initialize [:conversation!, :message_ids!]

  def perform
    @audio_transcription_entries = []
    zip_file = Tempfile.new(['chatwit-dossie', '.zip'])
    build_zip(zip_file.path)
    zip_file.rewind
    create_blob(zip_file)
  ensure
    zip_file&.close
    zip_file&.unlink
  end

  private

  def messages
    @messages ||= conversation.messages
                              .includes(:sender, { attachments: { file_attachment: :blob } })
                              .where(id: message_ids)
                              .order(:created_at, :id)
  end

  def build_zip(zip_path)
    Zip::OutputStream.open(zip_path) do |zip|
      attachment_index = 0
      transcript_lines = [transcript_header]

      messages.each do |message|
        transcript_lines << ''
        transcript_lines << message_heading(message)
        transcript_lines << message_body(message) if message_body(message).present?

        message.attachments.each do |attachment|
          attachment_index += 1
          transcript_lines.concat(write_attachment(zip, attachment, attachment_index))
        end
      end

      zip.put_next_entry('transcricao.txt')
      zip.write("#{transcript_lines.join("\n")}\n")

      write_audio_transcriptions_file(zip)
    end
  end

  def transcript_header
    <<~HEADER
      DOSSIÊ DE CONVERSA
      #{SEPARATOR}
      Conta: #{conversation.account.name}
      Conversa: ##{conversation.display_id}
      Caixa de entrada: #{conversation.inbox&.name}
      Contato: #{contact_line}
      Mensagens incluídas: #{messages.size}
      Período: #{period_line}
      Gerado em: #{format_time(Time.current)} (#{TIMEZONE_LABEL})
      Todos os horários deste documento estão no fuso #{TIMEZONE} (#{TIMEZONE_LABEL}).
      Documento gerado automaticamente pelo Chatwit a partir do histórico original da conversa.
      #{SEPARATOR}
    HEADER
  end

  def contact_line
    contact = conversation.contact
    [contact&.name, contact&.phone_number, contact&.email].filter_map(&:presence).join(' — ')
  end

  def period_line
    [messages.first, messages.last].compact.map { |message| format_time(message.created_at) }.uniq.join(' até ')
  end

  def message_heading(message)
    heading = "[#{format_time(message.created_at)}] #{sender_name(message)}:"
    heading += ' (Nota privada)' if message.private?
    heading
  end

  def message_body(message)
    return '[mensagem apagada]' if message.content_attributes[:deleted].present?

    message.content.to_s.strip
  end

  def sender_name(message)
    return 'Sistema' if message.activity?

    message.sender&.name.presence ||
      (message.incoming? ? conversation.contact&.name.presence : nil) ||
      'Atendimento (automação)'
  end

  def write_attachment(zip, attachment, index)
    blob = attachment.file.attached? ? attachment.file.blob : nil
    return external_attachment_lines(attachment) if blob.blank?
    return ["    [Anexo ignorado por exceder o tamanho máximo: #{blob.filename}]"] if blob.byte_size > MAX_ATTACHMENT_BYTES

    case attachment.file_type.to_s
    when 'audio'
      write_audio_attachment(zip, attachment, blob, index)
    when 'image'
      entry_name = "imagens/#{entry_base_name(blob, index)}"
      write_blob_entry(zip, entry_name, blob)
      ["    [Imagem: #{entry_name}]"]
    else
      entry_name = "arquivos/#{entry_base_name(blob, index)}"
      write_blob_entry(zip, entry_name, blob)
      ["    [Arquivo (#{attachment.file_type}): #{entry_name}]"]
    end
  end

  def external_attachment_lines(attachment)
    return ["    [Anexo externo (#{attachment.file_type}): #{attachment.external_url}]"] if attachment.external_url.present?

    ["    [Anexo sem arquivo disponível (#{attachment.file_type})]"]
  end

  def write_audio_attachment(zip, attachment, blob, index)
    audio_service = Conversations::DossierAudioService.new(attachment: attachment)
    written_entry = write_audio_entry(zip, audio_service, attachment, blob, index)
    transcription = audio_service.transcription
    @audio_transcription_entries << { entry: File.basename(written_entry), message: attachment.message, text: transcription }

    ["    [Áudio: #{written_entry}]", "    Transcrição do áudio: #{transcription}"]
  end

  # Returns the entry name actually written (falls back to the original format when transcoding fails).
  def write_audio_entry(zip, audio_service, attachment, blob, index)
    mp3_entry = "audios/#{format('%03d', index)}-#{sanitized_base_name(blob)}.mp3"
    audio_service.open_mp3 do |mp3_io|
      zip.put_next_entry(mp3_entry)
      copy_to_zip(mp3_io, zip)
    end
    mp3_entry
  rescue StandardError => e
    Rails.logger.warn("[DOSSIER] mp3 conversion failed for attachment ##{attachment.id}: #{e.message}")
    original_entry = "audios/#{entry_base_name(blob, index)}"
    write_blob_entry(zip, original_entry, blob)
    original_entry
  end

  def write_audio_transcriptions_file(zip)
    return if @audio_transcription_entries.blank?

    lines = ["TRANSCRIÇÕES DOS ÁUDIOS (fuso #{TIMEZONE} — #{TIMEZONE_LABEL})", SEPARATOR]
    @audio_transcription_entries.each do |item|
      lines << ''
      lines << "Arquivo: #{item[:entry]}"
      lines << "Enviado em: #{format_time(item[:message].created_at)} por #{sender_name(item[:message])}"
      lines << "Transcrição: #{item[:text]}"
      lines << SEPARATOR
    end
    zip.put_next_entry('audios/transcricoes.txt')
    zip.write("#{lines.join("\n")}\n")
  end

  def write_blob_entry(zip, entry_name, blob)
    zip.put_next_entry(entry_name)
    blob.open { |file| copy_to_zip(file, zip) }
  end

  def copy_to_zip(io, zip)
    while (chunk = io.read(1.megabyte))
      zip << chunk
    end
  end

  def entry_base_name(blob, index)
    extension = blob.filename.extension_with_delimiter
    "#{format('%03d', index)}-#{sanitized_base_name(blob)}#{extension}"
  end

  def sanitized_base_name(blob)
    base = ActiveStorage::Filename.new(blob.filename.base.to_s).sanitized
    base.presence&.first(80) || 'anexo'
  end

  def format_time(time)
    time.in_time_zone(TIMEZONE).strftime('%d/%m/%Y %H:%M:%S')
  end

  def create_blob(zip_file)
    ActiveStorage::Blob.create_and_upload!(
      io: zip_file,
      filename: "dossie-conversa-#{conversation.display_id}-#{Time.current.in_time_zone(TIMEZONE).strftime('%Y%m%d-%H%M')}.zip",
      content_type: 'application/zip'
    )
  end
end
