#!/usr/bin/env ruby
# Script para testar a correção das mensagens ricas do WhatsApp

require 'json'
require 'ostruct'

puts "=== TESTE DA CORREÇÃO DAS MENSAGENS RICAS DO WHATSAPP ==="
puts

# Simular payload do SocialWise Flow com mensagem interativa
whatsapp_payload = {
  'type' => 'interactive',
  'interactive' => {
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
}

puts "1. Payload de teste:"
puts JSON.pretty_generate(whatsapp_payload)
puts

# Testar os métodos auxiliares
processor = Integrations::SocialwiseFlow::ProcessorService.new(
  event_name: 'message.created',
  hook: OpenStruct.new(settings: {}),
  event_data: {}
)

puts "2. Testando should_use_cards_rendering?:"
should_use_cards = processor.send(:should_use_cards_rendering?, whatsapp_payload)
puts "   Resultado: #{should_use_cards}"
puts

if should_use_cards
  puts "3. Testando convert_whatsapp_to_cards_format:"
  cards_format = processor.send(:convert_whatsapp_to_cards_format, whatsapp_payload)
  puts "   Resultado:"
  puts JSON.pretty_generate(cards_format)
  puts
  
  puts "4. Verificando estrutura de cards:"
  items = cards_format['items']
  if items && items.length > 0
    item = items.first
    puts "   ✓ Título: #{item['title']}"
    puts "   ✓ Descrição: #{item['description']}"
    puts "   ✓ URL da imagem: #{item['media_url']}"
    puts "   ✓ Número de ações: #{item['actions']&.length || 0}"
    
    if item['actions']
      item['actions'].each_with_index do |action, index|
        puts "     Ação #{index + 1}: #{action['text']} (#{action['type']})"
      end
    end
  else
    puts "   ❌ Nenhum item de card encontrado"
  end
else
  puts "3. Mensagem será renderizada como WhatsApp Interactive (não como cards)"
end

puts
puts "=== TESTE CONCLUÍDO ==="