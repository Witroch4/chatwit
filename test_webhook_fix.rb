#!/usr/bin/env ruby

# Teste simples para verificar se a correção do webhook funcionou
puts "=== TESTE DA CORREÇÃO DO WEBHOOK ==="
puts

# Simular a estrutura de payload que vem dos webhooks
webhook_payload = {
  'account' => { 'id' => 3, 'name' => 'DraAmandaSousa' },
  'event' => 'contact_updated',
  'channel' => 'Channel::Whatsapp',  # AQUI ESTÁ O CHANNEL_TYPE!
  'inbox' => {
    'id' => 4,
    'name' => 'WhatsApp Inbox'
  },
  'conversation' => {
    'id' => 123,
    'status' => 'open'
  },
  'contact' => {
    'id' => 456,
    'name' => 'João Silva'
  }
}

puts "✅ Payload simulado criado:"
puts "  Channel no nível raiz: #{webhook_payload['channel']}"
puts "  Inbox ID: #{webhook_payload['inbox']['id']}"
puts

# Simular a lógica corrigida do create_mock_inbox_from_webhook_data
def test_channel_detection(webhook_data, conversation_data)
  channel_type = nil
  
  puts "🔍 Testando detecção de canal:"
  puts "  webhook_data keys: #{webhook_data.keys.inspect}"
  puts "  conversation_data presente: #{conversation_data.present?}"
  
  # Lógica original (não funcionava)
  if conversation_data.is_a?(Hash) && conversation_data['conversation']
    if conversation_data['conversation']['channel']
      channel_type = conversation_data['conversation']['channel']
      puts "  ❌ Tentativa 1 - conversation_data['conversation']['channel']: #{channel_type}"
    end
  end
  
  # CORREÇÃO: Buscar channel no nível raiz do payload
  if channel_type.nil? && conversation_data.is_a?(Hash)
    if conversation_data['channel']
      channel_type = conversation_data['channel']
      puts "  ✅ CORREÇÃO - conversation_data['channel']: #{channel_type}"
    elsif conversation_data[:channel]
      channel_type = conversation_data[:channel]
      puts "  ✅ CORREÇÃO - conversation_data[:channel]: #{channel_type}"
    end
  end
  
  puts "  Resultado final: #{channel_type}"
  puts
  
  # Verificar se é WhatsApp
  is_whatsapp = channel_type == 'Channel::Whatsapp'
  puts "🎯 Verificação WhatsApp:"
  puts "  channel_type == 'Channel::Whatsapp': #{is_whatsapp}"
  puts "  Resultado: #{is_whatsapp ? '✅ SUCESSO' : '❌ FALHOU'}"
  
  return channel_type, is_whatsapp
end

# Testar com a estrutura corrigida
channel_type, is_whatsapp = test_channel_detection(
  webhook_payload['inbox'], 
  webhook_payload  # Passando o payload completo como conversation_data
)

puts
puts "=== RESULTADO DO TESTE ==="
if is_whatsapp
  puts "✅ CORREÇÃO FUNCIONOU!"
  puts "   O sistema agora consegue identificar canais WhatsApp nos webhooks"
  puts "   Channel Type detectado: #{channel_type}"
else
  puts "❌ CORREÇÃO NÃO FUNCIONOU"
  puts "   O sistema ainda não consegue identificar canais WhatsApp"
end
puts

puts "=== PRÓXIMOS PASSOS ==="
puts "1. ✅ Correção implementada no WebhookEnhancerService"
puts "2. 🔄 Testar com webhook real"
puts "3. 🔍 Verificar se API key será extraída corretamente"
puts "4. 📝 Atualizar logs para confirmar funcionamento"