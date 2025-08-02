#!/usr/bin/env ruby
# Script para habilitar SOCIALWISE_RICH_DASHBOARD para a conta 3

# Encontrar a conta 3
account = Account.find(3)

puts "=== Habilitando SOCIALWISE_RICH_DASHBOARD para conta #{account.id} ==="
puts "Estado atual: #{account.feature_enabled?('SOCIALWISE_RICH_DASHBOARD')}"

# Habilitar a feature
account.enable_features!('SOCIALWISE_RICH_DASHBOARD')

puts "Estado após habilitação: #{account.feature_enabled?('SOCIALWISE_RICH_DASHBOARD')}"

# Verificar todas as features habilitadas
puts "\n=== Features habilitadas para conta #{account.id} ==="
account.enabled_features.each do |feature_name, enabled|
  puts "  #{feature_name}: #{enabled}"
end

puts "\n=== Teste do Instagram Rich Message Service ==="
puts "Feature check: #{account.feature_enabled?('SOCIALWISE_RICH_DASHBOARD')}"

puts "\n✅ Script concluído!"