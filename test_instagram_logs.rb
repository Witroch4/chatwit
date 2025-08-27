#!/usr/bin/env ruby

# Test para capturar logs específicos do InstagramResponseProcessor

require_relative 'config/environment'

# Configurar logs para capturar tudo
Rails.logger.level = Logger::DEBUG

puts "=== Test Instagram Logs ==="

# Payload reestruturado
restructured_payload = {
  'message_format' => 'GENERIC_TEMPLATE',
  'payload' => {
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

# Criar dados de teste
account = Account.first
inbox = account.inboxes.find_by(channel_type: 'Channel::FacebookPage')
contact = inbox.contacts.first
conversation = contact.conversations.first

# Criar mensagem de entrada
message = conversation.messages.create!(
  content: 'Test input',
  message_type: :incoming,
  account_id: account.id,
  inbox_id: inbox.id
)

puts "\nChamando InstagramResponseProcessor.process com logs habilitados..."

# Capturar logs em tempo real
begin
  success = Integrations::Socialwise::InstagramResponseProcessor.process(restructured_payload, message)
  puts "\nResultado: #{success}"
rescue => e
  puts "\nERRO: #{e.class}: #{e.message}"
  puts "Backtrace: #{e.backtrace.first(5).join('\n')}"
end

# Verificar mensagens criadas
recent_messages = conversation.messages.where('created_at > ?', 1.minute.ago)
puts "\nMensagens criadas: #{recent_messages.count}"

recent_messages.each do |msg|
  puts "  Mensagem #{msg.id}:"
  puts "    Content: #{msg.content}"
  puts "    Content Type: #{msg.content_type}"
  puts "    Message Type: #{msg.message_type}"
  puts "    Content Attributes: #{msg.content_attributes}"
end

puts "\n=== Fim do Test ==="