#!/usr/bin/env pwsh

param(
    [string]$ContainerName = "chatwit-app",
    [string]$DatabaseUrl = "",
    [switch]$Docker,
    [switch]$EnvFile,
    [switch]$DatabaseOnly
)

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  CONFIGURACAO DE PRIVACIDADE PRODUCAO" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Variaveis de ambiente para desabilitar telemetria
$EnvVars = @{
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

# Funcao para gerar comando docker run com variaveis
function Generate-DockerRunVars {
    Write-Host "VARIAVEIS PARA DOCKER RUN/COMPOSE:" -ForegroundColor Yellow
    foreach ($var in $EnvVars.GetEnumerator()) {
        Write-Host "  -e $($var.Key)=$($var.Value)" -ForegroundColor White
    }
    Write-Host ""
    
    Write-Host "EXEMPLO DOCKER RUN:" -ForegroundColor Cyan
    $dockerVars = ($EnvVars.GetEnumerator() | ForEach-Object { "-e $($_.Key)=$($_.Value)" }) -join " "
    Write-Host "docker run $dockerVars [outras-opcoes] witrocha/chatwit:latest" -ForegroundColor White
    Write-Host ""
}

# Funcao para gerar arquivo .env para producao
function Generate-ProductionEnv {
    Write-Host "CRIANDO ARQUIVO .env.production..." -ForegroundColor Yellow
    
    $envContent = @"
# ============================================
# CONFIGURACOES DE PRIVACIDADE - PRODUCAO
# ============================================

# Desabilita toda telemetria
DISABLE_TELEMETRY=true

# Remove analytics do frontend
ANALYTICS_TOKEN=
HELP_CENTER_ANALYTICS_ID=

# Remove conexoes com suporte Chatwoot
CHATWOOT_INBOX_TOKEN=
CHATWOOT_INBOX_HMAC_KEY=
CHATWOOT_SUPPORT_WEBSITE_TOKEN=
CHATWOOT_SUPPORT_SCRIPT_URL=
CHATWOOT_SUPPORT_IDENTIFIER_HASH=

# Redireciona hub para localhost
CHATWOOT_HUB_URL=http://localhost:9999

# ============================================
# OUTRAS CONFIGURACOES DE PRODUCAO
# ============================================

# Configure suas variaveis de producao aqui:
# POSTGRES_HOST=
# POSTGRES_DATABASE=
# POSTGRES_USERNAME=
# POSTGRES_PASSWORD=
# REDIS_URL=
# SECRET_KEY_BASE=
# FRONTEND_URL=
# FORCE_SSL=true
"@

    $envContent | Set-Content ".env.production"
    Write-Host "  Arquivo .env.production criado!" -ForegroundColor Green
    Write-Host ""
}

# Funcao para gerar script SQL para banco
function Generate-DatabaseScript {
    Write-Host "CRIANDO SCRIPT SQL PARA BANCO..." -ForegroundColor Yellow
    
    $sqlScript = @"
-- ============================================
-- REMOVER TELEMETRIA DO BANCO DE DADOS
-- ============================================

-- Remove tokens de analytics
UPDATE global_configs 
SET value = '' 
WHERE name IN ('ANALYTICS_TOKEN', 'HELP_CENTER_ANALYTICS_ID');

-- Remove configuracoes de suporte Chatwoot
UPDATE global_configs 
SET value = '' 
WHERE name IN (
    'CHATWOOT_INBOX_TOKEN',
    'CHATWOOT_INBOX_HMAC_KEY', 
    'CHATWOOT_SUPPORT_WEBSITE_TOKEN',
    'CHATWOOT_SUPPORT_SCRIPT_URL',
    'CHATWOOT_SUPPORT_IDENTIFIER_HASH'
);

-- Opcional: Remove identificador de instalacao (descomentar se necessario)
-- DELETE FROM installation_configs WHERE name = 'INSTALLATION_IDENTIFIER';

-- Verifica configuracoes aplicadas
SELECT name, 
       CASE WHEN value = '' THEN 'REMOVIDO' ELSE 'AINDA PRESENTE' END as status
FROM global_configs 
WHERE name IN (
    'ANALYTICS_TOKEN', 
    'HELP_CENTER_ANALYTICS_ID',
    'CHATWOOT_INBOX_TOKEN',
    'CHATWOOT_INBOX_HMAC_KEY',
    'CHATWOOT_SUPPORT_WEBSITE_TOKEN', 
    'CHATWOOT_SUPPORT_SCRIPT_URL',
    'CHATWOOT_SUPPORT_IDENTIFIER_HASH'
);
"@

    $sqlScript | Set-Content "remove-telemetry-production.sql"
    Write-Host "  Arquivo remove-telemetry-production.sql criado!" -ForegroundColor Green
    Write-Host ""
}

# Funcao para gerar script Rails para producao
function Generate-RailsScript {
    Write-Host "CRIANDO SCRIPT RAILS PARA PRODUCAO..." -ForegroundColor Yellow
    
    $railsScript = @"
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
"@

    $railsScript | Set-Content "remove-telemetry-production.rb"
    Write-Host "  Arquivo remove-telemetry-production.rb criado!" -ForegroundColor Green
    Write-Host ""
}

# Executa baseado nos parametros
if ($EnvFile -or (!$Docker -and !$DatabaseOnly)) {
    Generate-ProductionEnv
}

if ($Docker -or (!$EnvFile -and !$DatabaseOnly)) {
    Generate-DockerRunVars
}

if ($DatabaseOnly -or (!$Docker -and !$EnvFile)) {
    Generate-DatabaseScript
    Generate-RailsScript
}

Write-Host "INSTRUCOES PARA PRODUCAO:" -ForegroundColor Green
Write-Host ""

Write-Host "1. PARA DOCKER:" -ForegroundColor Cyan
Write-Host "   - Use as variaveis -e mostradas acima no docker run" -ForegroundColor White
Write-Host "   - Ou adicione ao docker-compose.yml" -ForegroundColor White
Write-Host ""

Write-Host "2. PARA SERVIDOR TRADICIONAL:" -ForegroundColor Cyan  
Write-Host "   - Copie .env.production para seu servidor" -ForegroundColor White
Write-Host "   - Execute: rails runner remove-telemetry-production.rb" -ForegroundColor White
Write-Host ""

Write-Host "3. PARA BANCO DE DADOS:" -ForegroundColor Cyan
Write-Host "   - Execute: psql -d database_name -f remove-telemetry-production.sql" -ForegroundColor White
Write-Host "   - Ou execute o script Rails na aplicacao em producao" -ForegroundColor White
Write-Host ""

Write-Host "VERIFICACAO:" -ForegroundColor Yellow
Write-Host "  Monitore os logs da aplicacao para confirmar que nao ha" -ForegroundColor White
Write-Host "  tentativas de conexao com hub.chatwoot.com" -ForegroundColor White
Write-Host ""

Write-Host "TELEMETRIA SERA DESABILITADA EM PRODUCAO!" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Cyan 