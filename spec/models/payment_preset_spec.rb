require 'rails_helper'

RSpec.describe PaymentPreset do
  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:whatsapp_interactive_template).optional }
  end
end
