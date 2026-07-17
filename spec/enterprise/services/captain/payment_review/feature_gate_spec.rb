require 'rails_helper'

RSpec.describe Captain::PaymentReview::FeatureGate do
  subject(:gate) { described_class.new(conversation) }

  let(:account) { create(:account, custom_attributes: { plan_name: 'startups' }) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

  it 'fails closed when the kill switch is absent' do
    with_modified_env CAPTAIN_PAYMENT_PHASE2_ENABLED: nil, CAPTAIN_PAYMENT_PHASE2_INBOX_IDS: inbox.id.to_s do
      expect(gate).not_to be_eligible
      expect(gate.reason).to eq(:kill_switch_disabled)
    end
  end

  it 'requires the exact inbox in the allowlist' do
    with_modified_env CAPTAIN_PAYMENT_PHASE2_ENABLED: 'true', CAPTAIN_PAYMENT_PHASE2_INBOX_IDS: (inbox.id + 1).to_s do
      expect(gate).not_to be_eligible
      expect(gate.reason).to eq(:inbox_not_allowlisted)
    end
  end

  it 'requires phase2_only mode and an assistant from the same tenant' do
    assistant = create(:captain_assistant, account: account)
    captain_inbox = create(:captain_inbox, inbox: inbox, captain_assistant: assistant, mode: :continuous)

    with_modified_env CAPTAIN_PAYMENT_PHASE2_ENABLED: 'true', CAPTAIN_PAYMENT_PHASE2_INBOX_IDS: inbox.id.to_s do
      expect(gate.reason).to eq(:phase2_mode_disabled)

      captain_inbox.update!(mode: :phase2_only)
      captain_inbox.update!(captain_assistant: create(:captain_assistant))
      inbox.reload

      expect(described_class.new(conversation.reload).reason).to eq(:assistant_tenant_mismatch)
    end
  end

  it 'captures quota exhaustion instead of treating the edge as eligible' do
    assistant = create(:captain_assistant, account: account)
    create(:captain_inbox, inbox: inbox, captain_assistant: assistant, mode: :phase2_only)
    account.update!(
      limits: account.limits.merge('captain_responses' => 1),
      custom_attributes: account.custom_attributes.merge('captain_responses_usage' => 1)
    )

    with_modified_env CAPTAIN_PAYMENT_PHASE2_ENABLED: 'true', CAPTAIN_PAYMENT_PHASE2_INBOX_IDS: inbox.id.to_s do
      expect(described_class.new(conversation.reload).reason).to eq(:quota_exhausted)
    end
  end

  it 'is eligible only when switch, inbox, mode, tenant, assistant and quota are valid' do
    assistant = create(:captain_assistant, account: account)
    create(:captain_inbox, inbox: inbox, captain_assistant: assistant, mode: :phase2_only)

    with_modified_env CAPTAIN_PAYMENT_PHASE2_ENABLED: 'true', CAPTAIN_PAYMENT_PHASE2_INBOX_IDS: "  #{inbox.id},999 " do
      expect(described_class.new(conversation.reload)).to be_eligible
    end
  end

  it 'fails closed when both the ENV switch and the account internal attribute are disabled' do
    assistant = create(:captain_assistant, account: account)
    create(:captain_inbox, inbox: inbox, captain_assistant: assistant, mode: :phase2_only)

    with_modified_env CAPTAIN_PAYMENT_PHASE2_ENABLED: nil, CAPTAIN_PAYMENT_PHASE2_INBOX_IDS: nil do
      gate = described_class.new(conversation.reload)
      expect(gate).not_to be_eligible
      expect(gate.reason).to eq(:kill_switch_disabled)
    end
  end

  context 'when activation comes from the account internal attribute' do
    before do
      account.update!(internal_attributes: account.internal_attributes.merge('captain_payment_phase2' => true))
    end

    it 'is eligible without any ENV when the phase2_only inbox is valid' do
      assistant = create(:captain_assistant, account: account)
      create(:captain_inbox, inbox: inbox, captain_assistant: assistant, mode: :phase2_only)

      with_modified_env CAPTAIN_PAYMENT_PHASE2_ENABLED: nil, CAPTAIN_PAYMENT_PHASE2_INBOX_IDS: nil do
        expect(described_class.new(conversation.reload)).to be_eligible
      end
    end

    it 'keeps blocking when a non-empty ENV allowlist excludes the inbox' do
      assistant = create(:captain_assistant, account: account)
      create(:captain_inbox, inbox: inbox, captain_assistant: assistant, mode: :phase2_only)

      with_modified_env CAPTAIN_PAYMENT_PHASE2_ENABLED: nil, CAPTAIN_PAYMENT_PHASE2_INBOX_IDS: (inbox.id + 1).to_s do
        gate = described_class.new(conversation.reload)
        expect(gate).not_to be_eligible
        expect(gate.reason).to eq(:inbox_not_allowlisted)
      end
    end
  end

  it 'treats junk jsonb values in the internal attribute as disabled' do
    assistant = create(:captain_assistant, account: account)
    create(:captain_inbox, inbox: inbox, captain_assistant: assistant, mode: :phase2_only)
    account.update!(internal_attributes: account.internal_attributes.merge('captain_payment_phase2' => 'sim, por favor'))

    with_modified_env CAPTAIN_PAYMENT_PHASE2_ENABLED: nil, CAPTAIN_PAYMENT_PHASE2_INBOX_IDS: nil do
      gate = described_class.new(conversation.reload)
      expect(gate).not_to be_eligible
      expect(gate.reason).to eq(:kill_switch_disabled)
    end
  end

  it 'keeps one immutable eligibility snapshot for the edge mutation' do
    assistant = create(:captain_assistant, account: account)
    create(:captain_inbox, inbox: inbox, captain_assistant: assistant, mode: :phase2_only)

    with_modified_env CAPTAIN_PAYMENT_PHASE2_ENABLED: 'true', CAPTAIN_PAYMENT_PHASE2_INBOX_IDS: inbox.id.to_s do
      expect(gate).to be_eligible
    end

    with_modified_env CAPTAIN_PAYMENT_PHASE2_ENABLED: 'false', CAPTAIN_PAYMENT_PHASE2_INBOX_IDS: inbox.id.to_s do
      expect(gate).to be_eligible
      expect(gate.reason).to eq(:eligible)
    end
  end
end
