class Captain::PaymentReview::LabelProvisioner
  LABEL_COLOR = '#7c3aed'.freeze
  LABEL_DESCRIPTION = 'Captain fase 2: revisar pagamento uma vez; remova e reaplique para novo ciclo'.freeze

  class << self
    def provision!(account)
      account.labels.find_or_create_by!(title: Captain::PaymentReviewTrigger::CANONICAL_LABEL) do |label|
        label.color = LABEL_COLOR
        label.description = LABEL_DESCRIPTION
        label.show_on_sidebar = true
      end
    rescue ActiveRecord::RecordNotUnique
      account.labels.find_by!(title: Captain::PaymentReviewTrigger::CANONICAL_LABEL)
    end

    def provision_all!
      return unless required_tables_available?

      Account.find_each { |account| provision_account(account) }
    rescue StandardError => e
      Rails.logger.warn("[CAPTAIN-PAYMENT] Skipped label provisioning: #{e.message}")
    end

    private

    def required_tables_available?
      ActiveRecord::Base.connection.table_exists?('accounts') && ActiveRecord::Base.connection.table_exists?('labels')
    end

    def provision_account(account)
      provision!(account)
    rescue StandardError => e
      Rails.logger.warn("[CAPTAIN-PAYMENT] Failed to provision label for account #{account.id}: #{e.message}")
    end
  end
end
