require 'rails_helper'

RSpec.describe CaptainInbox do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:inbox) { create(:inbox, account: account) }

  it 'defaults to continuous mode' do
    captain_inbox = described_class.create!(captain_assistant: assistant, inbox: inbox)

    expect(captain_inbox).to be_continuous
  end

  it 'supports the phase2_only mode' do
    captain_inbox = create(:captain_inbox, captain_assistant: assistant, inbox: inbox, mode: :phase2_only)

    expect(captain_inbox).to be_phase2_only
  end

  it 'allows only one captain association per inbox' do
    create(:captain_inbox, captain_assistant: assistant, inbox: inbox)
    other_assistant = create(:captain_assistant, account: account)

    duplicate = build(:captain_inbox, captain_assistant: other_assistant, inbox: inbox)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:inbox_id]).to be_present
  end

  describe 'phase2 settings' do
    let(:preset) { create(:payment_preset, account: account) }

    it 'accepts payment preset ids that belong to the account' do
      captain_inbox = build(:captain_inbox, captain_assistant: assistant, inbox: inbox, mode: :phase2_only,
                                            phase2_payment_preset_ids: [preset.id])

      expect(captain_inbox).to be_valid
    end

    it 'coerces integer-like string ids submitted through form params' do
      captain_inbox = create(:captain_inbox, captain_assistant: assistant, inbox: inbox, mode: :phase2_only,
                                             phase2_payment_preset_ids: [preset.id.to_s])

      expect(captain_inbox.phase2_payment_preset_ids).to eq([preset.id])
    end

    it 'rejects payment preset ids from another account' do
      foreign = create(:payment_preset, account: create(:account))
      captain_inbox = build(:captain_inbox, captain_assistant: assistant, inbox: inbox, mode: :phase2_only,
                                            phase2_payment_preset_ids: [foreign.id])

      expect(captain_inbox).not_to be_valid
      expect(captain_inbox.errors[:phase2_payment_preset_ids]).to be_present
    end

    it 'rejects non-integer preset ids' do
      captain_inbox = build(:captain_inbox, captain_assistant: assistant, inbox: inbox, mode: :phase2_only,
                                            phase2_payment_preset_ids: ['abc'])

      expect(captain_inbox).not_to be_valid
      expect(captain_inbox.errors[:phase2_payment_preset_ids]).to be_present
    end

    it 'normalizes phase2 fields to blank for continuous mode' do
      captain_inbox = create(:captain_inbox, captain_assistant: assistant, inbox: inbox, mode: :continuous,
                                             phase2_model: 'witdev_claude/sonnet', phase2_prompt: 'x',
                                             phase2_payment_preset_ids: [preset.id])

      expect(captain_inbox.phase2_model).to be_nil
      expect(captain_inbox.phase2_prompt).to be_nil
      expect(captain_inbox.phase2_payment_preset_ids).to eq([])
    end

    it 'falls back to the default prompt when phase2_prompt is blank' do
      captain_inbox = build(:captain_inbox, captain_assistant: assistant, inbox: inbox, mode: :phase2_only)

      expect(captain_inbox.phase2_prompt_or_default).to eq(Captain::PaymentReview::DEFAULT_PROMPT)
    end

    it 'uses the operator prompt when present' do
      captain_inbox = build(:captain_inbox, captain_assistant: assistant, inbox: inbox, mode: :phase2_only,
                                            phase2_prompt: 'Revise com carinho')

      expect(captain_inbox.phase2_prompt_or_default).to eq('Revise com carinho')
    end
  end
end
