#!/usr/bin/env pwsh

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  DESABILITAR TELEMETRIA DO CHATWOOT" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Verifica se estamos no diretorio correto
if (-not (Test-Path "Gemfile")) {
    Write-Host "ERRO: Este script deve ser executado na raiz do projeto Chatwoot!" -ForegroundColor Red
    exit 1
}

Write-Host "Configurando variaveis de ambiente para desabilitar telemetria..." -ForegroundColor Yellow
Write-Host ""

# Configura as variaveis no arquivo .env
$envVars = @{
    "DISABLE_TELEMETRY" = "true"
    "ANALYTICS_TOKEN" = ""
    "HELP_CENTER_ANALYTICS_ID" = ""
    "CHATWOOT_INBOX_TOKEN" = ""
    "CHATWOOT_INBOX_HMAC_KEY" = ""
    "CHATWOOT_SUPPORT_WEBSITE_TOKEN" = ""
    "CHATWOOT_SUPPORT_SCRIPT_URL" = ""
    "CHATWOOT_SUPPORT_IDENTIFIER_HASH" = ""
    "CHATWOOT_HUB_URL" = "http://localhost:9999"
}

# Funcao para adicionar/atualizar variavel no .env
function Update-EnvFile {
    param($varName, $varValue)
    
    $envFile = ".env"
    $line = "$varName=$varValue"
    
    if (Test-Path $envFile) {
        $content = Get-Content $envFile
        $newContent = @()
        $found = $false
        
        foreach ($currentLine in $content) {
            if ($currentLine -match "^$varName=") {
                $newContent += $line
                $found = $true
                Write-Host "   Atualizado: $line" -ForegroundColor Green
            } else {
                $newContent += $currentLine
            }
        }
        
        if (-not $found) {
            $newContent += $line
            Write-Host "   Adicionado: $line" -ForegroundColor Green
        }
        
        $newContent | Set-Content $envFile
    } else {
        $line | Set-Content $envFile
        Write-Host "   Criado .env com: $line" -ForegroundColor Green
    }
}

# Aplica todas as configuracoes
foreach ($var in $envVars.GetEnumerator()) {
    Update-EnvFile -varName $var.Key -varValue $var.Value
}

Write-Host ""
Write-Host "Criando script Rails para limpar configuracoes do banco..." -ForegroundColor Yellow

# Script Rails simples
$railsScript = @"
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
"@

$railsScript | Set-Content "clean_telemetry.rb"

Write-Host ""
Write-Host "RESUMO DAS CONFIGURACOES APLICADAS:" -ForegroundColor Cyan
Write-Host "  * DISABLE_TELEMETRY=true (bloqueia toda telemetria)" -ForegroundColor Green
Write-Host "  * ANALYTICS_TOKEN vazio (remove analytics do frontend)" -ForegroundColor Green  
Write-Host "  * Todos tokens de suporte Chatwoot removidos" -ForegroundColor Green
Write-Host "  * Hub URL redirecionado para localhost" -ForegroundColor Green
Write-Host ""

Write-Host "PROXIMOS PASSOS:" -ForegroundColor Yellow
Write-Host "  1. Execute: rails runner clean_telemetry.rb" -ForegroundColor White
Write-Host "  2. Reinicie a aplicacao" -ForegroundColor White
Write-Host "  3. Monitore os logs para confirmar que nao ha conexoes com Chatwoot" -ForegroundColor White
Write-Host ""

Write-Host "TELEMETRIA DESABILITADA COM SUCESSO!" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Cyan 