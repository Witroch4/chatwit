require 'rails_helper'

RSpec.describe SocialwiseDebounceJob do
  let(:job) { described_class.new }
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:message) { create(:message, account: account, inbox: inbox, conversation: conversation) }
  let(:hook) do
    create(
      :integrations_hook,
      account: account,
      inbox: inbox,
      app_id: 'socialwise_flow',
      settings: { 'language' => 'pt-BR' }
    )
  end
  let(:messages_key) { format(Redis::Alfred::SOCIALWISE_DEBOUNCE_MESSAGES, conversation_id: conversation.id) }
  let(:first_at_key) { format(Redis::Alfred::SOCIALWISE_DEBOUNCE_FIRST_AT, conversation_id: conversation.id) }
  let(:last_at_key) { format(Redis::Alfred::SOCIALWISE_DEBOUNCE_LAST_AT, conversation_id: conversation.id) }
  let(:active_key) { format(Redis::Alfred::SOCIALWISE_DEBOUNCE_ACTIVE, conversation_id: conversation.id) }
  let(:lock_key) { format(Redis::Alfred::SOCIALWISE_DEBOUNCE_LOCK, conversation_id: conversation.id) }
  let(:pending_message) do
    { message_id: message.id, content: message.content, timestamp: Time.current.to_f, ownership_epoch: 0 }.to_json
  end

  before do
    # MockRedis does not implement EVAL; script semantics are covered with real Redis below.
    allow(job).to receive(:release_active)
  end

  def create_eligible_trigger
    create(:captain_payment_review_trigger, conversation: conversation, account: account, state: :eligible)
  end

  def stub_ready_job
    stub_ready_redis
    stub_ready_timing
    allow(job).to receive(:claim_pending_messages).and_return([pending_message])
  end

  def stub_ready_redis
    allow(Redis::Alfred).to receive(:set).and_return(true)
    allow(Redis::Alfred).to receive(:delete)
  end

  def stub_ready_timing
    allow(job).to receive(:sleep)
    allow(job).to receive(:should_process_now?).and_return(true)
    allow(job).to receive(:acquire_lock).with(lock_key).and_return('owner-token')
    allow(job).to receive(:release_lock)
  end

  it 'stops before ACTIVE, sleep, or batch access when an eligible trigger is already present' do
    create_eligible_trigger
    expect(Redis::Alfred).not_to receive(:set).with(active_key, anything, anything)
    expect(Redis::Alfred).not_to receive(:lrange).with(messages_key, 0, -1)
    expect(job).not_to receive(:sleep)

    job.perform(conversation.id, hook.id, 'message.created', 5000, 30_000, 0)
  end

  it 'fails closed before Redis and provider work for a legacy job without an ownership epoch' do
    conversation
    hook
    expect(Redis::Alfred).not_to receive(:set).with(active_key, anything, anything)
    expect(Redis::Alfred).not_to receive(:lrange).with(messages_key, 0, -1)
    expect(job).not_to receive(:sleep)
    expect(Integrations::SocialwiseFlow::DebounceProcessorService).not_to receive(:new)
    expect(HTTParty).not_to receive(:post)

    job.perform(conversation.id, hook.id, 'message.created', 5000, 30_000)
  end

  it 'does not rebadge an old batch after cleanup failure followed by pause and resolve' do
    allow(Redis::Alfred).to receive(:delete).and_raise(Redis::BaseError, 'unavailable')
    guard = Integrations::SocialwiseFlow::OwnershipGuard.new(conversation)
    guard.pause_for_phase2!
    guard.release_for_resolve!(cutoff: Time.current)

    expect(conversation.reload.additional_attributes['socialwise_ownership_epoch']).to eq(2)
    expect(Redis::Alfred).not_to receive(:set)
    expect(job).not_to receive(:sleep)
    expect(Integrations::SocialwiseFlow::DebounceProcessorService).not_to receive(:new)
    expect(HTTParty).not_to receive(:post)

    expect { job.perform(conversation.id, hook.id, 'message.created', 5000, 30_000, 0) }.not_to raise_error
  end

  it 'acquires ACTIVE with an opaque NX token and rechecks ownership before the first sleep' do
    allow(SecureRandom).to receive(:uuid).and_return('active-owner-token')
    expect(Redis::Alfred).to receive(:set).with(active_key, 'active-owner-token', nx: true, ex: 60) do
      create_eligible_trigger
      true
    end
    expect(job).not_to receive(:sleep)

    job.perform(conversation.id, hook.id, 'message.created', 5000, 30_000, 0)
  end

  it 'does not delete a successor ACTIVE token while an old job exits' do
    allow(SecureRandom).to receive(:uuid).and_return('old-active-token')
    expect(job).to receive(:release_active).with(active_key, 'old-active-token') do |key, token|
      Redis::Alfred.delete(key) if Redis::Alfred.get(key) == token
    end
    allow(job).to receive(:sleep) do
      Redis::Alfred.delete(active_key)
      Redis::Alfred.set(active_key, 'successor-token', nx: true, ex: 60)
      create_eligible_trigger
    end

    job.perform(conversation.id, hook.id, 'message.created', 5000, 30_000, 0)

    expect(Redis::Alfred.get(active_key)).to eq('successor-token')
  ensure
    Redis::Alfred.delete(active_key)
  end

  it 'schedules a valid successor when the owned ACTIVE token expired before release' do
    connection = instance_double(Redis, lrange: [pending_message])
    allow(job).to receive(:acquire_active).with(active_key, 60).and_return('expired-owner-token')
    allow(job).to receive(:sleep)
    allow(job).to receive(:should_process_now?).and_return(true)
    allow(job).to receive(:acquire_lock).with(lock_key).and_return('lock-owner-token')
    allow(job).to receive(:release_lock)
    allow(job).to receive(:process_debounced_messages)
    allow(job).to receive(:release_active).with(active_key, 'expired-owner-token').and_return(0)
    allow(Redis::Alfred).to receive(:get).with(active_key).and_return(nil)
    allow(job).to receive(:with_redis).and_yield(connection)
    expect(described_class).to receive(:perform_later).with(
      conversation.id,
      hook.id,
      'message.created',
      5000,
      30_000,
      0
    )

    job.perform(conversation.id, hook.id, 'message.created', 5000, 30_000, 0)
  end

  it 'does not scan or schedule when compare-delete finds a successor ACTIVE token' do
    allow(job).to receive(:acquire_active).with(active_key, 60).and_return('old-owner-token')
    allow(job).to receive(:sleep)
    allow(job).to receive(:should_process_now?).and_return(true)
    allow(job).to receive(:acquire_lock).with(lock_key).and_return('lock-owner-token')
    allow(job).to receive(:release_lock)
    allow(job).to receive(:process_debounced_messages)
    allow(job).to receive(:release_active).with(active_key, 'old-owner-token').and_return(0)
    allow(Redis::Alfred).to receive(:get).with(active_key).and_return('successor-active-token')
    expect(job).not_to receive(:with_redis)
    expect(described_class).not_to receive(:perform_later)

    job.perform(conversation.id, hook.id, 'message.created', 5000, 30_000, 0)
  end

  it 'does not acquire the lock or remove the batch when ownership is lost during sleep' do
    allow(Redis::Alfred).to receive(:set).and_return(true)
    allow(Redis::Alfred).to receive(:delete)
    allow(job).to receive(:sleep) { create_eligible_trigger }
    expect(job).not_to receive(:acquire_lock)
    expect(Redis::Alfred).not_to receive(:lrange).with(messages_key, 0, -1)
    expect(Redis::Alfred).not_to receive(:delete).with(messages_key)

    job.perform(conversation.id, hook.id, 'message.created', 5000, 30_000, 0)
  end

  it 'does not inspect or remove the batch when ownership is lost while acquiring the lock' do
    stub_ready_job
    allow(job).to receive(:acquire_lock).with(lock_key) do
      create_eligible_trigger
      'owner-token'
    end
    expect(Redis::Alfred).not_to receive(:lrange).with(messages_key, 0, -1)
    expect(Redis::Alfred).not_to receive(:delete).with(messages_key)

    job.perform(conversation.id, hook.id, 'message.created', 5000, 30_000, 0)
  end

  it 'revalidates immediately before invoking the debounce processor' do
    stub_ready_job
    allow(Redis::Alfred).to receive(:lrange).with(messages_key, 0, -1).and_return([pending_message])
    allow(Message).to receive(:find_by).with(id: message.id) do
      create_eligible_trigger
      message
    end
    expect(Integrations::SocialwiseFlow::DebounceProcessorService).not_to receive(:new)

    job.perform(conversation.id, hook.id, 'message.created', 5000, 30_000, 0)
  end

  it 'revalidates the original epoch after processor construction and immediately before perform' do
    stub_ready_job
    allow(Redis::Alfred).to receive(:lrange).with(messages_key, 0, -1).and_return([pending_message])
    allow(Message).to receive(:find_by).with(id: message.id).and_return(message)
    processor = instance_double(Integrations::SocialwiseFlow::DebounceProcessorService)
    allow(Integrations::SocialwiseFlow::DebounceProcessorService).to receive(:new) do
      ownership_guard = Integrations::SocialwiseFlow::OwnershipGuard.new(conversation)
      ownership_guard.pause_for_phase2!
      ownership_guard.release_for_resolve!(cutoff: Time.current)
      processor
    end
    expect(processor).not_to receive(:perform)

    job.perform(conversation.id, hook.id, 'message.created', 5000, 30_000, 0)

    expect(conversation.reload.additional_attributes['socialwise_ownership_epoch']).to eq(2)
  end

  it 'continues through the batch for an ineligible trigger' do
    create(:captain_payment_review_trigger, conversation: conversation, account: account, state: :ineligible)
    stub_ready_job
    allow(Redis::Alfred).to receive(:lrange).with(messages_key, 0, -1).and_return([pending_message])
    allow(Message).to receive(:find_by).with(id: message.id).and_return(message)
    processor = instance_double(Integrations::SocialwiseFlow::DebounceProcessorService, perform: nil)
    expect(Integrations::SocialwiseFlow::DebounceProcessorService).to receive(:new).and_return(processor)

    job.perform(conversation.id, hook.id, 'message.created', 5000, 30_000, 0)
  end

  it 'preserves a message appended after the ready read instead of deleting it with the claimed batch' do
    redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379/0'))
    concurrent_message = create(:message, account: account, inbox: inbox, conversation: conversation, content: 'concurrent')
    concurrent_payload = {
      message_id: concurrent_message.id,
      content: concurrent_message.content,
      timestamp: Time.current.to_f + 1,
      ownership_epoch: 0
    }.to_json
    redis.lpush(messages_key, pending_message)
    redis.set(first_at_key, (Time.current.to_f - 1).to_s)
    redis.set(last_at_key, Time.current.to_f.to_s)
    stub_ready_timing
    allow(job).to receive(:release_active).and_return(1)
    allow(job).to receive(:with_redis).and_yield(redis)
    allow(job).to receive(:process_debounced_messages).and_wrap_original do |original, *arguments, **keywords|
      redis.lpush(messages_key, concurrent_payload)
      original.call(*arguments, **keywords)
    end
    processor = instance_double(Integrations::SocialwiseFlow::DebounceProcessorService, perform: nil)
    allow(Integrations::SocialwiseFlow::DebounceProcessorService).to receive(:new).and_return(processor)
    expect(described_class).to receive(:perform_later).with(
      conversation.id,
      hook.id,
      'message.created',
      5000,
      30_000,
      0
    )

    job.perform(conversation.id, hook.id, 'message.created', 5000, 30_000, 0)

    remaining_ids = redis.lrange(messages_key, 0, -1).map { |raw| JSON.parse(raw).fetch('message_id') }
    expect(remaining_ids).to contain_exactly(concurrent_message.id)
  ensure
    redis&.del(messages_key, first_at_key, last_at_key)
    redis&.close
    [messages_key, first_at_key, last_at_key, active_key, lock_key].each { |key| Redis::Alfred.delete(key) }
  end

  it 'claims only the expected ready epoch and atomically recomputes retained batch timestamps' do
    redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379/0'))
    suffix = SecureRandom.uuid
    keys = %W[socialwise-spec:#{suffix}:messages socialwise-spec:#{suffix}:first socialwise-spec:#{suffix}:last]
    entries = [
      '{malformed',
      { message_id: 'legacy', timestamp: 10 }.to_json,
      { message_id: 'old', timestamp: 10, ownership_epoch: 6 }.to_json,
      { message_id: 'claim', timestamp: 10, ownership_epoch: 7 }.to_json,
      { message_id: 'concurrent', timestamp: 30, ownership_epoch: 7 }.to_json,
      { message_id: 'future', timestamp: 40, ownership_epoch: 8 }.to_json
    ]
    entries.each { |entry| redis.rpush(keys.first, entry) }

    claimed = redis.eval(
      described_class::CLAIM_SCRIPT,
      keys: keys,
      argv: [7, 20, 120]
    )

    expect(claimed.map { |raw| JSON.parse(raw).fetch('message_id') }).to contain_exactly('claim')
    retained = redis.lrange(keys.first, 0, -1).map { |raw| JSON.parse(raw).fetch('message_id') }
    expect(retained).to eq(%w[concurrent future])
    expect(redis.mget(keys.second, keys.third)).to eq(%w[30 40])
    expect(keys.map { |key| redis.ttl(key) }).to all(be_positive)
  ensure
    redis&.del(*keys) if keys
    redis&.close
  end

  it 'fails closed instead of scheduling a successor from malformed or legacy retained items' do
    connection = instance_double(
      Redis,
      lrange: ['{malformed', { message_id: 'legacy', timestamp: 10 }.to_json]
    )
    ownership_guard = instance_double(Integrations::SocialwiseFlow::OwnershipGuard)
    allow(job).to receive(:with_redis).and_yield(connection)
    expect(ownership_guard).not_to receive(:can_publish?)
    expect(described_class).not_to receive(:perform_later)

    result = job.send(
      :schedule_successor_if_pending,
      conversation_id: conversation.id,
      hook_id: hook.id,
      event_name: 'message.created',
      debounce_ms: 5000,
      max_timeout_ms: 30_000,
      ownership_guard: ownership_guard
    )

    expect(result).to be(false)
  end

  describe 'owned Redis lock release' do
    it 'returns an opaque token when the lock is acquired' do
      allow(Redis::Alfred).to receive(:set).and_return(true)

      expect(job.send(:acquire_lock, lock_key)).to be_a(String)
    end

    it 'uses compare-and-delete instead of deleting an unowned lock' do
      key = lock_key
      redis = instance_double(Redis)
      # rubocop:disable Style/GlobalVars
      allow($alfred).to receive(:with).and_yield(redis)
      # rubocop:enable Style/GlobalVars
      expect(redis).to receive(:eval).with(kind_of(String), keys: [key], argv: ['owner-token'])
      expect(Redis::Alfred).not_to receive(:delete).with(key)

      job.send(:release_lock, key, 'owner-token')
    end

    it 'uses the same compare-and-delete ownership check for ACTIVE' do
      redis = instance_double(Redis)
      key = active_key
      allow(job).to receive(:release_active).and_call_original
      # rubocop:disable Style/GlobalVars
      allow($alfred).to receive(:with).and_yield(redis)
      # rubocop:enable Style/GlobalVars
      expect(redis).to receive(:eval).with(kind_of(String), keys: [key], argv: ['active-owner-token'])
      expect(Redis::Alfred).not_to receive(:delete).with(key)

      job.send(:release_active, key, 'active-owner-token')
    end
  end
end
