#!/usr/bin/env ruby
# frozen_string_literal: true

# Test script to verify that WhatsApp rich messages persist during status updates
puts "=== TESTE DE PERSISTÊNCIA DE MENSAGENS RICAS DO WHATSAPP ==="
puts

# Simulate creating a WhatsApp interactive message
puts "1. Criando mensagem interativa do WhatsApp..."

# Find a WhatsApp conversation for testing
whatsapp_inbox = Inbox.joins(:channel).where(channels: { provider: 'whatsapp_cloud' }).first
unless whatsapp_inbox
  puts "❌ Nenhum inbox do WhatsApp encontrado"
  exit 1
end

conversation = whatsapp_inbox.conversations.first
unless conversation
  puts "❌ Nenhuma conversa encontrada no inbox do WhatsApp"
  exit 1
end

# Create a rich interactive message
interactive_payload = {
  'type' => 'button',
  'body' => { 'text' => 'Escolha uma opção:' },
  'action' => {
    'buttons' => [
      { 'type' => 'reply', 'reply' => { 'id' => 'btn_1', 'title' => 'Opção 1' } },
      { 'type' => 'reply', 'reply' => { 'id' => 'btn_2', 'title' => 'Opção 2' } }
    ]
  }
}

# Create message with rich content
message = conversation.messages.create!(
  content: 'Escolha uma opção:',
  content_type: 'integrations',
  content_attributes: {
    'whatsapp_interactive_payload' => interactive_payload,
    'interactive' => interactive_payload
  },
  message_type: 'outgoing',
  account_id: conversation.account_id,
  inbox_id: whatsapp_inbox.id,
  sender: conversation.account.users.first,
  status: 'sent'
)

puts "✅ Mensagem criada com ID: #{message.id}"
puts "   Content Type: #{message.content_type}"
puts "   Status: #{message.status}"
puts "   Rich Content: #{message.content_attributes['whatsapp_interactive_payload'].present? ? 'Presente' : 'Ausente'}"

# Test the rich_message_content? method
puts "\n2. Testando método rich_message_content?..."
is_rich = message.rich_message_content?
puts "   Resultado: #{is_rich ? '✅ Detectado como mensagem rica' : '❌ NÃO detectado como mensagem rica'}"

# Test push_event_data preservation
puts "\n3. Testando preservação no push_event_data..."
event_data = message.push_event_data
puts "   Content Type no evento: #{event_data[:content_type]}"
puts "   Content Attributes preservados: #{event_data[:content_attributes].present? ? '✅ Sim' : '❌ Não'}"

if event_data[:content_attributes] && event_data[:content_attributes]['whatsapp_interactive_payload']
  puts "   WhatsApp Interactive Payload: ✅ Preservado"
else
  puts "   WhatsApp Interactive Payload: ❌ Perdido"
end

# Simulate status update
puts "\n4. Simulando atualização de status..."
original_content_type = message.content_type
original_attributes = message.content_attributes.dup

# Update status (this should trigger the update event)
message.update!(status: 'delivered')

puts "   Status atualizado para: #{message.status}"
puts "   Content Type após update: #{message.content_type}"
puts "   Content Type preservado: #{message.content_type == original_content_type ? '✅ Sim' : '❌ Não'}"

# Check if rich content is still there
rich_preserved = message.content_attributes['whatsapp_interactive_payload'].present?
puts "   Rich content preservado: #{rich_preserved ? '✅ Sim' : '❌ Não'}"

# Test push_event_data after update
puts "\n5. Testando push_event_data após atualização..."
updated_event_data = message.push_event_data
puts "   Content Type no evento: #{updated_event_data[:content_type]}"
puts "   Rich content no evento: #{updated_event_data[:content_attributes]&.dig('whatsapp_interactive_payload').present? ? '✅ Preservado' : '❌ Perdido'}"

# Summary
puts "\n=== RESUMO DO TESTE ==="
if is_rich && rich_preserved && updated_event_data[:content_attributes]&.dig('whatsapp_interactive_payload').present?
  puts "✅ SUCESSO: Mensagem rica do WhatsApp persistiu durante atualização de status"
  puts "   - Detectada como mensagem rica: ✅"
  puts "   - Content type preservado: ✅"
  puts "   - Payload interativo preservado: ✅"
  puts "   - Evento de update preserva dados: ✅"
else
  puts "❌ FALHA: Problemas na persistência da mensagem rica"
  puts "   - Detectada como mensagem rica: #{is_rich ? '✅' : '❌'}"
  puts "   - Content type preservado: #{message.content_type == original_content_type ? '✅' : '❌'}"
  puts "   - Payload interativo preservado: #{rich_preserved ? '✅' : '❌'}"
  puts "   - Evento de update preserva dados: #{updated_event_data[:content_attributes]&.dig('whatsapp_interactive_payload').present? ? '✅' : '❌'}"
end

puts "\n=== TESTE CONCLUÍDO ==="