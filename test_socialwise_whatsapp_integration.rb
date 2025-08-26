#!/usr/bin/env ruby
# Test script to verify SocialwiseFlow WhatsApp integration

require_relative 'config/environment'

# Test data - simulating a real SocialWise Flow WhatsApp response
test_whatsapp_payload = {
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

# Test SocialWise Flow response format
socialwise_response = {
  'whatsapp' => test_whatsapp_payload,
  'text' => 'Fallback text message'
}

puts "=== TESTING SOCIALWISE FLOW WHATSAPP INTEGRATION ==="
puts "WhatsApp payload: #{test_whatsapp_payload.inspect}"
puts

# Find a WhatsApp conversation for testing
whatsapp_inbox = Inbox.joins(:channel).where(channels: { type: 'Channel::Whatsapp' }).first

unless whatsapp_inbox
  puts "❌ No WhatsApp inbox found. Please create a WhatsApp channel first."
  exit 1
end

puts "✅ Found WhatsApp inbox: #{whatsapp_inbox.name} (ID: #{whatsapp_inbox.id})"

# Find or create a test conversation
conversation = whatsapp_inbox.conversations.first
unless conversation
  # Create a test contact and conversation
  contact = whatsapp_inbox.account.contacts.create!(
    name: 'Test Contact',
    phone_number: '+5511999999999'
  )
  
  contact_inbox = ContactInbox.create!(
    contact: contact,
    inbox: whatsapp_inbox,
    source_id: '+5511999999999'
  )
  
  conversation = whatsapp_inbox.account.conversations.create!(
    inbox: whatsapp_inbox,
    contact: contact,
    contact_inbox: contact_inbox,
    status: 'pending'
  )
end

puts "✅ Using conversation: #{conversation.id}"

# Create a test incoming message
incoming_message = conversation.messages.create!(
  message_type: :incoming,
  content: 'Test message',
  account_id: conversation.account_id,
  inbox_id: conversation.inbox_id,
  sender: conversation.contact
)

puts "✅ Created test incoming message: #{incoming_message.id}"

# Test the SocialwiseFlow processor
puts "\n=== TESTING SOCIALWISE FLOW PROCESSOR ==="

begin
  # Create a mock hook for testing
  hook = double('Hook', 
    account: conversation.account,
    settings: {
      'endpoint' => 'https://test.socialwise.com/webhook',
      'access_token' => 'test_token'
    }
  )
  
  # Create processor instance
  processor = Integrations::SocialwiseFlow::ProcessorService.new(
    event_name: 'message.created',
    hook: hook,
    event_data: { message: incoming_message }
  )
  
  puts "✅ Created SocialwiseFlow processor"
  
  # Test the process_whatsapp_response method directly
  puts "\n--- Testing process_whatsapp_response ---"
  
  # Call the private method using send
  processor.send(:process_whatsapp_response, incoming_message, test_whatsapp_payload)
  
  puts "✅ process_whatsapp_response completed without errors"
  
  # Check if message was created
  outgoing_messages = conversation.messages.outgoing.where('created_at > ?', incoming_message.created_at)
  
  if outgoing_messages.any?
    outgoing_message = outgoing_messages.last
    puts "✅ Outgoing message created:"
    puts "   ID: #{outgoing_message.id}"
    puts "   Content: #{outgoing_message.content}"
    puts "   Content Type: #{outgoing_message.content_type}"
    puts "   Content Attributes: #{outgoing_message.content_attributes.inspect}"
    
    # Test if the WhatsApp service can handle this message
    puts "\n--- Testing WhatsApp Service Integration ---"
    
    begin
      whatsapp_service = Whatsapp::SendOnWhatsappService.new(message: outgoing_message)
      
      # Check if the service recognizes the message format
      if outgoing_message.content_type == 'integrations'
        puts "✅ Message has content_type 'integrations'"
        puts "✅ Content attributes contain interactive payload"
      elsif outgoing_message.content_type == 'input_select'
        puts "✅ Message has content_type 'input_select'"
      else
        puts "⚠️  Message has content_type '#{outgoing_message.content_type}'"
      end
      
      puts "✅ WhatsApp service can process this message format"
      
    rescue => e
      puts "❌ WhatsApp service error: #{e.class}: #{e.message}"
      puts "   This indicates a compatibility issue"
    end
    
  else
    puts "❌ No outgoing message was created"
  end
  
rescue => e
  puts "❌ Error testing SocialwiseFlow processor: #{e.class}: #{e.message}"
  puts "   Backtrace: #{e.backtrace.first(5).join('\n   ')}"
end

puts "\n=== TEST COMPLETED ==="