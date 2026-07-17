class Api::V1::Accounts::Captain::InboxesController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action -> { check_authorization(Captain::Assistant) }

  before_action :set_assistant
  def index
    @captain_inboxes = @assistant.captain_inboxes.includes(:inbox)
  end

  def create
    inbox = Current.account.inboxes.find(assistant_params[:inbox_id])
    @captain_inbox = @assistant.captain_inboxes.build(captain_inbox_attributes(inbox))
    @captain_inbox.save!
  end

  def destroy
    @captain_inbox = @assistant.captain_inboxes.find_by!(inbox_id: permitted_params[:inbox_id])
    @captain_inbox.destroy!
    head :no_content
  end

  private

  def set_assistant
    @assistant = account_assistants.find(permitted_params[:assistant_id])
  end

  def account_assistants
    @account_assistants ||= Current.account.captain_assistants
  end

  def permitted_params
    params.permit(:assistant_id, :id, :account_id, :inbox_id)
  end

  def captain_inbox_attributes(inbox)
    attributes = { inbox: inbox }
    attributes[:mode] = assistant_params[:mode] if assistant_params[:mode].present?
    %i[phase2_model phase2_prompt phase2_payment_preset_ids].each do |key|
      attributes[key] = assistant_params[key] if assistant_params.key?(key)
    end
    attributes
  end

  def assistant_params
    params.require(:inbox).permit(:inbox_id, :mode, :phase2_model, :phase2_prompt, phase2_payment_preset_ids: [])
  end
end
