# Script para testar Dialogflow no console Rails
# Execute: rails console
# Depois cole este código

puts "==========================================".colorize(:cyan)
puts "  TESTE DIALOGFLOW - CONSOLE RAILS"
puts "==========================================".colorize(:cyan)

# Encontrar dados existentes
inbox = Inbox.find_by(name: "witdev")
contact = Contact.find_by(phone_number: "+558597550136")
dialogflow_hook = Integrations::Hook.find_by(app_id: 'dialogflow')
socialwise_hook = Integrations::Hook.find_by(app_id: 'socialwise_chatwit')

puts "📊 Verificando dados existentes..."
puts "✅ Inbox: #{inbox&.name} (ID: #{inbox&.id})"
puts "✅ Contact: #{contact&.name} (ID: #{contact&.id})"
puts "✅ Hook Dialogflow: #{dialogflow_hook&.status}"
puts "✅ Hook Socialwise: #{socialwise_hook&.status} (enabled: #{socialwise_hook&.settings&.dig('enabled')})"

if inbox && contact && dialogflow_hook && socialwise_hook
  puts "\n🚀 Iniciando teste..."
  
  # Buscar conversa existente
  contact_inbox = ContactInbox.find_by(contact: contact, inbox: inbox)
  conversation = Conversation.find_by(contact_inbox: contact_inbox, inbox: inbox) if contact_inbox
  
  if conversation
    puts "✅ Conversa encontrada: #{conversation.id}"
    
    # Criar mensagem de teste
    wamid = "WAID:CONSOLE#{Time.now.to_i}#{rand(1000)}"
    message = Message.create!(
      account: inbox.account,
      inbox: inbox,
      conversation: conversation,
      message_type: :incoming,
      content: "exibirpayload",
      source_id: wamid,
      sender: contact,
      content_type: :text
    )
    
    puts "📨 Mensagem criada: ID #{message.id}, WAMID: #{message.source_id}"
    
    # Testar processamento
    begin
      event_data = { message: message }
      processor = Integrations::Dialogflow::ProcessorService.new(
        event_name: 'message.created',
        hook: dialogflow_hook,
        event_data: event_data
      )
      
      puts "🔄 Processando com Dialogflow..."
      session_id = contact_inbox.source_id
      response = processor.send(:get_response, session_id, "exibirpayload")
      
      if response
        puts "✅ Resposta recebida do Dialogflow!"
        puts "📋 Resposta: #{response.inspect}"
      else
        puts "⚠️  Nenhuma resposta recebida do Dialogflow"
      end
      
    rescue => e
      puts "❌ Erro: #{e.message}"
      puts "📋 Backtrace: #{e.backtrace.first(3).join('\n')}"
    end
    
    puts "\n🎯 Teste concluído!"
  else
    puts "❌ Conversa não encontrada"
  end
else
  puts "❌ Dados necessários não encontrados"
end 