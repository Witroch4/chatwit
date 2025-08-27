#!/usr/bin/env ruby
# Script para testar a estabilidade das mensagens ricas do WhatsApp

puts "=== TESTE DE ESTABILIDADE DAS MENSAGENS RICAS ==="
puts

# Verificar mensagens recentes com content_type 'integrations' do WhatsApp
puts "1. Verificando mensagens WhatsApp Interactive recentes:"
whatsapp_messages = Message.joins(:conversation)
                          .joins('JOIN inboxes ON conversations.inbox_id = inboxes.id')
                          .where('inboxes.channel_type = ?', 'Channel::Whatsapp')
                          .where(content_type: 'integrations')
                          .where('messages.created_at > ?', 2.hours.ago)
                          .order(created_at: :desc)
                          .limit(10)

puts "   Mensagens encontradas (últimas 2 horas): #{whatsapp_messages.count}"

if whatsapp_messages.any?
  whatsapp_messages.each do |message|
    puts "   - ID: #{message.id}, Criada: #{message.created_at.strftime('%H:%M:%S')}"
    puts "     Conteúdo: #{message.content&.truncate(50)}"
    puts "     Content Type: #{message.content_type}"
    
    # Verificar flags de proteção
    if message.additional_attributes['skip_send_reply']
      puts "     ✅ skip_send_reply: true (evita duplicação)"
    else
      puts "     ❌ skip_send_reply: false ou ausente"
    end
    
    if message.additional_attributes['socialwise_flow_message']
      puts "     ✅ socialwise_flow_message: true (origem identificada)"
    else
      puts "     ⚠️  socialwise_flow_message: ausente"
    end
    
    if message.additional_attributes['preserve_content']
      puts "     ✅ preserve_content: true (proteção ativa)"
    else
      puts "     ⚠️  preserve_content: ausente"
    end
    
    # Verificar payloads
    if message.content_attributes['whatsapp_interactive_payload']
      puts "     ✅ whatsapp_interactive_payload: presente"
    else
      puts "     ❌ whatsapp_interactive_payload: ausente"
    end
    
    if message.content_attributes['interactive_payload']
      puts "     ✅ interactive_payload: presente (evita atualização)"
    else
      puts "     ❌ interactive_payload: ausente (pode causar atualização)"
    end
    
    # Verificar se tem source_id (foi enviada)
    if message.source_id.present?
      puts "     ✅ source_id: #{message.source_id} (mensagem enviada)"
    else
      puts "     ⚠️  source_id: ausente (não enviada ou falhou)"
    end
    
    puts
  end
else
  puts "   ℹ️  Nenhuma mensagem WhatsApp Interactive encontrada nas últimas 2 horas"
end

puts "2. Verificando atualizações recentes de mensagens:"
updated_messages = Message.joins(:conversation)
                         .joins('JOIN inboxes ON conversations.inbox_id = inboxes.id')
                         .where('inboxes.channel_type = ?', 'Channel::Whatsapp')
                         .where(content_type: 'integrations')
                         .where('messages.updated_at > messages.created_at')
                         .where('messages.created_at > ?', 2.hours.ago)
                         .order(updated_at: :desc)
                         .limit(5)

puts "   Mensagens atualizadas após criação: #{updated_messages.count}"

if updated_messages.any?
  updated_messages.each do |message|
    time_diff = (message.updated_at - message.created_at).round(2)
    puts "   - ID: #{message.id}"
    puts "     Criada: #{message.created_at.strftime('%H:%M:%S')}"
    puts "     Atualizada: #{message.updated_at.strftime('%H:%M:%S')} (+#{time_diff}s)"
    puts "     Diferença: #{time_diff} segundos"
    
    if time_diff < 5
      puts "     ✅ Atualização rápida (provavelmente source_id)"
    else
      puts "     ⚠️  Atualização tardia (pode indicar problema)"
    end
    puts
  end
else
  puts "   ✅ Nenhuma mensagem foi atualizada após criação (bom sinal!)"
end

puts "3. Verificando logs de erro recentes:"
puts "   💡 Para verificar erros, execute:"
puts "   tail -100 log/development.log | grep -i 'SOCIALWISE-FLOW.*ERROR'"
puts

puts "=== RESUMO ==="
puts "✅ Mensagens devem ter:"
puts "   - skip_send_reply: true"
puts "   - socialwise_flow_message: true"
puts "   - whatsapp_interactive_payload: presente"
puts "   - interactive_payload: presente"
puts "   - source_id: presente (após envio)"
puts
puts "❌ Problemas indicam:"
puts "   - Muitas atualizações após criação"
puts "   - Payloads ausentes"
puts "   - Flags de proteção ausentes"
puts
puts "=== TESTE CONCLUÍDO ==="