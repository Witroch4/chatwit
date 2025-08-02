#!/usr/bin/env ruby

# Test script to verify Instagram postback functionality
# This script simulates the Instagram webhook payload for postback events

require_relative 'config/environment'

puts "=== TESTE DE POSTBACK DO INSTAGRAM ==="
puts "Data: #{Time.current}"
puts

# Find an Instagram channel for testing
instagram_channel = Channel::Instagram.first
unless instagram_channel
  puts "❌ Nenhum canal do Instagram encontrado. Crie um canal primeiro."
  exit 1
end

puts "✅ Canal Instagram encontrado: #{instagram_channel.id}"
puts "   Instagram ID: #{instagram_channel.instagram_id}"

# Find or create a test conversation
inbox = instagram_channel.inbox
contact = inbox.contacts.first || begin
  # Create a test contact if none exists
  contact_inbox = inbox.contact_inboxes.create!(
    source_id: "test_user_#{rand(10000)}",
    contact: Contact.create!(
      name: "Test User",
      account: inbox.account
    )
  )
  contact_inbox.contact
end

conversation = Conversation.where(
  account: inbox.account,
  inbox: inbox,
  contact: contact
).first || Conversation.create!(
  account: inbox.account,
  inbox: inbox,
  contact: contact,
  contact_inbox: contact.contact_inboxes.find_by(inbox: inbox)
)

puts "✅ Conversa de teste: #{conversation.id}"
puts

# Test 1: Simulate postback webhook payload
puts "=== TESTE 1: SIMULANDO WEBHOOK DE POSTBACK ==="

postback_messaging = {
  sender: { id: contact.contact_inboxes.find_by(inbox: inbox).source_id },
  recipient: { id: instagram_channel.instagram_id },
  timestamp: Time.current.to_i,
  postback: {
    title: "Teste Botão 1",
    payload: "btn_1753868215821_m995rldbs"
  }
}

puts "Payload do postback:"
puts JSON.pretty_generate(postback_messaging)
puts

# Test the parser
parser = Integrations::Instagram::MessageParser.new(postback_messaging)
puts "Parser results:"
puts "  postback?: #{parser.postback?}"
puts "  postback_title: #{parser.postback_title}"
puts "  postback_payload: #{parser.postback_payload}"
puts

# Test 2: Create message using the builder
puts "=== TESTE 2: CRIANDO MENSAGEM COM BUILDER ==="

begin
  builder = Messages::Instagram::MessageBuilder.new(postback_messaging, inbox)
  builder.perform
  
  # Find the created message
  message = conversation.messages.order(created_at: :desc).first
  
  if message
    puts "✅ Mensagem criada com sucesso!"
    puts "   ID: #{message.id}"
    puts "   Conteúdo: #{message.content}"
    puts "   Content Attributes: #{message.content_attributes}"
    puts "   Postback Payload: #{message.content_attributes['postback_payload']}"
  else
    puts "❌ Nenhuma mensagem foi criada"
  end
rescue => e
  puts "❌ Erro ao criar mensagem: #{e.message}"
  puts "   Backtrace: #{e.backtrace.first(5).join('\n   ')}"
end

puts

# Test 3: Test quick reply
puts "=== TESTE 3: SIMULANDO QUICK REPLY ==="

quick_reply_messaging = {
  sender: { id: contact.contact_inboxes.find_by(inbox: inbox).source_id },
  recipient: { id: instagram_channel.instagram_id },
  timestamp: Time.current.to_i,
  message: {
    mid: "quick_reply_#{rand(10000)}",
    text: "Opção 1",
    quick_reply: {
      payload: "quick_option_1"
    }
  }
}

puts "Payload do quick reply:"
puts JSON.pretty_generate(quick_reply_messaging)
puts

# Test the parser for quick reply
parser = Integrations::Instagram::MessageParser.new(quick_reply_messaging)
puts "Parser results:"
puts "  quick_reply?: #{parser.quick_reply?}"
puts "  quick_reply_payload: #{parser.quick_reply_payload}"
puts "  content: #{parser.content}"
puts

# Test 4: Create quick reply message
puts "=== TESTE 4: CRIANDO MENSAGEM DE QUICK REPLY ==="

begin
  builder = Messages::Instagram::MessageBuilder.new(quick_reply_messaging, inbox)
  builder.perform
  
  # Find the created message
  message = conversation.messages.order(created_at: :desc).first
  
  if message
    puts "✅ Mensagem de quick reply criada com sucesso!"
    puts "   ID: #{message.id}"
    puts "   Conteúdo: #{message.content}"
    puts "   Content Attributes: #{message.content_attributes}"
    puts "   Quick Reply Payload: #{message.content_attributes['quick_reply_payload']}"
  else
    puts "❌ Nenhuma mensagem foi criada"
  end
rescue => e
  puts "❌ Erro ao criar mensagem de quick reply: #{e.message}"
  puts "   Backtrace: #{e.backtrace.first(5).join('\n   ')}"
end

puts

# Test 5: Test Dialogflow integration if available
puts "=== TESTE 5: TESTANDO INTEGRAÇÃO COM DIALOGFLOW ==="

dialogflow_hook = inbox.account.hooks.find_by(app_id: 'dialogflow')
if dialogflow_hook
  puts "✅ Hook do Dialogflow encontrado: #{dialogflow_hook.id}"
  
  # Test with the postback message
  message = conversation.messages.where.not(content_attributes: {}).order(created_at: :desc).first
  if message
    puts "   Testando com mensagem ID: #{message.id}"
    puts "   Postback payload: #{message.content_attributes['postback_payload']}"
    puts "   Quick reply payload: #{message.content_attributes['quick_reply_payload']}"
    
    # Check if SocialWise is active
    socialwise_active = Integrations::Socialwise::WebhookEnhancerService.socialwise_active?(inbox.account)
    puts "   SocialWise ativo: #{socialwise_active}"
    
    if socialwise_active
      # Test payload enhancement
      webhook_payload = {
        message: message,
        conversation: conversation,
        contact: contact,
        inbox: inbox
      }
      
      enhanced_payload = Integrations::Socialwise::WebhookEnhancerService.enhance_payload(webhook_payload, inbox.account)
      
      if enhanced_payload['socialwise-chatwit']
        socialwise_data = enhanced_payload['socialwise-chatwit']
        puts "   ✅ Payload SocialWise gerado com sucesso"
        puts "   Instagram data: #{socialwise_data.dig('message_data', 'instagram_data')}"
        puts "   Postback payload no flat: #{enhanced_payload['postback_payload']}"
        puts "   Quick reply payload no flat: #{enhanced_payload['quick_reply_payload']}"
      else
        puts "   ❌ Payload SocialWise não foi gerado"
      end
    end
  else
    puts "   ❌ Nenhuma mensagem com content_attributes encontrada"
  end
else
  puts "❌ Hook do Dialogflow não encontrado"
end

puts
puts "=== TESTE CONCLUÍDO ==="
puts "Verifique os logs para mais detalhes sobre o processamento."