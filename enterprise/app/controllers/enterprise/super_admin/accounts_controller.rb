module Enterprise::SuperAdmin::AccountsController
  def create
    manually_managed = params[:account]&.delete(:manually_managed_features)

    super do |resource|
      if manually_managed.present?
        service = ::Internal::Accounts::InternalAttributesService.new(resource)
        service.manually_managed_features = manually_managed
      end
    end
  end

  def update
    # Handle manually managed features from form submission
    if params[:account] && params[:account][:manually_managed_features].present?
      # Update using the service - it will handle array conversion and validation
      service = ::Internal::Accounts::InternalAttributesService.new(requested_resource)
      service.manually_managed_features = params[:account][:manually_managed_features]

      # Remove the manually_managed_features from params to prevent ActiveModel::UnknownAttributeError
      params[:account].delete(:manually_managed_features)
    end

    super
  end

  def toggle_captain_payment_phase2
    enabled = ::Internal::Accounts::InternalAttributesService.new(requested_resource).toggle_captain_payment_phase2!
    notice = enabled ? 'Captain Payment Phase 2 enabled' : 'Captain Payment Phase 2 disabled'
    redirect_back(fallback_location: [namespace, requested_resource], notice: notice)
  end
end
