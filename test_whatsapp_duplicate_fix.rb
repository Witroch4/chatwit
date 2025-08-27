#!/usr/bin/env ruby
# Test script to verify WhatsApp duplicate message fix
# Run with: docker exec chatwit-dev-rails-1 bundle exec rails runner test_whatsapp_duplicate_fix.rb

puts "=== Testing WhatsApp Duplicate Message Fix ==="

# Create test account and channel
account = Account.find_or_create_by(name: 'Test Account') do |acc|
  acc.locale = 'pt-BR'
end

whatsapp_channel = Channel::Whatsapp.find_or_create_by(phone_number: '+5511999999999') do |channel|
  channel.account = account
  channel.provider = 'whatsapp_cloud'
  channel.provider_config = {
    'api_key' => 'test_key',
    'phone_number_id' => 'test_phone_id',
    'business_account_id' => 'test_business_id',
    'webhook_verify_token' => 'test_token'
  }
end

inbox = Inbox.find_or_create_by(channel: whatsapp_channel) do |i|
  i.account = account
  i.name = 'Test WhatsApp Inbox'
end

contact = Contact.find_or_create_by(phone_number: '+5511888888888') do |c|
  c.account = account
  c.name = 'Test Contact'
end

contact_inbox = ContactInbox.find_or_create_by(contact: contact, inbox: inbox) do |ci|
  ci.source_id = '+5511888888888'
end

conversation = Conversation.find_or_create_by(contact_inbox: contact_inbox) do |conv|
  conv.account = account
  conv.inbox = inbox
  conv.status = 'open'
end

puts "✅ Test environment created"
puts "   Account: #{account.id}"
puts "   Channel: #{whatsapp_channel.id}"
puts "   Conversation: #{conversation.id}"

# Test interactive message payload
interactive_payload = {
  'type' => 'interactive',
  'interactive' => {
    'type' => 'button',
    'body' => {
      'text' => 'Escolha uma opção:'
    },
    'action' => {
      'buttons' => [
        {
          'type' => 'reply',
          'reply' => {
            'id' => 'option_1',
            'title' => 'Opção 1'
          }
        },
        {
          'type' => 'reply',
          'reply' => {
            'id' => 'option_2',
            'title' => 'Opção 2'
          }
        }
      ]
    }
  }
}

puts "\n=== Testing Interactive Message Creation ==="

# Mock external services to avoid actual API calls
allow_any_instance_of(Whatsapp::Providers::WhatsappCloudService).to receive(:send_interactive_text_message).and_return('test_message_id')

# Process the payload using SocialwiseFlowProcessorService
processor = Integrations::SocialwiseFlow::ProcessorService.new(
  payload: {
    'whatsapp' => interactive_payload,
    'conversation_id' => conversation.id
  }
)

initial_message_count = conversation.messages.count
puts "Initial message count: #{initial_message_count}"

# Process the interactive message
processor.process_whatsapp_response(conversation, interactive_payload)

final_message_count = conversation.messages.count
puts "Final message count: #{final_message_count}"

# Check if message was created
if final_message_count > initial_message_count
  message = conversation.messages.last
  puts "✅ Message created successfully"
  puts "   Message ID: #{message.id}"
  puts "   Content type: #{message.content_type}"
  puts "   Content: #{message.content}"
  puts "   Skip send reply flag: #{message.additional_attributes['skip_send_reply']}"
  
  # Verify the fix
  if message.additional_attributes['skip_send_reply'] == true
    puts "✅ DUPLICATE FIX WORKING: skip_send_reply flag is set to true"
    puts "   This should prevent SendReplyJob from being enqueued"
  else
    puts "❌ DUPLICATE FIX NOT WORKING: skip_send_reply flag is missing or false"
    puts "   SendReplyJob will be enqueued, causing duplicate messages"
  end
  
  # Check content_type
  if message.content_type == 'integrations'
    puts "✅ Content type is correct: 'integrations'"
  else
    puts "❌ Content type is incorrect: '#{message.content_type}' (expected 'integrations')"
  end
  
  # Check content_attributes
  if message.content_attributes['interactive'].present?
    puts "✅ Interactive payload stored in content_attributes"
  else
    puts "❌ Interactive payload missing from content_attributes"
  end
  
else
  puts "❌ No message was created"
end

puts "\n=== Testing Text Message Creation (should not have skip flag) ==="

text_payload = {
  'type' => 'text',
  'text' => {
    'body' => 'Esta é uma mensagem de texto simples'
  }
}

initial_message_count = conversation.messages.count
processor.process_whatsapp_response(conversation, text_payload)
final_message_count = conversation.messages.count

if final_message_count > initial_message_count
  text_message = conversation.messages.last
  puts "✅ Text message created successfully"
  puts "   Message ID: #{text_message.id}"
  puts "   Content type: #{text_message.content_type}"
  puts "   Skip send reply flag: #{text_message.additional_attributes['skip_send_reply']}"
  
  if text_message.additional_attributes['skip_send_reply'] != true
    puts "✅ Text message correctly does NOT have skip_send_reply flag"
    puts "   SendReplyJob will be enqueued normally for text messages"
  else
    puts "❌ Text message incorrectly has skip_send_reply flag"
  end
else
  puts "❌ Text message was not created"
end

puts "\n=== Test Summary ==="
puts "Interactive messages should have skip_send_reply: true to prevent duplicate sending"
puts "Text messages should NOT have skip_send_reply flag to allow normal sending"
puts "This fix prevents the duplicate message issue where both RichMessageService and SendReplyJob send the same message"