#!/usr/bin/env ruby

# Test para verificar validação do canal Instagram

require_relative 'config/environment'

puts "=== Test Instagram Channel Validation ==="

# Criar dados de teste
account = Account.first
inbox = account.inboxes.find_by(channel_type: 'Channel::FacebookPage')
contact = inbox.contacts.first
conversation = contact.conversations.first

message = conversation.messages.create!(
  content: 'Test input',
  message_type: :incoming,
  account_id: account.id,
  inbox_id: inbox.id
)

puts "\n1. Dados do teste:"
puts "   Account: #{account.id}"
puts "   Inbox: #{inbox.id}"
puts "   Inbox channel_type: #{inbox.channel_type}"
puts "   Conversation: #{conversation.id}"
puts "   Conversation inbox channel_type: #{conversation.inbox.channel_type}"
puts "   Message: #{message.id}"

puts "\n2. Testando validação do canal..."

# Testar a validação que está no InstagramResponseProcessor
begin
  # Simular o que acontece no route_message
  puts "   Verificando se é Channel::Instagram..."
  puts "   conversation.inbox.channel_type: #{conversation.inbox.channel_type}"
  puts "   É Channel::Instagram? #{conversation.inbox.channel_type == 'Channel::Instagram'}"
  puts "   É Channel::FacebookPage? #{conversation.inbox.channel_type == 'Channel::FacebookPage'}"
  
  # O problema pode estar aqui - o processor pode estar esperando Channel::Instagram
  # mas Instagram usa Channel::FacebookPage
  
  puts "\n3. Verificando classe do canal..."
  channel = conversation.inbox.channel
  puts "   Channel class: #{channel.class}"
  puts "   É Channel::Instagram? #{channel.is_a?(Channel::Instagram)}"
  puts "   É Channel::FacebookPage? #{channel.is_a?(Channel::FacebookPage)}"
  
  # Verificar se o canal tem as propriedades necessárias para Instagram
  puts "\n4. Propriedades do canal:"
  if channel.respond_to?(:instagram_id)
    puts "   instagram_id: #{channel.instagram_id}"
  else
    puts "   instagram_id: NÃO DISPONÍVEL"
  end
  
  if channel.respond_to?(:page_id)
    puts "   page_id: #{channel.page_id}"
  else
    puts "   page_id: NÃO DISPONÍVEL"
  end
  
  if channel.respond_to?(:access_token)
    puts "   access_token presente: #{channel.access_token.present?}"
  else
    puts "   access_token: NÃO DISPONÍVEL"
  end
  
rescue => e
  puts "   ❌ ERRO: #{e.class}: #{e.message}"
end

puts "\n5. DIAGNÓSTICO:"
puts "   O problema pode estar na validação do canal no InstagramResponseProcessor."
puts "   Instagram usa Channel::FacebookPage, não Channel::Instagram."
puts "   Verificar se o processor está validando o canal correto."

puts "\n=== Fim do Test ==="