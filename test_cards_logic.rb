#!/usr/bin/env ruby
# Script para testar a lógica de conversão para cards

require 'json'

puts "=== TESTE DA LÓGICA DE CONVERSÃO PARA CARDS ==="
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

# Implementar a lógica de teste
def should_use_cards_rendering?(whatsapp_payload)
  return false unless whatsapp_payload['type'] == 'interactive'
  
  interactive = whatsapp_payload['interactive']
  return false unless interactive
  
  # Usar cards se tiver header com imagem ou se for do tipo button com múltiplos botões
  has_image_header = interactive.dig('header', 'type') == 'image'
  is_button_template = interactive['type'] == 'button'
  has_multiple_buttons = interactive.dig('action', 'buttons')&.length.to_i > 1
  
  # Critérios para usar cards:
  # 1. Tem header com imagem
  # 2. É template de botão com múltiplos botões (mais visual como cards)
  result = has_image_header || (is_button_template && has_multiple_buttons)
  
  puts "   Critérios: image_header=#{has_image_header}, button_template=#{is_button_template}, multiple_buttons=#{has_multiple_buttons}"
  
  result
end

def convert_whatsapp_to_cards_format(whatsapp_payload)
  interactive = whatsapp_payload['interactive']
  
  # Extrair informações básicas
  title = interactive.dig('body', 'text') || interactive.dig('header', 'text') || ''
  description = interactive.dig('footer', 'text') || ''
  media_url = interactive.dig('header', 'image', 'link')
  
  # Converter botões para actions
  actions = []
  if interactive['type'] == 'button' && interactive.dig('action', 'buttons')
    interactive['action']['buttons'].each do |button|
      actions << {
        'type' => 'postback',
        'text' => button.dig('reply', 'title') || button['title'] || 'Botão',
        'payload' => button.dig('reply', 'id') || button['id'] || "button_#{actions.length + 1}"
      }
    end
  end
  
  # Criar estrutura de cards
  card_item = {
    'title' => title,
    'description' => description,
    'actions' => actions
  }
  
  # Adicionar media_url se existir
  card_item['media_url'] = media_url if media_url && !media_url.empty?
  
  cards_attributes = {
    'items' => [card_item],
    'whatsapp_interactive_source' => true,
    'original_interactive_payload' => interactive
  }
  
  cards_attributes
end

puts "2. Testando should_use_cards_rendering?:"
should_use_cards = should_use_cards_rendering?(whatsapp_payload)
puts "   Resultado: #{should_use_cards}"
puts

if should_use_cards
  puts "3. Testando convert_whatsapp_to_cards_format:"
  cards_format = convert_whatsapp_to_cards_format(whatsapp_payload)
  puts "   Resultado:"
  puts JSON.pretty_generate(cards_format)
  puts
  
  puts "4. Verificando estrutura de cards:"
  items = cards_format['items']
  if items && items.length > 0
    item = items.first
    puts "   ✓ Título: '#{item['title']}'"
    puts "   ✓ Descrição: '#{item['description']}'"
    puts "   ✓ URL da imagem: '#{item['media_url']}'"
    puts "   ✓ Número de ações: #{item['actions']&.length || 0}"
    
    if item['actions']
      item['actions'].each_with_index do |action, index|
        puts "     Ação #{index + 1}: '#{action['text']}' (#{action['type']}) -> #{action['payload']}"
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