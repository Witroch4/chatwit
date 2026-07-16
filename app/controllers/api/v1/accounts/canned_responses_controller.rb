class Api::V1::Accounts::CannedResponsesController < Api::V1::Accounts::BaseController
  before_action :fetch_canned_response, only: [:update, :destroy]

  def index
    render json: canned_responses
  end

  def create
    @canned_response = Current.account.canned_responses.new(canned_response_params)
    @canned_response.save!
    render json: @canned_response
  end

  def update
    @canned_response.update!(canned_response_params)
    render json: @canned_response
  end

  def destroy
    @canned_response.destroy!
    head :ok
  end

  def reorder
    ordered_ids = reorder_params[:canned_response_ids]
    account_ids = Current.account.canned_responses.pluck(:id)

    return render json: { error: 'Invalid canned response order' }, status: :unprocessable_entity unless valid_reorder?(ordered_ids, account_ids)

    CannedResponse.transaction do
      ordered_ids.each_with_index do |id, index|
        Current.account.canned_responses.find(id).update!(position: index + 1)
      end
    end

    render json: canned_responses
  end

  private

  def fetch_canned_response
    @canned_response = Current.account.canned_responses.find(params[:id])
  end

  def canned_response_params
    params.require(:canned_response).permit(:short_code, :content)
  end

  def reorder_params
    params.permit(canned_response_ids: [])
  end

  def valid_reorder?(ordered_ids, account_ids)
    return false unless ordered_ids.is_a?(Array) && ordered_ids.all?(Integer)

    ordered_ids.size == account_ids.size &&
      ordered_ids.uniq.size == ordered_ids.size &&
      ordered_ids.sort == account_ids.sort
  end

  def canned_responses
    if params[:search]
      Current.account.canned_responses
             .where('short_code ILIKE :search OR content ILIKE :search', search: "%#{params[:search]}%")
             .order_by_search(params[:search])
             .order(:position, :id)

    else
      Current.account.canned_responses.ordered
    end
  end
end
