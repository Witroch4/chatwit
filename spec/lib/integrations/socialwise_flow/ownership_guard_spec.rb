require 'rails_helper'

RSpec.describe 'Integrations::SocialwiseFlow::OwnershipGuard' do
  subject(:guard) { build_guard(conversation) }

  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, status: :open) }
  let(:canonical_label) { Captain::PaymentReviewTrigger::CANONICAL_LABEL }

  def guard_class
    klass = 'Integrations::SocialwiseFlow::OwnershipGuard'.safe_constantize
    expect(klass).not_to be_nil
    klass
  end

  def build_guard(target_conversation)
    guard_class.new(target_conversation)
  end

  def create_trigger(state: :eligible, activated_at: 1.minute.ago)
    attributes = { conversation: conversation, account: account, state: state, activated_at: activated_at }
    attributes[:deactivated_at] = Time.current if state.in?(%i[cancelled consumed])
    create(:captain_payment_review_trigger, **attributes)
  end

  describe '#socialwise_owned?' do
    it 'blocks eligible present triggers for open and pending conversations' do
      create_trigger

      expect(guard.socialwise_owned?).to be(false)

      conversation.update!(status: :pending)
      expect(guard.socialwise_owned?).to be(false)
    end

    it 'does not fence an ineligible trigger' do
      create_trigger(state: :ineligible)

      expect(guard.socialwise_owned?).to be(true)
    end

    it 'does not fence cancelled or consumed triggers' do
      create_trigger(state: :cancelled)
      create_trigger(state: :consumed)

      expect(guard.socialwise_owned?).to be(true)
    end

    it 'blocks an active phase 2 handoff without reevaluating the feature gate' do
      conversation.update!(
        additional_attributes: {
          'socialwise_handoff_at' => Time.current.iso8601,
          'socialwise_handoff_by' => 'captain_payment_phase2'
        }
      )
      allow(Captain::PaymentReview::FeatureGate).to receive(:new).and_raise('feature gate must not be evaluated')

      expect(guard.socialwise_owned?).to be(false)
    end

    it 'reads fresh database state on every check' do
      expect(guard.socialwise_owned?).to be(true)

      create_trigger

      expect(guard.socialwise_owned?).to be(false)
    end

    it 'evaluates the durable handoff and eligible trigger from one locked snapshot' do
      stale_conversation = Conversation.find(conversation.id)
      trigger_created = false

      allow(Conversation).to receive(:find).with(conversation.id).and_return(stale_conversation)
      allow(stale_conversation).to receive(:with_lock) do |&block|
        create_trigger
        trigger_created = true
        stale_conversation.reload
        block.call
      end

      expect(guard.socialwise_owned?).to be(false)
      expect(trigger_created).to be(true)
    end
  end

  describe '#snapshot_epoch and #can_publish?' do
    it 'normalizes absent and invalid epochs to zero' do
      expect(guard.snapshot_epoch).to eq(0)

      ['4', -1, 1.5, [], {}].each do |invalid_epoch|
        conversation.update!(additional_attributes: { 'socialwise_ownership_epoch' => invalid_epoch })
        expect(guard.snapshot_epoch).to eq(0)
      end
    end

    it 'publishes only while the fresh epoch matches and Socialwise still owns the conversation' do
      conversation.update!(additional_attributes: { 'socialwise_ownership_epoch' => 7 })
      epoch = guard.snapshot_epoch

      expect(epoch).to eq(7)
      expect(guard.can_publish?(epoch: epoch)).to be(true)

      conversation.update!(additional_attributes: { 'socialwise_ownership_epoch' => 8 })
      expect(guard.can_publish?(epoch: epoch)).to be(false)
    end

    it 'rejects a snapshot when an eligible trigger or handoff appears without an epoch change' do
      epoch = guard.snapshot_epoch
      trigger = create_trigger

      expect(guard.can_publish?(epoch: epoch)).to be(false)

      trigger.update!(state: :cancelled, deactivated_at: Time.current)
      conversation.update!(additional_attributes: { 'socialwise_handoff_at' => Time.current.iso8601 })
      expect(guard.can_publish?(epoch: epoch)).to be(false)
    end

    it 'rejects an old epoch when resolve releases ownership between find and the locked reload' do
      conversation.update!(
        additional_attributes: {
          'socialwise_handoff_at' => 1.minute.ago.iso8601,
          'socialwise_handoff_by' => 'captain_payment_phase2',
          'socialwise_ownership_epoch' => 0
        }
      )
      stale_conversation = Conversation.find(conversation.id)
      release_guard = build_guard(Conversation.find(conversation.id))
      released = false
      release = lambda do
        next if released

        released = true
        allow(release_guard).to receive(:reload_conversation).and_return(Conversation.unscoped.find(conversation.id))
        release_guard.release_for_resolve!(cutoff: Time.current)
      end
      find_count = 0

      allow(Conversation).to receive(:find).with(conversation.id) do
        find_count += 1
        next stale_conversation if find_count == 1

        release.call
        Conversation.unscoped.find(conversation.id)
      end
      allow(stale_conversation).to receive(:with_lock) do |&block|
        release.call
        stale_conversation.reload
        block.call
      end

      expect(guard.can_publish?(epoch: 0)).to be(false)
      expect(released).to be(true)
      expect(conversation.reload.additional_attributes['socialwise_ownership_epoch']).to eq(1)
    end
  end

  describe '#pause_for_phase2!' do
    it 'persists the durable fence under the conversation lock before clearing only disposable debounce keys' do
      conversation.update!(
        status: :pending,
        waiting_since: 2.hours.ago,
        additional_attributes: { 'keep_me' => true, 'socialwise_ownership_epoch' => 4 }
      )
      disposable_keys = [
        Redis::Alfred::SOCIALWISE_DEBOUNCE_MESSAGES,
        Redis::Alfred::SOCIALWISE_DEBOUNCE_FIRST_AT,
        Redis::Alfred::SOCIALWISE_DEBOUNCE_LAST_AT,
        Redis::Alfred::SOCIALWISE_DEBOUNCE_ACTIVE
      ].map { |key| format(key, conversation_id: conversation.id) }
      lock_key = format(Redis::Alfred::SOCIALWISE_DEBOUNCE_LOCK, conversation_id: conversation.id)

      allow(Conversation).to receive(:find).with(conversation.id).and_return(conversation)
      expect(conversation).not_to receive(:bot_handoff!)
      disposable_keys.each { |key| expect(Redis::Alfred).to receive(:delete).with(key).once }
      expect(Redis::Alfred).not_to receive(:delete).with(lock_key)

      freeze_time do
        guard.pause_for_phase2!

        conversation.reload
        expect(conversation).to be_open
        expect(conversation.waiting_since).to be_nil
        expect(conversation.additional_attributes).to include(
          'keep_me' => true,
          'socialwise_handoff_at' => Time.current.iso8601(6),
          'socialwise_handoff_by' => 'captain_payment_phase2',
          'socialwise_ownership_epoch' => 5
        )
      end
    end

    it 'contains Redis cleanup failures after the database fence is durable' do
      allow(Redis::Alfred).to receive(:delete).and_raise(Redis::BaseError, 'unavailable')

      expect { guard.pause_for_phase2! }.not_to raise_error

      expect(conversation.reload.additional_attributes).to include(
        'socialwise_handoff_by' => 'captain_payment_phase2',
        'socialwise_ownership_epoch' => 1
      )
    end

    it 'contains cleanup reacquisition failures after the database fence is durable' do
      reload_count = 0
      allow(Conversation).to receive(:find).with(conversation.id) do
        reload_count += 1
        raise ActiveRecord::ConnectionNotEstablished, 'cleanup unavailable' if reload_count == 2

        Conversation.unscoped.find(conversation.id)
      end
      expect(Rails.logger).to receive(:warn).with(
        /Failed to clear debounce state for conversation #{conversation.id}: ActiveRecord::ConnectionNotEstablished: cleanup unavailable/
      )

      expect { guard.pause_for_phase2! }.not_to raise_error

      expect(reload_count).to eq(2)
      expect(conversation.reload.additional_attributes).to include(
        'socialwise_handoff_by' => 'captain_payment_phase2',
        'socialwise_ownership_epoch' => 1
      )
    end

    it 'merges the phase 2 fence from fresh locked attributes when initialized with a stale conversation' do
      stale_conversation = Conversation.find(conversation.id)
      Conversation.find(conversation.id).update!(
        additional_attributes: {
          'keep_me' => 'fresh',
          'socialwise_ownership_epoch' => 4
        }
      )
      stale_guard = build_guard(stale_conversation)
      allow(Redis::Alfred).to receive(:delete)

      stale_guard.pause_for_phase2!

      expect(conversation.reload.additional_attributes).to include(
        'keep_me' => 'fresh',
        'socialwise_handoff_by' => 'captain_payment_phase2',
        'socialwise_ownership_epoch' => 5
      )
    end

    it 'does not clear successor debounce state after its installed fence is superseded' do
      messages_key = format(Redis::Alfred::SOCIALWISE_DEBOUNCE_MESSAGES, conversation_id: conversation.id)
      first_at_key = format(Redis::Alfred::SOCIALWISE_DEBOUNCE_FIRST_AT, conversation_id: conversation.id)
      last_at_key = format(Redis::Alfred::SOCIALWISE_DEBOUNCE_LAST_AT, conversation_id: conversation.id)
      active_key = format(Redis::Alfred::SOCIALWISE_DEBOUNCE_ACTIVE, conversation_id: conversation.id)
      lock_key = format(Redis::Alfred::SOCIALWISE_DEBOUNCE_LOCK, conversation_id: conversation.id)
      cleanup_keys = [messages_key, first_at_key, last_at_key, active_key, lock_key]
      release_guard = build_guard(Conversation.find(conversation.id))

      allow(guard).to receive(:clear_disposable_debounce_keys).and_wrap_original do |original, *arguments, **keywords|
        expect(conversation.reload.additional_attributes).to include(
          'socialwise_handoff_by' => 'captain_payment_phase2',
          'socialwise_ownership_epoch' => 1
        )

        release_guard.release_for_resolve!(cutoff: 1.second.from_now)
        Redis::Alfred.lpush(messages_key, 'successor-message')
        Redis::Alfred.set(first_at_key, 'successor-first')
        Redis::Alfred.set(last_at_key, 'successor-last')
        Redis::Alfred.set(active_key, 'successor-active')
        Redis::Alfred.set(lock_key, 'successor-lock')

        original.call(*arguments, **keywords)
      end

      guard.pause_for_phase2!

      expect(conversation.reload.additional_attributes['socialwise_ownership_epoch']).to eq(2)
      expect(Redis::Alfred.lrange(messages_key, 0, -1)).to eq(['successor-message'])
      expect(Redis::Alfred.get(first_at_key)).to eq('successor-first')
      expect(Redis::Alfred.get(last_at_key)).to eq('successor-last')
      expect(Redis::Alfred.get(active_key)).to eq('successor-active')
      expect(Redis::Alfred.get(lock_key)).to eq('successor-lock')
    ensure
      cleanup_keys&.each { |key| Redis::Alfred.delete(key) }
    end

    it 'does not touch Redis when the locked database update fails' do
      locked_conversation = Conversation.find(conversation.id)
      allow(Conversation).to receive(:find).with(conversation.id).and_return(locked_conversation)
      allow(locked_conversation).to receive(:update!).and_raise(ActiveRecord::RecordInvalid.new(locked_conversation))
      expect(Redis::Alfred).not_to receive(:delete)

      expect { guard.pause_for_phase2! }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe '#release_for_resolve!' do
    let(:cutoff) { Time.current.change(usec: 0) }

    it 'atomically cancels the generation present at resolve, preserves correlation, removes only the canonical label, and advances the epoch' do
      conversation.update!(
        label_list: [canonical_label, 'keep_me'],
        additional_attributes: {
          'keep_me' => true,
          'socialwise_handoff_at' => 1.minute.ago.iso8601,
          'socialwise_handoff_by' => 'captain_payment_phase2',
          'socialwise_ownership_epoch' => 9
        }
      )
      trigger = create(
        :captain_payment_review_trigger,
        conversation: conversation,
        account: account,
        state: :eligible,
        activated_at: 2.minutes.ago,
        payment_context_id: 'payment-context',
        payment_context_version: 3,
        trigger_message_id: 123
      )

      guard.release_for_resolve!(cutoff: cutoff)

      expect(trigger.reload).to be_cancelled
      expect(trigger.deactivated_at).to be_present
      expect(trigger).to have_attributes(
        payment_context_id: 'payment-context',
        payment_context_version: 3,
        trigger_message_id: 123,
        generation: trigger.generation,
        event_key: trigger.event_key
      )
      expect(conversation.reload.label_list).to contain_exactly('keep_me')
      expect(conversation.additional_attributes).to eq(
        'keep_me' => true,
        'socialwise_ownership_epoch' => 10
      )
    end

    it 'does not consume a successor trigger or handoff created after the event timestamp' do
      conversation.update!(
        label_list: [canonical_label, 'keep_me'],
        additional_attributes: {
          'socialwise_handoff_at' => 1.minute.from_now.iso8601,
          'socialwise_handoff_by' => 'captain_payment_phase2',
          'socialwise_ownership_epoch' => 4
        }
      )
      successor = create_trigger(activated_at: 1.minute.from_now)

      guard.release_for_resolve!(cutoff: cutoff)

      expect(successor.reload).to be_eligible
      expect(successor.deactivated_at).to be_nil
      expect(conversation.reload.label_list).to contain_exactly(canonical_label, 'keep_me')
      expect(conversation.additional_attributes).to include(
        'socialwise_handoff_by' => 'captain_payment_phase2',
        'socialwise_ownership_epoch' => 4
      )
    end

    it 'cancels an old trigger without clearing a handoff acquired after the cutoff' do
      successor_handoff_at = 1.minute.from_now.change(usec: 0)
      conversation.update!(
        label_list: [canonical_label, 'keep_me'],
        additional_attributes: {
          'socialwise_handoff_at' => successor_handoff_at.iso8601,
          'socialwise_handoff_by' => 'captain_payment_phase2',
          'socialwise_ownership_epoch' => 4
        }
      )
      old_trigger = create_trigger(activated_at: 1.minute.ago)

      guard.release_for_resolve!(cutoff: cutoff)

      expect(old_trigger.reload).to be_cancelled
      expect(conversation.reload.label_list).to contain_exactly('keep_me')
      expect(conversation.additional_attributes).to include(
        'socialwise_handoff_at' => successor_handoff_at.iso8601,
        'socialwise_handoff_by' => 'captain_payment_phase2',
        'socialwise_ownership_epoch' => 5
      )
    end

    it 'preserves a phase 2 handoff acquired later in the same second as the resolve event' do
      resolve_cutoff = Time.zone.parse('2026-07-16 12:00:00.100000')
      handoff_time = resolve_cutoff + 0.2.seconds
      allow(Redis::Alfred).to receive(:delete)

      travel_to(handoff_time, with_usec: true) { guard.pause_for_phase2! }
      guard.release_for_resolve!(cutoff: resolve_cutoff)

      expect(conversation.reload.additional_attributes).to include(
        'socialwise_handoff_at' => handoff_time.iso8601(6),
        'socialwise_handoff_by' => 'captain_payment_phase2',
        'socialwise_ownership_epoch' => 1
      )
    end

    it 'releases an old handoff without removing the canonical label of a successor created after the cutoff' do
      conversation.update!(
        label_list: [canonical_label, 'keep_me'],
        additional_attributes: {
          'socialwise_handoff_at' => 1.minute.ago.iso8601,
          'socialwise_handoff_by' => 'captain_payment_phase2',
          'socialwise_ownership_epoch' => 4
        }
      )
      successor = create_trigger(activated_at: 1.minute.from_now)

      guard.release_for_resolve!(cutoff: cutoff)

      expect(successor.reload).to be_eligible
      expect(successor.deactivated_at).to be_nil
      expect(conversation.reload.label_list).to contain_exactly(canonical_label, 'keep_me')
      expect(conversation.additional_attributes).to eq('socialwise_ownership_epoch' => 5)
    end

    it 'leaves a conversation without a relevant trigger or handoff intact' do
      conversation.update!(label_list: ['keep_me'], additional_attributes: { 'custom' => 'value' })
      before_attributes = conversation.reload.attributes

      guard.release_for_resolve!(cutoff: cutoff)

      expect(conversation.reload.attributes).to eq(before_attributes)
    end

    it 'rolls back trigger cancellation when the conversation update fails' do
      conversation.update!(label_list: [canonical_label], additional_attributes: { 'socialwise_ownership_epoch' => 2 })
      trigger = create_trigger
      locked_conversation = Conversation.find(conversation.id)
      allow(Conversation).to receive(:find).with(conversation.id).and_return(locked_conversation)
      allow(locked_conversation).to receive(:update!).and_raise(ActiveRecord::RecordInvalid.new(locked_conversation))

      expect { guard.release_for_resolve!(cutoff: cutoff) }.to raise_error(ActiveRecord::RecordInvalid)

      expect(trigger.reload).to be_eligible
      expect(trigger.deactivated_at).to be_nil
      expect(conversation.reload.label_list).to contain_exactly(canonical_label)
      expect(conversation.additional_attributes['socialwise_ownership_epoch']).to eq(2)
    end

    it 'allows a later canonical re-add to create the next generation' do
      conversation.update!(label_list: [canonical_label])
      first_trigger = create_trigger

      guard.release_for_resolve!(cutoff: cutoff)
      Captain::PaymentReview::LabelMutationService.new(
        conversation: conversation,
        labels: [canonical_label],
        source: :manual
      ).add!

      expect(first_trigger.reload).to be_cancelled
      expect(Captain::PaymentReviewTrigger.present_generation.find_by!(conversation: conversation).generation).to eq(first_trigger.generation + 1)
    end

    %i[absent cancelled consumed].each do |trigger_state|
      it "removes an orphaned canonical label after releasing an old handoff when the trigger is #{trigger_state}" do
        conversation.update!(
          label_list: [canonical_label, 'keep_me'],
          additional_attributes: {
            'socialwise_handoff_at' => 1.minute.ago.iso8601,
            'socialwise_handoff_by' => 'captain_payment_phase2',
            'socialwise_ownership_epoch' => 2
          }
        )
        old_trigger = create_trigger(state: trigger_state) unless trigger_state == :absent

        guard.release_for_resolve!(cutoff: cutoff)

        expect(conversation.reload.label_list).to contain_exactly('keep_me')
        expect(old_trigger&.reload&.state).to eq(trigger_state.to_s) if old_trigger

        Captain::PaymentReview::LabelMutationService.new(
          conversation: conversation,
          labels: [canonical_label],
          source: :manual
        ).add!

        expected_generation = old_trigger&.generation.to_i + 1
        expect(Captain::PaymentReviewTrigger.present_generation.find_by!(conversation: conversation).generation).to eq(expected_generation)
      end
    end
  end
end
