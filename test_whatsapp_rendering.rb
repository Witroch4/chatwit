#!/usr/bin/env ruby
# Script para testar se as mensagens WhatsApp estão sendo renderizadas corretamente

puts "=== TESTE DE RENDERIZAÇÃO DO WHATSAPP INTERACTIVE ==="
puts

# Verificar mensagens WhatsApp recentes
puts "1. Verificando mensagens WhatsApp recentes:"
whatsapp_messages = Message.joins(:conversation)
                          .joins('JOIN inboxes ON conversations.inbox_id = inboxes.id')
                          .where('inboxes.channel_type = ?', 'Channel::Whatsapp')
                          .where('messages.created_at > ?', 2.hours.ago)
                          .order(created_at: :desc)
                          .limit(10)

puts "   Mensagens WhatsApp encontradas (últimas 2 horas): #{whatsapp_messages.count}"

if whatsapp_messages.any?
  whatsapp_messages.each do |message|
    puts "   - ID: #{message.id}, Criada: #{message.created_at.strftime('%H:%M:%S')}"
    puts "     Conteúdo: #{message.content&.truncate(50)}"
    puts "     Content Type: #{message.content_type}"
    puts "     Message Type: #{message.message_type}"
    
    # Verificar se é mensagem interativa
    if message.content_type == 'integrations'
      puts "     ✅ Mensagem interativa - deve aparecer como WhatsAppInteractive.vue"
      
      # Verificar payloads necessários para renderização
      if message.content_attributes['whatsapp_interactive_payload']
        puts "       ✅ whatsapp_interactive_payload: presente"
        
        payload = message.content_attributes['whatsapp_interactive_payload']
        puts "       Tipo: #{payload['type']}"
        
        if payload['body'] && payload['body']['text']
          puts "       ✅ Body text: #{payload['body']['text'].truncate(30)}"
        else
          puts "       ❌ Body text: ausente"
        end
        
        if payload['header'] && payload['header']['type'] == 'image'
          puts "       ✅ Header image: #{payload['header']['image']['link']&.truncate(40)}"
        else
          puts "       ℹ️  Header image: não presente"
        end
        
        if payload['action'] && payload['action']['buttons']
          buttons_count = payload['action']['buttons'].length
          puts "       ✅ Botões: #{buttons_count}"
          
          payload['action']['buttons'].each_with_index do |button, index|
            title = button.dig('reply', 'title') || button['title'] || 'Sem título'
            puts "         Botão #{index + 1}: #{title}"
          end
        else
          puts "       ❌ Botões: ausentes"
        end
        
      else
        puts "       ❌ whatsapp_interactive_payload: ausente"
      end
      
      if message.content_attributes['interactive']
        puts "       ✅ interactive: presente (compatibilidade)"
      else
        puts "       ❌ interactive: ausente"
      end
      
      if message.content_attributes['interactive_payload']
        puts "       ✅ interactive_payload: presente (evita atualização)"
      else
        puts "       ❌ interactive_payload: ausente"
      end
      
    elsif message.content_type == 'text'
      puts "     ℹ️  Mensagem de texto simples"
    else
      puts "     ⚠️  Tipo desconhecido: #{message.content_type}"
    end
    
    # Verificar origem
    if message.additional_attributes['socialwise_flow_message']
      puts "     🔄 Origem: SocialWise Flow"
    else
      puts "     ❓ Origem: Desconhecida"
    end
    
    # Verificar se foi enviada
    if message.source_id.present?
      puts "     ✅ Enviada: source_id = #{message.source_id}"
    else
      puts "     ⚠️  Não enviada: source_id ausente"
    end
    
    puts
  end
else
  puts "   ℹ️  Nenhuma mensagem WhatsApp encontrada nas últimas 2 horas"
end

puts "2. Verificando estrutura esperada pelo WhatsAppInteractive.vue:"
puts "   O componente Vue.js procura por:"
puts "   - contentAttributes.whatsapp_interactive_payload ✓"
puts "   - contentAttributes.interactive (fallback) ✓"
puts "   - payload.body.text para o texto principal"
puts "   - payload.header.image.link para imagem do header"
puts "   - payload.action.buttons para os botões"
puts "   - payload.footer.text para o footer"
puts

puts "3. Verificando se mensagens estão sendo criadas com padrão Instagram:"
recent_socialwise_messages = Message.joins(:conversation)
                                   .joins('JOIN inboxes ON conversations.inbox_id = inboxes.id')
                                   .where('inboxes.channel_type = ?', 'Channel::Whatsapp')
                                   .where('messages.additional_attributes @> ?', { socialwise_flow_message: true }.to_json)
                                   .where('messages.created_at > ?', 1.hour.ago)
                                   .order(created_at: :desc)
                                   .limit(5)

puts "   Mensagens SocialWise Flow (última hora): #{recent_socialwise_messages.count}"

if recent_socialwise_messages.any?
  recent_socialwise_messages.each do |message|
    puts "   - ID: #{message.id}, Tipo: #{message.content_type}"
    puts "     Criada: #{message.created_at.strftime('%H:%M:%S')}"
    
    if message.content_type == 'integrations'
      puts "     ✅ Padrão Instagram aplicado corretamente"
      
      # Verificar se tem todos os payloads necessários
      required_attrs = ['whatsapp_interactive_payload', 'interactive', 'interactive_payload']
      missing_attrs = required_attrs.reject { |attr| message.content_attributes[attr].present? }
      
      if missing_attrs.empty?
        puts "     ✅ Todos os atributos necessários presentes"
      else
        puts "     ❌ Atributos ausentes: #{missing_attrs.join(', ')}"
      end
    else
      puts "     ❌ Não está usando padrão Instagram (content_type: #{message.content_type})"
    end
    puts
  end
else
  puts "   ℹ️  Nenhuma mensagem SocialWise Flow encontrada na última hora"
end

puts "=== DIAGNÓSTICO ==="
puts "✅ Se mensagens aparecem com:"
puts "   - content_type: 'integrations'"
puts "   - whatsapp_interactive_payload presente"
puts "   - Botões e texto corretos"
puts "   → Renderização deve estar funcionando"
puts
puts "❌ Se mensagens não aparecem ou somem:"
puts "   - Verificar logs do navegador (F12 → Console)"
puts "   - Verificar se WhatsAppInteractive.vue está sendo chamado"
puts "   - Verificar se há erros de JavaScript"
puts
puts "=== TESTE CONCLUÍDO ==="