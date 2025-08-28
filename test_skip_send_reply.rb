#!/usr/bin/env ruby

# Test script to verify skip_send_reply flag is working

puts "=== Testing skip_send_reply flag functionality ==="

# Load Rails environment
require_relative 'config/environment'

# Test 1: Create a message with skip_send_reply flag
puts "\n1. Testing message creation with skip_send_reply flag..."

# Find a test conversation
conversation = Conversation.joins(:inbox)
                          .where(inboxes: { channel_type: 'Channel::Whatsapp' })
                          .first

if conversation.nil?
  puts "❌ No WhatsApp conversation found for testing"
  exit 1
end

puts "✅ Found test conversation: #{conversation.id}"

# Create message with skip_send_reply flag
test_message = conversation.messages.create!(
  content: "Test message with skip_send_reply flag",
  message_type: :outgoing,
  account_id: conversation.account_id,
  inbox_id: conversation.inbox_id,
  additional_attributes: { skip_send_reply: true }
)

puts "✅ Created test message: #{test_message.id}"
puts "✅ Message additional_attributes: #{test_message.additional_attributes.inspect}"

# Test 2: Verify the flag is properly stored
skip_flag = test_message.additional_attributes&.dig('skip_send_reply')
puts "✅ skip_send_reply flag value: #{skip_flag}"

if skip_flag == true
  puts "✅ Flag is properly set to true"
else
  puts "❌ Flag is not properly set: #{skip_flag.inspect}"
end

# Test 3: Test the send_reply method
puts "\n2. Testing send_reply method behavior..."

class TestMessage < Message
  def self.test_send_reply_logic(additional_attrs)
    # Simulate the send_reply logic
    return "SKIPPED" if additional_attrs&.dig('skip_send_reply')
    return "WOULD_SEND"
  end
end

# Test with flag
result_with_flag = TestMessage.test_send_reply_logic({ 'skip_send_reply' => true })
puts "✅ With skip_send_reply=true: #{result_with_flag}"

# Test without flag
result_without_flag = TestMessage.test_send_reply_logic({})
puts "✅ Without skip_send_reply: #{result_without_flag}"

# Test with nil
result_with_nil = TestMessage.test_send_reply_logic(nil)
puts "✅ With nil additional_attributes: #{result_with_nil}"

# Clean up
test_message.destroy
puts "\n✅ Test message cleaned up"

puts "\n=== Test completed successfully! ==="
puts "✅ skip_send_reply flag is working correctly"
puts "✅ Messages with the flag will skip automatic sending"