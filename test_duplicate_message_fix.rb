#!/usr/bin/env ruby
# frozen_string_literal: true

# Test script to verify the duplicate message fix
# This script simulates the scenario that was causing duplicate messages

require 'bundler/setup'
require_relative 'config/environment'

puts "=== Testing Duplicate Message Fix ==="
puts "Date: #{Time.current}"
puts

# Find a test account and Instagram inbox
account = Account.first
if account.nil?
  puts "❌ No account found. Please create an account first."
  exit 1
end

instagram_inbox = account.inboxes.joins(:channel).where(channels: { type: 'Channel::Instagram' }).first
if instagram_inbox.nil?
  puts "❌ No Instagram inbox found. Please create an Instagram channel first."
  exit 1
end

puts "✅ Using Account: #{account.name} (ID: #{account.id})"
puts "✅ Using Instagram Inbox: #{instagram_inbox.name} (ID: #{instagram_inbox.id})"
puts

# Create a test contact and conversation
contact = instagram_inbox.contacts.first_or_create!(
  name: 'Test Contact for Duplicate Fix',
  identifier: 'test_duplicate_fix_contact',
  additional_attributes: { source_id: 'test_instagram_user_123' }
)

conversation = contact.conversations.create!(
  account: account,
  inbox: instagram_inbox,
  status: :pending
)

puts "✅ Created test conversation (ID: #{conversation.id})"
puts

# Create an incoming message to trigger the flow
incoming_message = conversation.messages.create!(
  content: 'Test message to trigger socialwise response',
  message_type: :incoming,
  account: account,
  inbox: instagram_inbox,
  sender: contact,
  source_id: 'test_message_123'
)

puts "✅ Created incoming message (ID: #{incoming_message.id})"
puts

# Test socialwise response data (Generic Template)
socialwise_data = {
  'message_format' => 'GENERIC_TEMPLATE',
  'payload' => {
    'template_type' => 'generic',
    'elements' => [
      {
        'title' => 'Test Template Title',
        'subtitle' => 'Test subtitle for duplicate fix verification',
        'image_url' => 'https://example.com/test-image.jpg',
        'buttons' => [
          {
            'type' => 'web_url',
            'title' => 'Visit Website',
            'url' => 'https://example.com'
          },
          {
            'type' => 'postback',
            'title' => 'Get Info',
            'payload' => 'GET_INFO_PAYLOAD'
          }
        ]
      }
    ]
  }
}

puts "🧪 Testing socialwise response processing..."
puts "📋 Socialwise data: #{socialwise_data.inspect}"
puts

# Count messages before processing
messages_before = conversation.messages.count
puts "📊 Messages before processing: #{messages_before}"

# Process the socialwise response
begin
  success = Integrations::Socialwise::InstagramResponseProcessor.process(socialwise_data, incoming_message)
  
  if success
    puts "✅ Socialwise response processed successfully"
  else
    puts "❌ Socialwise response processing failed"
  end
rescue => e
  puts "❌ Exception during processing: #{e.class}: #{e.message}"
  puts "   Backtrace: #{e.backtrace.first(3).join('\n   ')}"
end

# Count messages after processing
messages_after = conversation.messages.count
puts "📊 Messages after processing: #{messages_after}"
puts "📈 New messages created: #{messages_after - messages_before}"
puts

# Analyze the created messages
new_messages = conversation.messages.where('id > ?', incoming_message.id).order(:created_at)
puts "🔍 Analyzing created messages:"

new_messages.each_with_index do |msg, index|
  puts "  #{index + 1}. Message ID: #{msg.id}"
  puts "     Type: #{msg.message_type}"
  puts "     Content: #{msg.content.truncate(50)}"
  puts "     Skip send reply: #{msg.additional_attributes&.dig('skip_send_reply') || 'false'}"
  puts "     Source ID: #{msg.source_id || 'none'}"
  puts
end

# Check if the fix worked
outgoing_messages = new_messages.where(message_type: :outgoing)
messages_with_skip_flag = outgoing_messages.select { |m| m.additional_attributes&.dig('skip_send_reply') }

puts "📋 Summary:"
puts "  Total outgoing messages: #{outgoing_messages.count}"
puts "  Messages with skip_send_reply flag: #{messages_with_skip_flag.count}"

if messages_with_skip_flag.count > 0
  puts "✅ Fix is working! Messages are being created with skip_send_reply flag."
  puts "   This should prevent SendReplyJob from being enqueued for rich messages."
else
  puts "❌ Fix may not be working. No messages found with skip_send_reply flag."
end

puts
puts "🧹 Cleaning up test data..."

# Clean up test data
conversation.messages.destroy_all
conversation.destroy
contact.destroy

puts "✅ Test completed and cleaned up."
puts "=== End of Test ==="