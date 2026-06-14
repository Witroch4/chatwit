class Api::V1::Accounts::StickersController < Api::V1::Accounts::BaseController
  include Rails.application.routes.url_helpers

  before_action :fetch_sticker, only: [:destroy, :send_sticker]

  def index
    authorize Sticker
    stickers = if ActiveModel::Type::Boolean.new.cast(params[:recent])
                 Sticker.recent_for(Current.account, Current.user)
               else
                 Current.account.stickers.order(created_at: :desc)
               end
    render json: stickers.map { |sticker| serialize(sticker) }
  end

  def create
    authorize Sticker
    sticker = build_sticker
    render json: serialize(sticker)
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

  def build_sticker
    if params[:source_attachment_id].present?
      attachment = Attachment.joins(:message)
                             .where(messages: { account_id: Current.account.id })
                             .find_by(id: params[:source_attachment_id])
      raise Stickers::ConverterService::InvalidSource, 'attachment not found' if attachment.blank?

      Stickers::ConverterService.new(account: Current.account, user: Current.user, blob: attachment.file.blob).perform
    else
      Stickers::ConverterService.new(account: Current.account, user: Current.user, file: params[:file]).perform
    end
  end

  def serialize(sticker)
    { id: sticker.id, animated: sticker.animated, url: sticker_url(sticker) }
  end

  def sticker_url(sticker)
    return nil unless sticker.file.attached?

    url_for(sticker.file)
  end
end
