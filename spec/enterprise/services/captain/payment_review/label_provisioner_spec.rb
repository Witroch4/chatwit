require 'rails_helper'

RSpec.describe Captain::PaymentReview::LabelProvisioner do
  let!(:account) { create(:account) }
  let(:canonical_label) { 'captain_revisar_pagamento' }

  describe '.provision!' do
    it 'creates the canonical FlowBuilder label with stable metadata' do
      described_class.provision!(account)

      expect(account.labels.find_by!(title: canonical_label)).to have_attributes(
        color: described_class::LABEL_COLOR,
        description: 'Captain fase 2: revisar pagamento uma vez; remova e reaplique para novo ciclo',
        show_on_sidebar: true
      )
    end

    it 'is idempotent and preserves an existing administrator customization' do
      label = create(:label, account: account, title: canonical_label, color: '#123456', description: 'custom')

      2.times { described_class.provision!(account) }

      expect(account.labels.where(title: canonical_label).count).to eq(1)
      expect(label.reload).to have_attributes(color: '#123456', description: 'custom')
    end
  end

  describe '.provision_all!' do
    it 'provisions existing accounts independently of runtime rollout flags' do
      second_account = create(:account)

      with_modified_env CAPTAIN_PAYMENT_PHASE2_ENABLED: 'false', CAPTAIN_PAYMENT_PHASE2_INBOX_IDS: '' do
        described_class.provision_all!
      end

      expect(account.labels).to exist(title: canonical_label)
      expect(second_account.labels).to exist(title: canonical_label)
    end

    it 'does not abort application boot when the database is unavailable' do
      allow(ActiveRecord::Base.connection).to receive(:table_exists?).and_raise(ActiveRecord::ConnectionNotEstablished)

      expect(Rails.logger).to receive(:warn).with(/Skipped label provisioning/)
      expect { described_class.provision_all! }.not_to raise_error
    end
  end
end
