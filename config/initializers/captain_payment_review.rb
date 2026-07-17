Rails.application.config.to_prepare do
  Captain::PaymentReview::LabelProvisioner.provision_all! if ChatwootApp.enterprise?
end
