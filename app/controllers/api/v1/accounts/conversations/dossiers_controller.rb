# Chatwit: dossier export of selected messages (see chatwitdocs/baixar-dossie.md)
class Api::V1::Accounts::Conversations::DossiersController < Api::V1::Accounts::Conversations::BaseController
  MAX_MESSAGES = 2000

  def show
    payload = Conversations::DossierStatus.read(Current.account.id, @conversation.display_id, permitted_params[:id])
    return render json: { error: 'not found' }, status: :not_found if payload.blank?

    render json: payload.merge(id: permitted_params[:id])
  end

  def create
    message_ids = @conversation.messages.where(id: permitted_params[:message_ids]).limit(MAX_MESSAGES).pluck(:id)
    return render json: { error: I18n.t('errors.dossier.no_messages') }, status: :unprocessable_entity if message_ids.blank?

    dossier_id = SecureRandom.uuid
    Conversations::DossierStatus.write(Current.account.id, @conversation.display_id, dossier_id, status: 'pending')
    Conversations::DossierExportJob.perform_later(@conversation.id, message_ids, dossier_id)

    render json: { id: dossier_id, status: 'pending' }
  end

  private

  def permitted_params
    params.permit(:id, :account_id, :conversation_id, message_ids: [])
  end
end
