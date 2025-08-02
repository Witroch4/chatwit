#!/usr/bin/env ruby
# Teste para verificar se a feature SOCIALWISE_RICH_DASHBOARD está funcionando

puts "=== Teste da Feature SOCIALWISE_RICH_DASHBOARD ==="

# Verificar se a feature está na lista
puts "\n1. Verificando se a feature está na lista:"
feature_list = YAML.safe_load(Rails.root.join('config/features.yml').read)
socialwise_feature = feature_list.find { |f| f['name'] == 'SOCIALWISE_RICH_DASHBOARD' }

if socialwise_feature
  puts "✅ Feature encontrada: #{socialwise_feature.inspect}"
else
  puts "❌ Feature não encontrada na lista"
  exit 1
end

# Verificar a conta 3
puts "\n2. Verificando conta 3:"
begin
  account = Account.find(3)
  puts "✅ Conta 3 encontrada: #{account.name}"
  
  # Verificar se a feature está habilitada
  enabled = account.feature_enabled?('SOCIALWISE_RICH_DASHBOARD')
  puts "Feature habilitada: #{enabled}"
  
  if enabled
    puts "✅ Feature está habilitada para a conta 3"
  else
    puts "⚠️  Feature não está habilitada para a conta 3"
    puts "Habilitando agora..."
    account.enable_features!('SOCIALWISE_RICH_DASHBOARD')
    puts "✅ Feature habilitada!"
  end
  
rescue ActiveRecord::RecordNotFound
  puts "❌ Conta 3 não encontrada"
  exit 1
end

# Testar com uma mensagem simulada
puts "\n3. Testando com Instagram Rich Message Service:"
begin
  # Encontrar uma conversa da conta 3
  conversation = account.conversations.joins(:inbox)
                        .where(inboxes: { channel_type: 'Channel::Instagram' })
                        .first
  
  if conversation
    puts "✅ Conversa Instagram encontrada: #{conversation.id}"
    
    # Criar uma mensagem de teste
    message = conversation.messages.create!(
      content: 'Teste de mensagem rica',
      message_type: :outgoing,
      account_id: account.id,
      inbox_id: conversation.inbox.id,
      additional_attributes: { skip_send_reply: true }
    )
    
    puts "✅ Mensagem criada: #{message.id}"
    
    # Testar o payload rico
    rich_payload = {
      'template_type' => 'generic',
      'elements' => [
        {
          'title' => 'Teste de Produto',
          'subtitle' => 'Testando o dashboard rico',
          'image_url' => 'https://example.com/test.jpg'
        }
      ]
    }
    
    # Simular o serviço
    service = Instagram::RichMessageService.new(message: message, rich_payload: rich_payload)
    
    # Testar apenas o método de verificação
    enabled = service.send(:rich_dashboard_enabled?)
    puts "Rich dashboard enabled: #{enabled}"
    
    if enabled
      puts "✅ Instagram Rich Message Service detectou a feature como habilitada"
    else
      puts "❌ Instagram Rich Message Service não detectou a feature como habilitada"
    end
    
  else
    puts "⚠️  Nenhuma conversa Instagram encontrada para a conta 3"
    puts "Criando conversa de teste..."
    
    # Verificar se existe um canal Instagram
    instagram_channel = account.instagram_channels.first
    if instagram_channel
      inbox = instagram_channel.inbox
      contact = account.contacts.first || account.contacts.create!(name: 'Teste', email: 'teste@example.com')
      conversation = account.conversations.create!(
        inbox: inbox,
        contact: contact,
        status: :open
      )
      puts "✅ Conversa de teste criada: #{conversation.id}"
    else
      puts "⚠️  Nenhum canal Instagram encontrado para a conta 3"
    end
  end
  
rescue => e
  puts "❌ Erro ao testar: #{e.message}"
  puts e.backtrace.first(3)
end

puts "\n=== Teste concluído ==="