require 'rails_helper'

RSpec.describe Captain::PaymentReview::LabelMutationService do
  subject(:service) do
    described_class.new(
      conversation: conversation,
      labels: requested_labels,
      source: source,
      payment_context: payment_context
    )
  end

  let(:account) { create(:account, custom_attributes: { plan_name: 'startups' }) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:canonical_label) { 'captain_revisar_pagamento' }
  let(:requested_labels) { [canonical_label] }
  let(:source) { :platform_bot }
  let(:payment_context) { { id: 'ctx_1', version: 4 } }

  def with_phase2_enabled(&)
    create(:captain_inbox, inbox: inbox, captain_assistant: assistant, mode: :phase2_only) unless inbox.captain_inbox
    inbox.reload

    with_modified_env(
      { CAPTAIN_PAYMENT_PHASE2_ENABLED: 'true', CAPTAIN_PAYMENT_PHASE2_INBOX_IDS: inbox.id.to_s },
      &
    )
  end

  def on_fresh_connection(&)
    Thread.new { ActiveRecord::Base.connection_pool.with_connection(&) }.value
  end

  def create_committed_race_fixture
    on_fresh_connection do
      race_account = FactoryBot.create(:account, custom_attributes: { plan_name: 'startups' })
      race_inbox = FactoryBot.create(:inbox, account: race_account)
      race_conversation = FactoryBot.create(:conversation, account: race_account, inbox: race_inbox)
      race_assistant = FactoryBot.create(:captain_assistant, account: race_account)
      FactoryBot.create(:captain_inbox, inbox: race_inbox, captain_assistant: race_assistant, mode: :phase2_only)

      { account_id: race_account.id, inbox_id: race_inbox.id, conversation_id: race_conversation.id }
    end
  end

  def destroy_committed_race_fixture(fixture)
    on_fresh_connection do
      Conversation.find_by(id: fixture[:conversation_id])&.destroy!
      Account.find_by(id: fixture[:account_id])&.destroy!
    end
  end

  describe '#add!' do
    it 'preserves unrelated labels and persists the eligible edge in the same mutation' do
      conversation.update!(label_list: ['existing_label'])
      watermark = create(:message, conversation: conversation)

      result = with_phase2_enabled { service.add! }
      trigger = Captain::PaymentReviewTrigger.find_by!(conversation: conversation)

      expect(result.added).to contain_exactly(canonical_label)
      expect(result.labels).to contain_exactly('existing_label', canonical_label)
      expect(trigger).to have_attributes(
        account_id: account.id,
        generation: 1,
        state: 'eligible',
        source: 'platform_bot',
        trigger_label: canonical_label,
        trigger_message_id: watermark.id,
        payment_context_id: 'ctx_1',
        payment_context_version: 4,
        deactivated_at: nil
      )
      expect(conversation.reload.label_list).to contain_exactly('existing_label', canonical_label)
    end

    it 'is a no-op while the canonical label is already present' do
      first_result = with_phase2_enabled { service.add! }
      second_result = with_phase2_enabled { service.add! }

      expect(first_result.added).to contain_exactly(canonical_label)
      expect(second_result.added).to be_empty
      expect(Captain::PaymentReviewTrigger.where(conversation: conversation).count).to eq(1)
    end

    it 'keeps an already-applied canonical retry idempotent after rollout is disabled' do
      with_phase2_enabled { service.add! }

      with_modified_env CAPTAIN_PAYMENT_PHASE2_ENABLED: 'false', CAPTAIN_PAYMENT_PHASE2_INBOX_IDS: inbox.id.to_s do
        expect(service.add!.added).to be_empty
      end

      expect(Captain::PaymentReviewTrigger.where(conversation: conversation).count).to eq(1)
    end

    it 'serializes stale callers into one generation' do
      first_service = described_class.new(conversation: conversation.class.find(conversation.id), labels: requested_labels, source: source)
      second_service = described_class.new(conversation: conversation.class.find(conversation.id), labels: requested_labels, source: source)

      results = with_phase2_enabled { [first_service.add!, second_service.add!] }

      expect(results.sum { |result| result.added.count(canonical_label) }).to eq(1)
      expect(Captain::PaymentReviewTrigger.where(conversation: conversation).count).to eq(1)
    end

    it 'rejects automated canonical edges when the kill switch is disabled' do
      with_modified_env CAPTAIN_PAYMENT_PHASE2_ENABLED: 'false', CAPTAIN_PAYMENT_PHASE2_INBOX_IDS: inbox.id.to_s do
        expect { service.add! }.to raise_error(described_class::Phase2DisabledError)
      end

      expect(conversation.reload.label_list).not_to include(canonical_label)
      expect(Captain::PaymentReviewTrigger.where(conversation: conversation)).to be_empty
    end

    it 'keeps a disabled manual edge visual and permanently ineligible' do
      manual_service = described_class.new(conversation: conversation, labels: requested_labels, source: :manual)

      with_modified_env CAPTAIN_PAYMENT_PHASE2_ENABLED: 'false', CAPTAIN_PAYMENT_PHASE2_INBOX_IDS: inbox.id.to_s do
        manual_service.add!
      end
      with_phase2_enabled { manual_service.add! }

      trigger = Captain::PaymentReviewTrigger.find_by!(conversation: conversation)
      expect(trigger).to be_ineligible
      expect(Captain::PaymentReviewTrigger.where(conversation: conversation).count).to eq(1)
    end

    it 'rejects incomplete payment correlation' do
      expect do
        described_class.new(
          conversation: conversation,
          labels: requested_labels,
          source: :platform_bot,
          payment_context: { id: 'ctx_1', version: 0 }
        ).add!
      end.to raise_error(described_class::InvalidPaymentContextError)
    end

    it 'rolls back the durable edge when the label update fails' do
      locked_conversation = conversation.class.find(conversation.id)
      allow(conversation.class).to receive(:find).with(conversation.id).and_return(locked_conversation)
      allow(locked_conversation).to receive(:update!).and_raise(ActiveRecord::RecordInvalid.new(locked_conversation))

      expect { with_phase2_enabled { service.add! } }.to raise_error(ActiveRecord::RecordInvalid)

      expect(conversation.reload.label_list).not_to include(canonical_label)
      expect(Captain::PaymentReviewTrigger.where(conversation: conversation)).to be_empty
    end
  end

  describe '#remove! and manual rearm' do
    it 'cancels generation one and creates generation two only after re-add' do
      with_phase2_enabled { service.add! }
      remove_service = described_class.new(conversation: conversation, labels: requested_labels, source: :manual)
      remove_service.remove!
      second_result = with_phase2_enabled { service.add! }

      triggers = Captain::PaymentReviewTrigger.where(conversation: conversation).order(:generation)
      expect(triggers.first).to be_cancelled
      expect(triggers.first.deactivated_at).to be_present
      expect(triggers.second).to be_eligible
      expect(triggers.second.deactivated_at).to be_nil
      expect(second_result.trigger.generation).to eq(2)
      expect(triggers.where(deactivated_at: nil).count).to eq(1)
    end

    it 'removes only requested labels from a stale conversation instance' do
      conversation.update!(label_list: %w[captain_revisar_pagamento keep_me remove_me])
      stale_conversation = conversation.class.find(conversation.id)
      conversation.add_labels('added_later')

      described_class.new(conversation: stale_conversation, labels: ['remove_me'], source: :manual).remove!

      expect(conversation.reload.label_list).to contain_exactly(canonical_label, 'keep_me', 'added_later')
    end
  end

  describe '#replace!' do
    it 'keeps the native comma-separated string semantics' do
      replacement = described_class.new(conversation: conversation, labels: 'first_label, second_label', source: :manual)

      replacement.replace!

      expect(conversation.reload.label_list).to contain_exactly('first_label', 'second_label')
    end

    it 'materializes a canonical edge parsed from native comma-separated input' do
      replacement = described_class.new(
        conversation: conversation,
        labels: "keep_me, #{canonical_label}",
        source: :manual
      )

      with_phase2_enabled { replacement.replace! }

      expect(conversation.reload.label_list).to contain_exactly('keep_me', canonical_label)
      expect(Captain::PaymentReviewTrigger.find_by!(conversation: conversation)).to be_eligible
    end

    it 'preserves native replacement semantics while materializing both edges' do
      conversation.update!(label_list: ['old_label'])
      replacement = described_class.new(conversation: conversation, labels: [canonical_label], source: :manual)

      with_phase2_enabled { replacement.replace! }
      expect(conversation.reload.label_list).to contain_exactly(canonical_label)

      described_class.new(conversation: conversation, labels: ['new_label'], source: :manual).replace!
      expect(conversation.reload.label_list).to contain_exactly('new_label')
      expect(Captain::PaymentReviewTrigger.find_by!(conversation: conversation)).to be_cancelled
    end
  end

  context 'when two committed callers race' do
    it 'creates exactly one generation for concurrent canonical adds' do
      fixture = create_committed_race_fixture
      barrier = Concurrent::CyclicBarrier.new(2)
      results = Concurrent::Array.new
      errors = Concurrent::Array.new

      with_modified_env(
        CAPTAIN_PAYMENT_PHASE2_ENABLED: 'true',
        CAPTAIN_PAYMENT_PHASE2_INBOX_IDS: fixture[:inbox_id].to_s
      ) do
        threads = Array.new(2) do
          Thread.new do
            ActiveRecord::Base.connection_pool.with_connection do
              raced_conversation = Conversation.find(fixture[:conversation_id])
              raced_service = described_class.new(
                conversation: raced_conversation,
                labels: ['captain_revisar_pagamento'],
                source: :platform_bot
              )
              barrier.wait
              results << raced_service.add!
            rescue StandardError => e
              errors << e
            end
          end
        end
        threads.each(&:join)
      end

      expect(errors).to be_empty
      expect(results.sum { |result| result.added.count('captain_revisar_pagamento') }).to eq(1)
      expect(Captain::PaymentReviewTrigger.where(conversation_id: fixture[:conversation_id]).count).to eq(1)
    ensure
      destroy_committed_race_fixture(fixture) if fixture
    end

    it 'serializes a Platform add with native replacement without losing either mutation' do
      fixture = create_committed_race_fixture
      barrier = Concurrent::CyclicBarrier.new(2)
      errors = Concurrent::Array.new
      platform_add = lambda do
        described_class.new(
          conversation: Conversation.find(fixture[:conversation_id]), labels: [canonical_label], source: :platform_bot
        ).add!
      end
      native_replace = lambda do
        described_class.new(
          conversation: Conversation.find(fixture[:conversation_id]), labels: ['replacement_label'], source: :manual
        ).replace!
      end

      with_modified_env(
        CAPTAIN_PAYMENT_PHASE2_ENABLED: 'true',
        CAPTAIN_PAYMENT_PHASE2_INBOX_IDS: fixture[:inbox_id].to_s
      ) do
        threads = [platform_add, native_replace].map do |operation|
          Thread.new do
            ActiveRecord::Base.connection_pool.with_connection do
              barrier.wait
              operation.call
            rescue StandardError => e
              errors << e
            end
          end
        end
        threads.each(&:join)
      end

      final_labels = Conversation.find(fixture[:conversation_id]).label_list.to_a
      trigger = Captain::PaymentReviewTrigger.find_by!(conversation_id: fixture[:conversation_id])

      expect(errors).to be_empty
      expect(final_labels).to include('replacement_label')
      expect(trigger.deactivated_at.nil?).to eq(final_labels.include?(canonical_label))
    ensure
      destroy_committed_race_fixture(fixture) if fixture
    end
  end
end
