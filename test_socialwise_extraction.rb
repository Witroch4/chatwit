#!/usr/bin/env ruby

require_relative 'config/environment'

# Simular o payload real
real_webhook_payload = {
  "account" => {"id" => 3, "name" => "DraAmandaSousa"},
  "content_attributes" => {},
  "content_type" => "text",
  "content" => nil,
  "conversation" => {
    "channel" => "Channel::Whatsapp",
    "id" => 1778,
    "inbox_id" => 4,
    "status" => "pending",
    "created_at" => 1753402911,
    "updated_at" => 1753521674.057222,
    "meta" => {
      "sender" => {
        "id" => 1447,
        "name" => "Witalo Rocha",
        "phone_number" => "+558597550136",
        "email" => nil,
        "custom_attributes" => {}
      }
    }
  },
  "id" => 32892,
  "inbox" => {"id" => 4, "name" => "WhatsApp - ANA"},
  "message_type" => "incoming",
  "sender" => {
    "id" => 1447,
    "name" => "Witalo Rocha",
    "phone_number" => "+558597550136",
    "custom_attributes" => {}
  },
  "source_id" => "wamid.HBgMNTU4NTk3NTUwMTM2FQIAEhgUM0E3REYyMDA4NTVENTkzNzQ3NEYA",
  "event" => "message_created"
}

puts "=== TESTE DE EXTRAÇÃO SOCIALWISE ==="

# Simular account
account = OpenStruct.new(id: 3, name: "DraAmandaSousa")

# Testar se o SocialWise está ativo (vai dar false, mas não importa para o teste)
service = Integrations::Socialwise::WebhookEnhancerService

begin
  # Testar extração de objetos
  puts "Testando extração de objetos..."
  
  message = service.send(:extract_message_from_payload, real_webhook_payload)
  puts "Message extraída: #{message.class} - ID: #{message&.id}"
  
  conversation = service.send(:extract_conversation_from_payload, real_webhook_payload)
  puts "Conversation extraída: #{conversation.class} - ID: #{conversation&.id}"
  
  contact = service.send(:extract_contact_from_payload, real_webhook_payload)
  puts "Contact extraído: #{contact.class} - ID: #{contact&.id}, Nome: #{contact&.name}"
  
  inbox = service.send(:extract_inbox_from_payload, real_webhook_payload)
  puts "Inbox extraída: #{inbox.class} - ID: #{inbox&.id}, Tipo: #{inbox&.channel_type}"
  
  puts "\n=== TESTE DE CONSTRUÇÃO DE DADOS ==="
  
  # Testar construção de dados individuais
  whatsapp_identifiers = service.send(:build_whatsapp_identifiers, message, contact)
  puts "WhatsApp Identifiers: #{whatsapp_identifiers}"
  
  contact_data = service.send(:build_contact_data, contact)
  puts "Contact Data: #{contact_data}"
  
  message_data = service.send(:build_message_data, message)
  puts "Message Data: #{message_data}"
  
  puts "\n=== SUCESSO! ==="
  
rescue => e
  puts "ERRO: #{e.class}: #{e.message}"
  puts "Backtrace: #{e.backtrace.first(5).join('\n')}"
end