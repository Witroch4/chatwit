# frozen_string_literal: true

class Api::V1::Accounts::WhatsappInteractiveTemplatesController < Api::V1::Accounts::BaseController
  EDITABLE_ATTRIBUTES = %w[
    name template_type header_type header_text header_image_url
    body_text footer_text button_text url_placeholder static_url quick_replies
  ].freeze

  before_action :check_authorization
  before_action :fetch_template, only: [:update, :destroy, :dispatch_to_conversation]

  rescue_from Whatsapp::InteractiveTemplatePayloadBuilder::ValidationError, with: :render_payload_error

  def index
    @templates = Current.account.whatsapp_interactive_templates.order(created_at: :desc)
    render json: @templates
  end

  def create
    @template = Current.account.whatsapp_interactive_templates.create!(
      permitted_params.merge(payload: build_payload(permitted_params.to_h))
    )

    render json: @template, status: :created
  end

  def update
    # Partial PATCH: rebuild the payload from the persisted attributes merged
    # with the incoming params, so unsent fields keep their current values.
    merged_attributes = @template.attributes.slice(*EDITABLE_ATTRIBUTES)
                                 .with_indifferent_access
                                 .merge(permitted_params.to_h)

    @template.update!(permitted_params.merge(payload: build_payload(merged_attributes)))

    render json: @template
  end

  def destroy
    @template.destroy!
    head :ok
  end

  def publish_header
    blob = ActiveStorage::Blob.find_signed(params[:blob_id].to_s)
    file_url = Whatsapp::InteractiveHeaderPublisherService.new(blob: blob).perform

    render json: { file_url: file_url }
  rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
    render json: { error: 'Invalid blob id' }, status: :unprocessable_entity
  rescue Whatsapp::InteractiveHeaderPublisherService::PublishError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def dispatch_to_conversation
    conversation = find_conversation
    return render json: { error: 'Conversation not found' }, status: :not_found if conversation.blank?

    @message = Whatsapp::InteractiveTemplateDispatchService.new(
      template: @template,
      conversation: conversation,
      user: Current.user,
      runtime_url: params[:runtime_url].presence,
      runtime_body_text: params[:runtime_body_text].presence
    ).perform

    render json: @message, status: :created
  rescue Whatsapp::InteractiveTemplateDispatchService::DispatchError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def build_payload(attributes)
    Whatsapp::InteractiveTemplatePayloadBuilder.new(template_attributes: attributes).build_template_payload
  end

  def render_payload_error(exception)
    render json: { error: exception.message }, status: :unprocessable_entity
  end

  def find_conversation
    scope = Current.account.conversations
    conversation_id = params[:conversation_id]
    scope.find_by(display_id: conversation_id) || scope.find_by(id: conversation_id)
  end

  def fetch_template
    @template = Current.account.whatsapp_interactive_templates.find(params[:id])
  end

  def permitted_params
    params.require(:whatsapp_interactive_template).permit(
      :name,
      :template_type,
      :header_type,
      :header_text,
      :header_image_url,
      :body_text,
      :footer_text,
      :button_text,
      :url_placeholder,
      :static_url,
      quick_replies: [:id, :text]
    )
  end
end
