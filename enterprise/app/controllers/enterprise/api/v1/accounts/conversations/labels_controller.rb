module Enterprise::Api::V1::Accounts::Conversations::LabelsController
  def add
    return render_unauthorized('Only the Chatwit Platform Bot may add labels') unless platform_bot_request?

    requested_labels = normalized_requested_labels
    return render_invalid_labels('labels must contain at least one label') if requested_labels.empty?

    missing_labels = requested_labels - Current.account.labels.where(title: requested_labels).pluck(:title)
    return render_invalid_labels("Unknown account labels: #{missing_labels.join(', ')}") if missing_labels.present?

    result = Captain::PaymentReview::LabelMutationService.new(
      conversation: @conversation,
      labels: requested_labels,
      source: :platform_bot,
      payment_context: permitted_params[:payment_context].presence
    ).add!
    @labels = result.labels
    render :create
  rescue Captain::PaymentReview::LabelMutationService::Phase2DisabledError => e
    render json: { error: e.message, code: 'phase2_disabled' }, status: :conflict
  rescue Captain::PaymentReview::LabelMutationService::InvalidPaymentContextError => e
    render_invalid_labels(e.message)
  end

  private

  def platform_bot_request?
    @resource.is_a?(AgentBot) && @resource == Chatwit::PlatformBot.bot
  end

  def normalized_requested_labels
    Array(permitted_params[:labels]).map(&:to_s).map(&:strip).reject(&:blank?).uniq
  end

  def render_invalid_labels(message)
    render json: { error: message }, status: :unprocessable_entity
  end
end
