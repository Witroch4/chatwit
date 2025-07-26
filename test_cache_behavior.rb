#!/usr/bin/env ruby

require_relative 'config/environment'

puts "=== TESTE DE COMPORTAMENTO DO CACHE SOCIALWISE ==="

# Simular o payload real
real_webhook_payload = {
  "account" => {"id" => 3, "name" => "DraAmandaSousa"},
  "content_attributes" => {},
  "content_type" => "text",
  "content" => nil,
  "conversation" => {
    "channel" => "Channel::Whatsapp",
    "id" => 1778,
    "inbox_id" => 4,
    "status" => "pending",
    "created_at" => 1753402911,
    "updated_at" => 1753521674.057222,
    "meta" => {
      "sender" => {
        "id" => 1447,
        "name" => "Witalo Rocha",
        "phone_number" => "+558597550136",
        "email" => nil,
        "custom_attributes" => {}
      }
    }
  },
  "id" => 32892,
  "inbox" => {"id" => 4, "name" => "WhatsApp - ANA"},
  "message_type" => "incoming",
  "sender" => {
    "id" => 1447,
    "name" => "Witalo Rocha",
    "phone_number" => "+558597550136",
    "custom_attributes" => {}
  },
  "source_id" => "wamid.HBgMNTU4NTk3NTUwMTM2FQIAEhgUM0E3REYyMDA4NTVENTkzNzQ3NEYA",
  "event" => "message_created"
}

account = OpenStruct.new(id: 3, name: "DraAmandaSousa")
service = Integrations::Socialwise::WebhookEnhancerService

puts "1. Verificando estado inicial do cache..."
channel_cache_key = "socialwise:channel_type:4"
provider_cache_key = "socialwise:provider_config:4"

puts "Cache channel_type: #{Rails.cache.read(channel_cache_key) || 'VAZIO'}"
puts "Cache provider_config: #{Rails.cache.read(provider_cache_key) || 'VAZIO'}"

puts "\n2. Limpando cache para garantir estado limpo..."
Rails.cache.delete(channel_cache_key)
Rails.cache.delete(provider_cache_key)

puts "Cache channel_type após limpeza: #{Rails.cache.read(channel_cache_key) || 'VAZIO'}"
puts "Cache provider_config após limpeza: #{Rails.cache.read(provider_cache_key) || 'VAZIO'}"

puts "\n3. Primeira chamada - deve gerar CACHE MISS..."
begin
  enhanced_payload_1 = service.enhance_payload(real_webhook_payload, account)
  puts "Primeira chamada concluída"
rescue => e
  puts "Erro na primeira chamada: #{e.message}"
end

puts "\n4. Verificando se o cache foi populado..."
puts "Cache channel_type: #{Rails.cache.read(channel_cache_key) || 'VAZIO'}"
puts "Cache provider_config: #{Rails.cache.read(provider_cache_key) || 'VAZIO'}"

puts "\n5. Segunda chamada - deve usar cache (CACHE HIT)..."
begin
  enhanced_payload_2 = service.enhance_payload(real_webhook_payload, account)
  puts "Segunda chamada concluída"
rescue => e
  puts "Erro na segunda chamada: #{e.message}"
end

puts "\n6. Terceira chamada - deve usar cache (CACHE HIT)..."
begin
  enhanced_payload_3 = service.enhance_payload(real_webhook_payload, account)
  puts "Terceira chamada concluída"
rescue => e
  puts "Erro na terceira chamada: #{e.message}"
end

puts "\n7. Verificando estatísticas do cache..."
stats = service.get_cache_stats
puts "Estatísticas do cache:"
puts "Channel Type - Hits: #{stats.dig('channel_type', 'hits')}, Misses: #{stats.dig('channel_type', 'misses')}, Hit Rate: #{stats.dig('channel_type', 'hit_rate')}%"
puts "Provider Config - Hits: #{stats.dig('provider_config', 'hits')}, Misses: #{stats.dig('provider_config', 'misses')}, Hit Rate: #{stats.dig('provider_config', 'hit_rate')}%"

puts "\n8. Testando configuração do Rails.cache..."
puts "Rails.cache class: #{Rails.cache.class}"
puts "Rails.cache store: #{Rails.cache.class.name}"

# Teste direto do cache
test_key = "socialwise:test:#{Time.current.to_i}"
test_value = "test_value_#{rand(1000)}"

puts "\n9. Teste direto do cache..."
Rails.cache.write(test_key, test_value, expires_in: 1.hour)
cached_value = Rails.cache.read(test_key)
puts "Valor escrito: #{test_value}"
puts "Valor lido: #{cached_value}"
puts "Cache funcionando: #{test_value == cached_value ? 'SIM' : 'NÃO'}"

puts "\n10. Forçando preload do cache para inbox 4..."
success = service.force_preload_inbox_cache(4)
puts "Preload bem-sucedido: #{success ? 'SIM' : 'NÃO'}"

puts "\n11. Verificando cache após preload..."
puts "Cache channel_type: #{Rails.cache.read(channel_cache_key) || 'VAZIO'}"
puts "Cache provider_config: #{Rails.cache.read(provider_cache_key) || 'VAZIO'}"

puts "\n12. Quarta chamada após preload - deve usar cache..."
begin
  enhanced_payload_4 = service.enhance_payload(real_webhook_payload, account)
  puts "Quarta chamada concluída"
rescue => e
  puts "Erro na quarta chamada: #{e.message}"
end

puts "\n13. Diagnóstico completo do cache..."
diagnosis = service.diagnose_cache_issues(4)
puts "Diagnóstico: #{diagnosis}"

puts "\n=== FIM DO TESTE ==="