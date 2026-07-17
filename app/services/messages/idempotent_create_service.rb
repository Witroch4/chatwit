require 'digest'

class Messages::IdempotentCreateService
  class ConflictError < StandardError; end

  IDEMPOTENT_PAYLOAD_KEYS = %i[
    content private message_type content_type content_attributes attachments
    external_created_at campaign_id template_params sender_type sender_id
    email_html_content cc_emails bcc_emails to_emails echo_id
  ].freeze

  JSON_PAYLOAD_KEYS = %i[content_attributes template_params].freeze

  def initialize(user:, conversation:, params:)
    @user = user
    @conversation = conversation
    @params = params
    @idempotency_key = params[:idempotency_key].to_s.strip
    raise ArgumentError, 'Idempotency key cannot be blank' if @idempotency_key.blank?

    @payload_hash = Digest::SHA256.hexdigest(JSON.generate(canonical_payload))
  end

  def perform
    locked_conversation = conversation.class.find(conversation.id)
    locked_conversation.with_lock do
      existing = existing_message(locked_conversation)
      if existing
        resolve_existing!(existing)
      else
        Messages::MessageBuilder.new(
          user,
          locked_conversation,
          idempotent_message_params,
          idempotency_payload_hash: payload_hash
        ).perform
      end
    end
  rescue ActiveRecord::RecordNotUnique
    winner = existing_message(conversation)
    raise if winner.blank?

    resolve_existing!(winner)
  end

  private

  attr_reader :user, :conversation, :params, :idempotency_key, :payload_hash

  def existing_message(target_conversation)
    target_conversation.messages.find_by(idempotency_key: idempotency_key)
  end

  def resolve_existing!(message)
    if message&.idempotency_payload_hash == payload_hash
      message.echo_id = params[:echo_id]
      return message
    end

    raise ConflictError, 'Idempotency key was already used with a different payload'
  end

  def idempotent_message_params
    params.except(:source_id, 'source_id')
  end

  def canonical_payload
    payload = IDEMPOTENT_PAYLOAD_KEYS.index_with { |key| normalized_param(key) }
    payload[:private] = ActiveModel::Type::Boolean.new.cast(params[:private] || false)
    payload[:message_type] = params[:message_type].presence || 'outgoing'
    payload[:content_type] = params[:content_type].presence || 'text'
    payload[:actor] = { type: user.class.name, id: user.id }
    canonicalize(payload)
  end

  def normalized_param(key)
    value = params[key]
    return value unless JSON_PAYLOAD_KEYS.include?(key) && value.is_a?(String)

    JSON.parse(value)
  rescue JSON::ParserError
    key == :content_attributes ? {} : value
  end

  def canonicalize(value)
    return canonical_uploaded_file(value) if uploaded_file?(value)
    return canonicalize_hash(value.to_unsafe_h) if value.is_a?(ActionController::Parameters)

    case value
    when Hash
      canonicalize_hash(value)
    when Array
      value.map { |item| canonicalize(item) }
    else
      value
    end
  end

  def canonicalize_hash(value)
    value.to_h.transform_keys(&:to_s).sort.to_h.transform_values { |item| canonicalize(item) }
  end

  def uploaded_file?(value)
    value.respond_to?(:original_filename) && value.respond_to?(:content_type) && value.respond_to?(:tempfile)
  end

  def canonical_uploaded_file(upload)
    tempfile = upload.respond_to?(:tempfile) ? upload.tempfile : nil
    {
      filename: upload.original_filename,
      content_type: upload.content_type,
      size: tempfile&.size,
      sha256: tempfile&.path.present? ? Digest::SHA256.file(tempfile.path).hexdigest : nil
    }
  end
end
