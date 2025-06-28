#!/usr/bin/env pwsh

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "  DESABILITAR TELEMETRIA DO CHATWOOT" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

# Verifica se estamos no diretório correto
if (-not (Test-Path "Gemfile")) {
    Write-Host "❌ Este script deve ser executado na raiz do projeto Chatwoot!" -ForegroundColor Red
    exit 1
}

Write-Host "🔍 Verificando configurações atuais de telemetria..." -ForegroundColor Yellow
Write-Host ""

# Função para adicionar variável de ambiente ao .env
function Add-EnvVariable {
    param($name, $value)
    
    $envFile = ".env"
    $line = "$name=$value"
    
    if (Test-Path $envFile) {
        $content = Get-Content $envFile
        $exists = $content | Where-Object { $_ -match "^$name=" }
        
        if ($exists) {
            # Substitui a linha existente
            $newContent = $content | ForEach-Object {
                if ($_ -match "^$name=") { $line } else { $_ }
            }
            $newContent | Set-Content $envFile
            Write-Host "   ✅ Atualizado: $line" -ForegroundColor Green
        } else {
            # Adiciona nova linha
            Add-Content $envFile "`n$line"
            Write-Host "   ✅ Adicionado: $line" -ForegroundColor Green
        }
    } else {
        # Cria arquivo .env
        $line | Set-Content $envFile
        Write-Host "   ✅ Criado .env com: $line" -ForegroundColor Green
    }
}

Write-Host "📝 Configurando variáveis de ambiente para desabilitar telemetria..."
Write-Host ""

# Desabilita telemetria principal
Add-EnvVariable "DISABLE_TELEMETRY" "true"

# Remove tokens de analytics
Add-EnvVariable "ANALYTICS_TOKEN" ""
Add-EnvVariable "HELP_CENTER_ANALYTICS_ID" ""

# Remove configurações de suporte Chatwoot
Add-EnvVariable "CHATWOOT_INBOX_TOKEN" ""
Add-EnvVariable "CHATWOOT_INBOX_HMAC_KEY" ""
Add-EnvVariable "CHATWOOT_SUPPORT_WEBSITE_TOKEN" ""
Add-EnvVariable "CHATWOOT_SUPPORT_SCRIPT_URL" ""
Add-EnvVariable "CHATWOOT_SUPPORT_IDENTIFIER_HASH" ""

# Define URL personalizada para o hub (opcional - redireciona para localhost)
Add-EnvVariable "CHATWOOT_HUB_URL" "http://localhost:9999"

Write-Host ""
Write-Host "🛠️  Criando configuração adicional no banco de dados..." -ForegroundColor Yellow

# Script Rails para remover configurações de telemetria do banco
$railsScript = @'
# Remove tokens de analytics da configuração global
GlobalConfig.where(name: ['ANALYTICS_TOKEN', 'HELP_CENTER_ANALYTICS_ID']).update_all(value: '')

# Remove configurações de suporte Chatwoot
GlobalConfig.where(name: [
  'CHATWOOT_INBOX_TOKEN', 
  'CHATWOOT_INBOX_HMAC_KEY',
  'CHATWOOT_SUPPORT_WEBSITE_TOKEN',
  'CHATWOOT_SUPPORT_SCRIPT_URL', 
  'CHATWOOT_SUPPORT_IDENTIFIER_HASH'
]).update_all(value: '')

puts "✅ Configurações de telemetria removidas do banco de dados"
'@

$railsScript | Set-Content "temp_disable_telemetry.rb"

Write-Host ""
Write-Host "🔍 Verificando arquivo de configuração atual..." -ForegroundColor Yellow

if (Test-Path ".env") {
    Write-Host ""
    Write-Host "📄 Conteúdo atual do .env relacionado à telemetria:" -ForegroundColor Cyan
    Get-Content ".env" | Where-Object { 
        $_ -match "(DISABLE_TELEMETRY|ANALYTICS|CHATWOOT_.*TOKEN|CHATWOOT_.*HMAC|CHATWOOT_SUPPORT|CHATWOOT_HUB)" 
    } | ForEach-Object {
        Write-Host "   $_" -ForegroundColor White
    }
}

Write-Host ""
Write-Host "📋 RESUMO DAS CONFIGURAÇÕES:" -ForegroundColor Cyan
Write-Host "   • DISABLE_TELEMETRY=true (desabilita toda telemetria)" -ForegroundColor Green
Write-Host "   • ANALYTICS_TOKEN vazio (remove analytics frontend)" -ForegroundColor Green  
Write-Host "   • Tokens de suporte Chatwoot removidos" -ForegroundColor Green
Write-Host "   • Hub URL redirecionado para localhost" -ForegroundColor Green
Write-Host ""

Write-Host "⚠️  IMPORTANTE:" -ForegroundColor Yellow
Write-Host "   1. Execute: rails runner temp_disable_telemetry.rb" -ForegroundColor White
Write-Host "   2. Reinicie a aplicação após as mudanças" -ForegroundColor White
Write-Host "   3. Verifique os logs para confirmar que não há tentativas de conexão" -ForegroundColor White
Write-Host ""

Write-Host "🔒 VERIFICAÇÃO ADICIONAL:" -ForegroundColor Cyan
Write-Host "   Para confirmar que a telemetria está desabilitada, monitore os logs da aplicação." -ForegroundColor White
Write-Host "   Não devem aparecer tentativas de conexão com hub.chatwoot.com" -ForegroundColor White
Write-Host ""

Write-Host "✅ Configuração de desabilitação da telemetria concluída!" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Cyan

# Pergunta se deve executar o script Rails automaticamente
$response = Read-Host "Deseja executar o script Rails agora para limpar o banco? (s/n)"
if ($response -eq "s" -or $response -eq "S") {
    Write-Host ""
    Write-Host "🚀 Executando script Rails..." -ForegroundColor Yellow
    
    if (Get-Command "rails" -ErrorAction SilentlyContinue) {
        rails runner temp_disable_telemetry.rb
        Write-Host "✅ Script Rails executado!" -ForegroundColor Green
    } else {
        Write-Host "❌ Comando 'rails' não encontrado. Execute manualmente:" -ForegroundColor Red
        Write-Host "   rails runner temp_disable_telemetry.rb" -ForegroundColor White
    }
    
    Write-Host ""
    Write-Host "🗑️  Removendo arquivo temporário..." -ForegroundColor Yellow
    Remove-Item "temp_disable_telemetry.rb" -ErrorAction SilentlyContinue
    Write-Host "✅ Limpeza concluída!" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "ℹ️  Lembre-se de executar manualmente:" -ForegroundColor Blue
    Write-Host "   rails runner temp_disable_telemetry.rb" -ForegroundColor White
    Write-Host "   rm temp_disable_telemetry.rb" -ForegroundColor White
}

Write-Host ""
Write-Host "🎉 Processo concluído! Sua instância do Chatwoot não enviará mais dados de telemetria." -ForegroundColor Green 