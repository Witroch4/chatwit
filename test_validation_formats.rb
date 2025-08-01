# Teste específico para validação dos formatos BUTTON_TEMPLATE e QUICK_REPLIES
# Simula as validações que estão no InstagramResponseProcessor

puts "=== Testando Validações dos Formatos ==="

# Simular método validate_button_template
def validate_button_template(payload)
  puts "  Validando BUTTON_TEMPLATE..."
  puts "    template_type: #{payload['template_type']}"
  puts "    text presente: #{payload['text'] && !payload['text'].empty?}"
  puts "    buttons é array: #{payload['buttons'].is_a?(Array)}"
  puts "    buttons não vazio: #{payload['buttons']&.any?}"
  puts "    buttons <= 3: #{payload['buttons']&.length && payload['buttons'].length <= 3}"
  
  # Validação real
  return false unless payload['template_type'] == 'button'
  return false unless payload['text'] && !payload['text'].empty?
  return false unless payload['buttons'].is_a?(Array) && payload['buttons'].any? && payload['buttons'].length <= 3
  
  # Validar cada botão
  payload['buttons'].each_with_index do |button, index|
    puts "    Validando botão #{index}: #{button.inspect}"
    return false unless button.is_a?(Hash)
    return false unless button['type'] && button['title']
    
    case button['type']
    when 'postback'
      return false unless button['payload']
    when 'web_url'
      return false unless button['url']
    else
      return false
    end
  end
  
  true
end

# Simular método validate_quick_replies
def validate_quick_replies(payload)
  puts "  Validando QUICK_REPLIES..."
  puts "    text presente: #{payload['text'] && !payload['text'].empty?}"
  puts "    quick_replies é array: #{payload['quick_replies'].is_a?(Array)}"
  puts "    quick_replies não vazio: #{payload['quick_replies']&.any?}"
  puts "    quick_replies <= 13: #{payload['quick_replies']&.length && payload['quick_replies'].length <= 13}"
  
  # Validação real
  return false unless payload['text'] && !payload['text'].empty?
  return false unless payload['quick_replies'].is_a?(Array) && payload['quick_replies'].any? && payload['quick_replies'].length <= 13
  
  # Validar cada quick reply
  payload['quick_replies'].each_with_index do |quick_reply, index|
    puts "    Validando quick reply #{index}: #{quick_reply.inspect}"
    return false unless quick_reply.is_a?(Hash)
    return false unless quick_reply['content_type'] == 'text'
    return false unless quick_reply['title'] && !quick_reply['title'].empty?
    return false unless quick_reply['payload'] && !quick_reply['payload'].empty?
  end
  
  true
end

# Dados de teste
button_template_payload = {
  'template_type' => 'button',
  'text' => 'Olá! Gostaria de falar com um atendente?',
  'buttons' => [
    { 'type' => 'postback', 'title' => 'Falar com Atendente', 'payload' => 'human_handoff' },
    { 'type' => 'web_url', 'url' => 'https://seusite.com/ajuda', 'title' => 'Ver FAQ' }
  ]
}

quick_replies_payload = {
  'text' => 'Selecione o assunto do seu interesse:',
  'quick_replies' => [
    { 'content_type' => 'text', 'title' => 'Serviços', 'payload' => 'ver_servicos' },
    { 'content_type' => 'text', 'title' => 'Endereço', 'payload' => 'ver_endereco' }
  ]
}

# Testar BUTTON_TEMPLATE
puts "🧪 Testando BUTTON_TEMPLATE:"
button_valid = validate_button_template(button_template_payload)
puts "  Resultado: #{button_valid ? '✅ VÁLIDO' : '❌ INVÁLIDO'}"
puts

# Testar QUICK_REPLIES
puts "🧪 Testando QUICK_REPLIES:"
quick_valid = validate_quick_replies(quick_replies_payload)
puts "  Resultado: #{quick_valid ? '✅ VÁLIDO' : '❌ INVÁLIDO'}"
puts

puts "=== Resumo ==="
puts "BUTTON_TEMPLATE: #{button_valid ? '✅' : '❌'}"
puts "QUICK_REPLIES: #{quick_valid ? '✅' : '❌'}"
puts
puts "Se ambos estão válidos, o problema pode estar em outro lugar."
puts "=== Fim do Teste ==="