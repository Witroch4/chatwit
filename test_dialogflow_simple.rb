# Script SIMPLES para testar somente o método detect_intent
# Execute no console Rails: rails console
# Cole este código

puts "🧪 TESTE SIMPLES - DETECT_INTENT"
puts "================================="

# Buscar dados existentes
hook = Hook.find_by(app_id: 'dialogflow')
contact = Contact.find_by(phone_number: "+558597550136")
inbox = Inbox.find_by(name: "witdev")

if hook && contact && inbox
  contact_inbox = ContactInbox.find_by(contact: contact, inbox: inbox)
  conversation = Conversation.find_by(contact_inbox: contact_inbox, inbox: inbox) if contact_inbox
  
  if conversation
    # Simular uma mensagem
    fake_message = OpenStruct.new(
      source_id: "WAID:TESTE#{Time.now.to_i}",
      content: "exibirpayload",
      conversation: conversation,
      sender: contact
    )
    
    # Criar o processor
    processor = Integrations::Dialogflow::ProcessorService.new(
      event_name: 'message.created',
      hook: hook,
      event_data: { message: fake_message }
    )
    
    puts "📞 Testando detect_intent diretamente..."
    
    begin
      # Testar o método detect_intent
      session_id = contact_inbox.source_id
      response = processor.send(:detect_intent, session_id, "exibirpayload")
      
      puts "✅ Método detect_intent executado com sucesso!"
      puts "📋 Resposta: #{response.class}"
      
    rescue => e
      puts "❌ ERRO no detect_intent: #{e.message}"
      puts "📋 Classe do erro: #{e.class}"
      puts "📋 Backtrace: #{e.backtrace.first(5).join("\n")}"
    end
    
    puts "\n🎯 Teste concluído!"
  else
    puts "❌ Conversa não encontrada"
  end
else
  puts "❌ Dados básicos não encontrados"
  puts "Hook: #{hook&.status}"
  puts "Contact: #{contact&.name}"
  puts "Inbox: #{inbox&.name}"
end 