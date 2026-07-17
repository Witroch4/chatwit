class Api::V1::Accounts::Conversations::LabelsController < Api::V1::Accounts::Conversations::BaseController
  include LabelConcern

  def add
    render_unauthorized('This endpoint is available only in Enterprise')
  end

  private

  def model
    @model ||= @conversation
  end

  def permitted_params
    params.permit(:conversation_id, labels: [], payment_context: %i[id version])
  end
end

Api::V1::Accounts::Conversations::LabelsController.prepend_mod_with('Api::V1::Accounts::Conversations::LabelsController')
