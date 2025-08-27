#!/usr/bin/env ruby

# Test para identificar o problema na estrutura do payload do Instagram

puts "=== Teste de Estrutura do Payload Instagram ==="

# Payload que o SocialWise Flow recebe
socialwise_payload = {
  "instagram" => {
    "message_format" => "GENERIC_TEMPLATE",
    "template_type" => "generic",
    "elements" => [
      {
        "title" => "mandado de segurança",
        "buttons" => [
          {
            "type" => "postback",
            "title" => "atendimento",
            "payload" => "ig_btn_1756139332989_pm6hd9wau"
          }
        ],
        "image_url" => "https://objstoreapi.witdev.com.br/chatwit-social/1b2024eb-ecd3-486d-8629-57a1df029b08.png"
      }
    ]
  }
}

puts "\n1. Payload completo do SocialWise Flow:"
puts socialwise_payload.inspect

instagram_payload = socialwise_payload["instagram"]
puts "\n2. Payload extraído para Instagram:"
puts instagram_payload.inspect

puts "\n3. Estrutura atual:"
puts "   message_format: #{instagram_payload['message_format']}"
puts "   template_type: #{instagram_payload['template_type']}"
puts "   elements: #{instagram_payload['elements'] ? 'presente' : 'ausente'}"

puts "\n4. PROBLEMA IDENTIFICADO:"
puts "   O InstagramResponseProcessor.process espera:"
puts "   - socialwise_data['message_format']"
puts "   - socialwise_data['payload'] (com template_type e elements)"
puts ""
puts "   Mas está recebendo:"
puts "   - instagram_payload['message_format']"
puts "   - instagram_payload (direto, sem chave 'payload')"

puts "\n5. Estrutura correta deveria ser:"
correct_structure = {
  'message_format' => instagram_payload['message_format'],
  'payload' => {
    'template_type' => instagram_payload['template_type'],
    'elements' => instagram_payload['elements']
  }
}
puts correct_structure.inspect

puts "\n6. SOLUÇÃO:"
puts "   Modificar process_instagram_response para reestruturar o payload"
puts "   antes de chamar InstagramResponseProcessor.process"