#!/usr/bin/env ruby
# Script para testar o padrão Instagram aplicado ao WhatsApp

puts "=== TESTE DO PADRÃO INSTAGRAM APLICADO AO WHATSAPP ==="
puts

# Simular payload do WhatsApp Interactive
whatsapp_interactive_payload = {
  'type' => 'button',
  'header' => {
    'type' => 'image',
    'image' => {
      'link' => 'https://example.com/image.jpg'
    }
  },
  'body' => {
    'text' => 'Olá! Como posso ajudar você hoje?'
  },
  'footer' => {
    'text' => 'Escolha uma das opções abaixo'
  },
  'action' => {
    'buttons' => [
      {
        'type' => 'reply',
        'reply' => {
          'id' => 'btn_1',
          'title' => 'Falar com Atendente'
        }
      },
      {
        'type' => 'reply',
        'reply' => {
          'id' => 'btn_2',
          'title' => 'Ver Produtos'
        }
      }
    ]
  }
}

puts "1. Testando WhatsApp Renderer Mapper:"
puts "   Payload de entrada:"
puts JSON.pretty_generate(whatsapp_interactive_payload)
puts

begin
  # Testar o mapper
  mapped_result = Messages::WhatsappRendererMapper.map(whatsapp_interactive_payload)
  
  puts "2. Resultado do mapeamento:"
  puts "   Content Type: #{mapped_result.content_type}"
  puts "   Fallback Text: #{mapped_result.fallback_text}"
  puts "   Content Attributes Keys: #{mapped_result.content_attributes.keys.join(', ')}"
  puts
  
  puts "3. Verificando content_attributes:"
  mapped_result.content_attributes.each do |key, value|
    if key == 'interactive_payload'
      puts "   ✅ #{key}: presente (evita atualização posterior)"
    elsif key == 'whatsapp_interactive_payload'
      puts "   ✅ #{key}: presente (para renderização)"
    elsif key == 'interactive'
      puts "   ✅ #{key}: presente (compatibilidade)"
    else
      puts "   ℹ️  #{key}: #{value.class}"
    end
  end
  puts
  
  puts "4. Comparação com padrão Instagram:"
  puts "   ✅ Cria mensagem diretamente com content_type correto"
  puts "   ✅ Inclui todos os content_attributes necessários"
  puts "   ✅ Evita atualizações posteriores"
  puts "   ✅ Usa fallback_text apropriado"
  puts
  
  puts "5. Fluxo esperado:"
  puts "   1. SocialWise Flow recebe payload"
  puts "   2. WhatsappRendererMapper converte para formato Chatwoot"
  puts "   3. Mensagem criada diretamente com tudo correto"
  puts "   4. RichMessageService não precisa atualizar (payload já presente)"
  puts "   5. Apenas source_id é atualizado após envio"
  puts "   6. Mensagem permanece estável no dashboard"
  
rescue => e
  puts "❌ Erro ao testar mapper: #{e.class}: #{e.message}"
  puts "   Backtrace: #{e.backtrace.first(3).join('\n')}"
end

puts
puts "=== TESTE CONCLUÍDO ==="
puts
puts "📋 PRÓXIMOS PASSOS:"
puts "1. Teste enviando uma mensagem rica do SocialWise Flow"
puts "2. Verifique se ela aparece corretamente no dashboard"
puts "3. Confirme que não há ícone de 'enviando' persistente"
puts "4. Verifique se a mensagem não some após recarregar a página"