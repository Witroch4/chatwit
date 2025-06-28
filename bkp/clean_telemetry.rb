# Remove tokens de analytics
GlobalConfig.where(name: ['ANALYTICS_TOKEN', 'HELP_CENTER_ANALYTICS_ID']).update_all(value: '')

# Remove configuracoes de suporte
GlobalConfig.where(name: [
  'CHATWOOT_INBOX_TOKEN', 
  'CHATWOOT_INBOX_HMAC_KEY',
  'CHATWOOT_SUPPORT_WEBSITE_TOKEN',
  'CHATWOOT_SUPPORT_SCRIPT_URL', 
  'CHATWOOT_SUPPORT_IDENTIFIER_HASH'
]).update_all(value: '')

puts 'Configuracoes de telemetria removidas do banco de dados!'
