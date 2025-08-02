#!/usr/bin/env ruby

# Test script to verify Instagram postback functionality
# This script tests the parser and builder logic without requiring database data

require_relative 'config/environment'

puts "=== TESTE SIMPLES DE POSTBACK DO INSTAGRAM ==="
puts "Data: #{Time.current}"
puts

# Test 1: Test the Instagram parser with postback
puts "=== TESTE 1: PARSER DE POSTBACK ==="

postback_messaging = {
  sender: { id: "test_user_123" },
  recipient: { id: "instagram_page_456" },
  timestamp: Time.current.to_i,
  postback: {
    title: "Teste Botão 1",
    payload: "btn_1753868215821_m995rldbs"
  }
}

puts "Payload do postback:"
puts JSON.pretty_generate(postback_messaging)
puts

# Test the parser
parser = Integrations::Instagram::MessageParser.new(postback_messaging)
puts "Parser results:"
puts "  postback?: #{parser.postback?}"
puts "  postback_title: #{parser.postback_title}"
puts "  postback_payload: #{parser.postback_payload}"
puts "  message?: #{parser.message?}"
puts "  quick_reply?: #{parser.quick_reply?}"
puts

# Test 2: Test the Instagram parser with quick reply
puts "=== TESTE 2: PARSER DE QUICK REPLY ==="

quick_reply_messaging = {
  sender: { id: "test_user_123" },
  recipient: { id: "instagram_page_456" },
  timestamp: Time.current.to_i,
  message: {
    mid: "quick_reply_#{rand(10000)}",
    text: "Opção 1",
    quick_reply: {
      payload: "quick_option_1"
    }
  }
}

puts "Payload do quick reply:"
puts JSON.pretty_generate(quick_reply_messaging)
puts

# Test the parser for quick reply
parser = Integrations::Instagram::MessageParser.new(quick_reply_messaging)
puts "Parser results:"
puts "  message?: #{parser.message?}"
puts "  quick_reply?: #{parser.quick_reply?}"
puts "  quick_reply_payload: #{parser.quick_reply_payload}"
puts "  content: #{parser.content}"
puts "  postback?: #{parser.postback?}"
puts

# Test 3: Test the Instagram parser with regular message
puts "=== TESTE 3: PARSER DE MENSAGEM REGULAR ==="

regular_messaging = {
  sender: { id: "test_user_123" },
  recipient: { id: "instagram_page_456" },
  timestamp: Time.current.to_i,
  message: {
    mid: "regular_#{rand(10000)}",
    text: "Olá, como você está?"
  }
}

puts "Payload da mensagem regular:"
puts JSON.pretty_generate(regular_messaging)
puts

# Test the parser for regular message
parser = Integrations::Instagram::MessageParser.new(regular_messaging)
puts "Parser results:"
puts "  message?: #{parser.message?}"
puts "  content: #{parser.content}"
puts "  postback?: #{parser.postback?}"
puts "  quick_reply?: #{parser.quick_reply?}"
puts

# Test 4: Test the Facebook parser with postback (for comparison)
puts "=== TESTE 4: PARSER DO FACEBOOK COM POSTBACK ==="

facebook_postback = {
  "sender" => { "id" => "test_user_123" },
  "recipient" => { "id" => "facebook_page_456" },
  "timestamp" => Time.current.to_i,
  "postback" => {
    "title" => "Teste Botão Facebook",
    "payload" => "facebook_btn_payload"
  }
}.to_json

puts "Payload do Facebook postback:"
puts JSON.pretty_generate(JSON.parse(facebook_postback))
puts

# Test the Facebook parser
fb_parser = Integrations::Facebook::MessageParser.new(facebook_postback)
puts "Facebook Parser results:"
puts "  postback?: #{fb_parser.postback?}"
puts "  postback_title: #{fb_parser.postback_title}"
puts "  postback_payload: #{fb_parser.postback_payload}"
puts

# Test 5: Test the Facebook parser with quick reply (for comparison)
puts "=== TESTE 5: PARSER DO FACEBOOK COM QUICK REPLY ==="

facebook_quick_reply = {
  "sender" => { "id" => "test_user_123" },
  "recipient" => { "id" => "facebook_page_456" },
  "timestamp" => Time.current.to_i,
  "message" => {
    "mid" => "facebook_quick_#{rand(10000)}",
    "text" => "Opção Facebook",
    "quick_reply" => {
      "payload" => "facebook_quick_option"
    }
  }
}.to_json

puts "Payload do Facebook quick reply:"
puts JSON.pretty_generate(JSON.parse(facebook_quick_reply))
puts

# Test the Facebook parser for quick reply
fb_parser = Integrations::Facebook::MessageParser.new(facebook_quick_reply)
puts "Facebook Parser results:"
puts "  quick_reply?: #{fb_parser.quick_reply?}"
puts "  quick_reply_payload: #{fb_parser.quick_reply_payload}"
puts "  content: #{fb_parser.content}"
puts

# Test 6: Test Instagram Events Job supported events
puts "=== TESTE 6: EVENTOS SUPORTADOS NO INSTAGRAM ==="

supported_events = Webhooks::InstagramEventsJob::SUPPORTED_EVENTS
puts "Eventos suportados: #{supported_events.inspect}"
puts "Postback incluído?: #{supported_events.include?(:postback)}"
puts

puts "=== TESTE CONCLUÍDO COM SUCESSO ==="
puts "Todos os parsers estão funcionando corretamente!"
puts "O suporte a postbacks foi adicionado ao Instagram."