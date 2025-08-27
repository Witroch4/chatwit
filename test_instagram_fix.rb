#!/usr/bin/env ruby

# Test para verificar se o fix do Instagram funciona

require_relative 'config/environment'

puts "=== Teste do Fix Instagram SocialWise Flow ==="

# Criar dados de teste
account = Account.first || Account.create!(name: 'Test Account')
user = User.first || User.create!(name: 'Test User', email: 'test@example.com', password: 'password')
inbox = account.inboxes.find_by(channel_type: 'Channel::FacebookPage') || 
        account.inboxes.create!(
          name: 'Test Instagram',
          channel_type: 'Channel::FacebookPage',
          channel_attributes: {
            'page_id' => 'test_page_id',
            'page_access_token' => 'test_token'
          }
        )

contact = inbox.contacts.first || inbox.contacts.create!(
  name: 'Test Contact',
  account: account
)

conversation = contact.conversations.first || contact.conversations.create!(
  account: account,
  inbox: inbox
)

# Criar mensagem de entrada
incoming_message = conversation.messages.create!(
  content: 'Test message',
  message_type: :incoming,
  account_id: account.id,
  inbox_id: inbox.id
)

puts "\n1. Dados de teste criados:"
puts "   Account: #{account.id}"
puts "   Inbox: #{inbox.id} (#{inbox.channel_type})"
puts "   Conversation: #{conversation.id}"
puts "   Message: #{incoming_message.id}"

# Payload do SocialWise Flow (formato atual)
socialwise_response = {
  'instagram' => {
    'message_format' => 'GENERIC_TEMPLATE',
    'template_type' => 'generic',
    'elements' => [
      {
        'title' => 'Teste de mensagem rica',
        'subtitle' => 'Subtítulo do teste',
        'buttons' => [
          {
            'type' => 'postback',
            'title' => 'Clique aqui',
            'payload' => 'test_payload_123'
          }
        ],
        'image_url' => 'https://example.com/image.jpg'
      }
    ]
  }
}

puts "\n2. Payload de teste:"
puts socialwise_response.inspect

# Simular o processamento
begin
  puts "\n3. Testando process_instagram_response..."
  
  # Extrair payload do Instagram
  instagram_payload = socialwise_response['instagram']
  
  # Aplicar o fix: reestruturar payload
  restructured_payload = {
    'message_format' => instagram_payload['message_format'],
    'payload' => instagram_payload.except('message_format')
  }
  
  puts "   Payload reestruturado: #{restructured_payload.inspect}"
  
  # Testar com InstagramResponseProcessor
  puts "\n4. Testando InstagramResponseProcessor.process..."
  success = Integrations::Socialwise::InstagramResponseProcessor.process(restructured_payload, incoming_message)
  
  puts "   Resultado: #{success ? '✅ SUCESSO' : '❌ FALHA'}"
  
  # Verificar se mensagem foi criada
  outgoing_messages = conversation.messages.outgoing.where('created_at > ?', 1.minute.ago)
  puts "\n5. Mensagens criadas: #{outgoing_messages.count}"
  
  outgoing_messages.each do |msg|
    puts "   Mensagem #{msg.id}:"
    puts "     Content: #{msg.content}"
    puts "     Content Type: #{msg.content_type}"
    puts "     Content Attributes: #{msg.content_attributes.keys.join(', ')}"
  end
  
  if success && outgoing_messages.any?
    puts "\n✅ FIX FUNCIONOU! Mensagem rica do Instagram foi processada corretamente."
  else
    puts "\n❌ FIX NÃO FUNCIONOU. Verificar logs para mais detalhes."
  end
  
rescue => e
  puts "\n❌ ERRO durante o teste: #{e.class}: #{e.message}"
  puts "   Backtrace: #{e.backtrace.first(5).join('\n   ')}"
end

puts "\n=== Fim do Teste ==="