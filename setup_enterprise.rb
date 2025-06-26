# Script para habilitar funcionalidades Enterprise para fins educacionais

puts "🚀 Configurando Chatwoot Enterprise para fins educacionais..."

# 1. Configurar plano Enterprise
enterprise_plan = InstallationConfig.find_or_initialize_by(name: 'INSTALLATION_PRICING_PLAN')
enterprise_plan.value = 'enterprise'
enterprise_plan.save!
puts "✅ Plano configurado como Enterprise"

# 2. Configurar quantidade de agentes
agent_quantity = InstallationConfig.find_or_initialize_by(name: 'INSTALLATION_PRICING_PLAN_QUANTITY')
agent_quantity.value = 100
agent_quantity.save!
puts "✅ Limite de agentes configurado para 100"

# 3. Habilitar todas as funcionalidades Enterprise para todas as contas
Account.find_each do |account|
  # Funcionalidades Enterprise básicas
  enterprise_features = [
    'disable_branding',
    'audit_logs', 
    'sla',
    'captain_integration',
    'custom_roles',
    'response_bot'
  ]
  
  account.enable_features!(*enterprise_features)
  puts "✅ Funcionalidades Enterprise habilitadas para conta: #{account.name}"
end

puts "\n🎉 Configuração Enterprise concluída!"
puts "🔄 Reinicie o servidor Rails para aplicar todas as mudanças"
puts "📝 Acesse o Super Admin em: http://localhost:3000/super_admin" 