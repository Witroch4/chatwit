# Teste para verificar os 3 formatos de mensagens ricas
# Execute no Rails console: rails console

puts "=== Testando os 3 Formatos de Mensagens Ricas ==="
puts "Data: #{Time.now}"
puts

# Dados de teste para cada formato
test_formats = {
  'GENERIC_TEMPLATE' => {
    'message_format' => 'GENERIC_TEMPLATE',
    'payload' => {
      'template_type' => 'generic',
      'elements' => [
        {
          'title' => 'Dra. Amanda Sousa Advocacia',
          'subtitle' => 'Selecione uma das opções abaixo.',
          'image_url' => 'https://url.da.sua.imagem/aqui.png',
          'buttons' => [
            { 'type' => 'postback', 'title' => 'Ver Serviços', 'payload' => 'ver_servicos' },
            { 'type' => 'web_url', 'url' => 'https://seusite.com/servicos', 'title' => 'Abrir Site' }
          ]
        }
      ]
    }
  },
  
  'BUTTON_TEMPLATE' => {
    'message_format' => 'BUTTON_TEMPLATE',
    'payload' => {
      'template_type' => 'button',
      'text' => 'Olá! Gostaria de falar com um atendente?',
      'buttons' => [
        { 'type' => 'postback', 'title' => 'Falar com Atendente', 'payload' => 'human_handoff' },
        { 'type' => 'web_url', 'url' => 'https://seusite.com/ajuda', 'title' => 'Ver FAQ' }
      ]
    }
  },
  
  'QUICK_REPLIES' => {
    'message_format' => 'QUICK_REPLIES',
    'payload' => {
      'text' => 'Selecione o assunto do seu interesse:',
      'quick_replies' => [
        { 'content_type' => 'text', 'title' => 'Serviços', 'payload' => 'ver_servicos' },
        { 'content_type' => 'text', 'title' => 'Endereço', 'payload' => 'ver_endereco' }
      ]
    }
  }
}

# Simular validação de cada formato
test_formats.each do |format_name, data|
  puts "🧪 Testando formato: #{format_name}"
  puts "📋 Payload: #{data['payload'].inspect}"
  
  # Simular validação
  case format_name
  when 'GENERIC_TEMPLATE'
    valid = data['payload']['template_type'] == 'generic' && 
            data['payload']['elements'].is_a?(Array) && 
            data['payload']['elements'].any?
  when 'BUTTON_TEMPLATE'
    valid = data['payload']['template_type'] == 'button' && 
            !data['payload']['text'].nil? && !data['payload']['text'].empty? && 
            data['payload']['buttons'].is_a?(Array)
  when 'QUICK_REPLIES'
    valid = !data['payload']['text'].nil? && !data['payload']['text'].empty? && 
            data['payload']['quick_replies'].is_a?(Array)
  end
  
  puts valid ? "✅ Validação passou" : "❌ Validação falhou"
  puts
end

puts "=== Verificando Estruturas Finais ==="

# Simular como cada payload seria processado
test_formats.each do |format_name, data|
  puts "📤 #{format_name} - Estrutura final esperada:"
  
  case format_name
  when 'GENERIC_TEMPLATE', 'BUTTON_TEMPLATE'
    # Template format - vai dentro de attachment
    final_structure = {
      "recipient" => { "id" => "<IGSID>" },
      "message" => {
        "attachment" => {
          "type" => "template",
          "payload" => data['payload']
        }
      }
    }
  when 'QUICK_REPLIES'
    # Quick replies format - vai direto no message
    final_structure = {
      "recipient" => { "id" => "<IGSID>" },
      "messaging_type" => "RESPONSE",
      "message" => data['payload']
    }
  end
  
  puts "   #{final_structure.inspect}"
  puts
end

puts "✅ Teste de estruturas concluído!"
puts "=== Fim do Teste ==="