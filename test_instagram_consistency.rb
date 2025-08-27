#!/usr/bin/env ruby
# Script para testar a consistência das mensagens ricas do Instagram

puts "=== TESTE DE CONSISTÊNCIA DAS MENSAGENS RICAS DO INSTAGRAM ==="
puts

# Verificar mensagens recentes do Instagram
puts "1. Verificando mensagens Instagram recentes:"
instagram_messages = Message.joins(:conversation)
                           .joins('JOIN inboxes ON conversations.inbox_id = inboxes.id')
                           .where('inboxes.channel_type = ?', 'Channel::FacebookPage')
                           .where('conversations.additional_attributes @> ?', { type: 'instagram_direct_message' }.to_json)
                           .where('messages.created_at > ?', 2.hours.ago)
                           .order(created_at: :desc)
                           .limit(10)

puts "   Mensagens Instagram encontradas (últimas 2 horas): #{instagram_messages.count}"

if instagram_messages.any?
  instagram_messages.each do |message|
    puts "   - ID: #{message.id}, Criada: #{message.created_at.strftime('%H:%M:%S')}"
    puts "     Conteúdo: #{message.content&.truncate(50)}"
    puts "     Content Type: #{message.content_type}"
    puts "     Message Type: #{message.message_type}"
    
    # Verificar se é mensagem rica
    if message.content_type == 'cards'
      puts "     ✅ Mensagem rica (cards) - deve aparecer como RichCards.vue"
      
      if message.content_attributes['items']&.any?
        items_count = message.content_attributes['items'].length
        puts "       Cards: #{items_count}"
        
        message.content_attributes['items'].each_with_index do |item, index|
          puts "         Card #{index + 1}: #{item['title']&.truncate(30)}"
          puts "           Ações: #{item['actions']&.length || 0}"
          puts "           Imagem: #{item['media_url'] ? 'Sim' : 'Não'}"
        end
      end
    elsif message.content_type == 'input_select'
      puts "     ✅ Quick Replies - deve aparecer como QuickReplies.vue"
      
      if message.content_attributes['items']&.any?
        items_count = message.content_attributes['items'].length
        puts "       Quick Replies: #{items_count}"
      end
    elsif message.content_type == 'integrations'
      puts "     ⚠️  Integrations - pode ser mensagem rica não processada corretamente"
    else
      puts "     ℹ️  Mensagem de texto simples"
    end
    
    # Verificar origem
    if message.additional_attributes['socialwise_flow_message']
      puts "     🔄 Origem: SocialWise Flow"
    elsif message.sender&.type == 'agent_bot'
      puts "     🤖 Origem: Dialogflow (provavelmente)"
    else
      puts "     👤 Origem: Agente/Usuário"
    end
    
    puts
  end
else
  puts "   ℹ️  Nenhuma mensagem Instagram encontrada nas últimas 2 horas"
end

puts "2. Verificando mensagens ricas específicas do Instagram:"
rich_instagram_messages = Message.joins(:conversation)
                                .joins('JOIN inboxes ON conversations.inbox_id = inboxes.id')
                                .where('inboxes.channel_type = ?', 'Channel::FacebookPage')
                                .where('conversations.additional_attributes @> ?', { type: 'instagram_direct_message' }.to_json)
                                .where(content_type: ['cards', 'input_select'])
                                .where('messages.created_at > ?', 24.hours.ago)
                                .order(created_at: :desc)
                                .limit(5)

puts "   Mensagens ricas encontradas (últimas 24 horas): #{rich_instagram_messages.count}"

if rich_instagram_messages.any?
  rich_instagram_messages.each do |message|
    puts "   - ID: #{message.id}, Tipo: #{message.content_type}"
    puts "     Criada: #{message.created_at.strftime('%d/%m %H:%M:%S')}"
    puts "     Conteúdo: #{message.content&.truncate(40)}"
    
    # Analisar estrutura
    if message.content_type == 'cards' && message.content_attributes['items']
      puts "     ✅ Cards estruturados corretamente"
      puts "       Número de cards: #{message.content_attributes['items'].length}"
    elsif message.content_type == 'input_select' && message.content_attributes['items']
      puts "     ✅ Quick Replies estruturados corretamente"
      puts "       Número de opções: #{message.content_attributes['items'].length}"
    else
      puts "     ❌ Estrutura pode estar incorreta"
    end
    puts
  end
else
  puts "   ℹ️  Nenhuma mensagem rica Instagram encontrada nas últimas 24 horas"
end

puts "3. Comparando com mensagens do Dialogflow:"
dialogflow_messages = Message.joins(:conversation)
                            .joins('JOIN inboxes ON conversations.inbox_id = inboxes.id')
                            .where('inboxes.channel_type = ?', 'Channel::FacebookPage')
                            .where('conversations.additional_attributes @> ?', { type: 'instagram_direct_message' }.to_json)
                            .where(content_type: ['cards', 'input_select'])
                            .where(sender_type: 'agent_bot')
                            .where('messages.created_at > ?', 24.hours.ago)
                            .order(created_at: :desc)
                            .limit(3)

puts "   Mensagens ricas do Dialogflow (últimas 24 horas): #{dialogflow_messages.count}"

if dialogflow_messages.any?
  dialogflow_messages.each do |message|
    puts "   - ID: #{message.id}, Tipo: #{message.content_type}"
    puts "     Sender: #{message.sender&.type || 'N/A'}"
    puts "     Estrutura: #{message.content_attributes.keys.join(', ')}"
    puts
  end
end

puts "=== ANÁLISE ==="
puts "✅ Bons sinais:"
puts "   - SocialWise Flow usa o mesmo InstagramResponseProcessor do Dialogflow"
puts "   - Mensagens devem ter content_type 'cards' ou 'input_select'"
puts "   - Estrutura deve ser consistente entre ambos os fluxos"
puts
puts "⚠️  Possíveis problemas:"
puts "   - Mensagens com content_type 'integrations' podem não estar sendo processadas"
puts "   - Falta de mensagens ricas pode indicar problema no processamento"
puts "   - Diferenças na estrutura entre Dialogflow e SocialWise Flow"
puts
puts "=== TESTE CONCLUÍDO ==="