class Api::V1::Accounts::StickersController < Api::V1::Accounts::BaseController
  include Rails.application.routes.url_helpers

  before_action :fetch_sticker, only: [:show, :destroy, :send_sticker]

  def index
    authorize Sticker
    stickers = if ActiveModel::Type::Boolean.new.cast(params[:recent])
                 Sticker.recent_for(Current.account, Current.user)
               else
                 Current.account.stickers.order(created_at: :desc)
               end
    render json: stickers.map { |sticker| serialize(sticker) }
  end

  def show
    authorize @sticker
    render json: serialize(@sticker)
  end

  def create
    authorize Sticker
    render json: serialize(create_sticker)
  rescue Stickers::ConverterService::InvalidSource => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def destroy
    authorize @sticker
    @sticker.destroy!
    head :ok
  end

  def send_sticker
    authorize @sticker, :send_sticker?
    unless @sticker.ready?
      return render json: { error: I18n.t('errors.stickers.processing', default: 'Sticker is still processing') },
                    status: :unprocessable_entity
    end

    conversation = Current.account.conversations.find_by!(display_id: params[:conversation_id])
    message = Messages::MessageBuilder.new(
      Current.user, conversation,
      { message_type: 'outgoing', content_type: 'sticker', attachments: [@sticker.file.blob.signed_id] }
    ).perform
    Sticker.touch_recent(Current.user, @sticker.id)
    render json: { id: message.id }
  end

  private

  def fetch_sticker
    @sticker = Current.account.stickers.find(params[:id])
  end

  # Already-compliant stickers convert instantly (header-only passthrough) and return
  # :ready. Anything needing a real re-encode is stored as-is and converted in the
  # background so the request returns immediately (optimistic flow).
  def create_sticker
    bytes, filename, content_type = sticker_source_bytes
    converter = Stickers::ConverterService.new(account: Current.account, user: Current.user, bytes: bytes)
    return converter.perform if converter.compliant?

    enqueue_sticker_conversion(bytes, filename, content_type)
  end

  def enqueue_sticker_conversion(bytes, filename, content_type)
    sticker = Current.account.stickers.create!(user: Current.user, status: :processing)
    sticker.file.attach(io: StringIO.new(bytes), filename: filename, content_type: content_type)
    Stickers::ConvertJob.perform_later(sticker.id)
    sticker
  end

  def sticker_source_bytes
    if params[:source_attachment_id].present?
      attachment = Attachment.joins(:message)
                             .where(messages: { account_id: Current.account.id })
                             .find_by(id: params[:source_attachment_id])
      raise Stickers::ConverterService::InvalidSource, 'attachment not found' if attachment.blank?

      blob = attachment.file.blob
      [blob.open(&:read), blob.filename.to_s, blob.content_type]
    else
      file = params[:file]
      raise Stickers::ConverterService::InvalidSource, 'file required' if file.blank?

      [file.read, file.original_filename, file.content_type]
    end
  end

  def serialize(sticker)
    { id: sticker.id, animated: sticker.animated, status: sticker.status, url: sticker_url(sticker) }
  end

  def sticker_url(sticker)
    return nil unless sticker.file.attached?

    url_for(sticker.file)
  end
end
