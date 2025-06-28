#!/usr/bin/env ruby
# Script para remover telemetria em producao

puts '============================================'
puts '  REMOVENDO TELEMETRIA EM PRODUCAO'
puts '============================================'

# Verifica ambiente
if Rails.env.production?
  puts 'Ambiente: PRODUCAO ✓'
else
  puts "Ambiente: #{Rails.env} (ATENCAO: nao e producao!)"
end

# Remove tokens de analytics
analytics_configs = GlobalConfig.where(name: ['ANALYTICS_TOKEN', 'HELP_CENTER_ANALYTICS_ID'])
analytics_configs.update_all(value: '')
puts "Analytics removidos: #{analytics_configs.count} configuracoes"

# Remove configuracoes de suporte
support_configs = GlobalConfig.where(name: [
  'CHATWOOT_INBOX_TOKEN',
  'CHATWOOT_INBOX_HMAC_KEY', 
  'CHATWOOT_SUPPORT_WEBSITE_TOKEN',
  'CHATWOOT_SUPPORT_SCRIPT_URL',
  'CHATWOOT_SUPPORT_IDENTIFIER_HASH'
])
support_configs.update_all(value: '')
puts "Suporte Chatwoot removido: #{support_configs.count} configuracoes"

# Verifica se telemetria esta desabilitada via ENV
telemetry_disabled = ENV['DISABLE_TELEMETRY'] == 'true'
puts "DISABLE_TELEMETRY: #{telemetry_disabled ? 'ATIVO ✓' : 'INATIVO ✗'}"

analytics_token = ENV['ANALYTICS_TOKEN']
puts "ANALYTICS_TOKEN: #{analytics_token.blank? ? 'VAZIO ✓' : 'PRESENTE ✗'}"

puts ''
puts 'TELEMETRIA REMOVIDA COM SUCESSO!'
puts '============================================'
