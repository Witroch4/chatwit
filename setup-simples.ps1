# Script PowerShell Simplificado para Setup do Chatwoot
# Execute na pasta raiz do projeto

Write-Host "Iniciando setup do Chatwoot..." -ForegroundColor Green

# Verificar se estamos no diretório correto (deve ter Gemfile)
if (-not (Test-Path "Gemfile")) {
    Write-Host "ERRO: Arquivo 'Gemfile' não encontrado!" -ForegroundColor Red
    Write-Host "Execute este script na pasta raiz do projeto Chatwoot" -ForegroundColor Yellow
    exit 1
}

Write-Host "OK: Você está na pasta raiz do projeto" -ForegroundColor Green

# Verificar Ruby
Write-Host "Verificando Ruby..." -ForegroundColor Cyan
$rubyCheck = Get-Command ruby -ErrorAction SilentlyContinue
if ($rubyCheck) {
    $rubyVersion = ruby --version
    Write-Host "OK: Ruby encontrado - $rubyVersion" -ForegroundColor Green
} else {
    Write-Host "ERRO: Ruby não encontrado!" -ForegroundColor Red
    Write-Host "Instale Ruby 3.4.4 em: https://rubyinstaller.org/" -ForegroundColor Yellow
    exit 1
}

# Verificar Node.js
Write-Host "Verificando Node.js..." -ForegroundColor Cyan
$nodeCheck = Get-Command node -ErrorAction SilentlyContinue
if ($nodeCheck) {
    $nodeVersion = node --version
    Write-Host "OK: Node.js encontrado - $nodeVersion" -ForegroundColor Green
} else {
    Write-Host "ERRO: Node.js não encontrado!" -ForegroundColor Red
    Write-Host "Instale Node.js 23.x em: https://nodejs.org/" -ForegroundColor Yellow
    exit 1
}

# Verificar/Instalar pnpm
Write-Host "Verificando pnpm..." -ForegroundColor Cyan
$pnpmCheck = Get-Command pnpm -ErrorAction SilentlyContinue
if ($pnpmCheck) {
    $pnpmVersion = pnpm --version
    Write-Host "OK: pnpm encontrado - $pnpmVersion" -ForegroundColor Green
} else {
    Write-Host "AVISO: pnpm não encontrado. Instalando..." -ForegroundColor Yellow
    npm install -g pnpm@10.x
    Write-Host "OK: pnpm instalado!" -ForegroundColor Green
}

# Criar arquivo .env se não existir
if (-not (Test-Path ".env")) {
    Write-Host "Criando arquivo .env..." -ForegroundColor Cyan
    
@'
# Banco de dados
POSTGRES_HOST=localhost
POSTGRES_PORT=5432
POSTGRES_USERNAME=postgres
POSTGRES_PASSWORD=
POSTGRES_DATABASE=chatwoot_dev

# Redis
REDIS_URL=redis://localhost:6379

# Rails
RAILS_ENV=development
SECRET_KEY_BASE=
FRONTEND_URL=http://localhost:3000

# Mailer (opcional para desenvolvimento)
MAILER_SENDER_EMAIL=noreply@chatwoot.dev
SMTP_ADDRESS=localhost
SMTP_PORT=1025

# Configurações adicionais
RAILS_LOG_TO_STDOUT=true
RAILS_MAX_THREADS=5
'@ | Out-File -FilePath ".env" -Encoding UTF8
    
    Write-Host "OK: Arquivo .env criado!" -ForegroundColor Green
    Write-Host "IMPORTANTE: Configure POSTGRES_PASSWORD no arquivo .env" -ForegroundColor Yellow
} else {
    Write-Host "OK: Arquivo .env já existe" -ForegroundColor Green
}

# Instalar bundler
Write-Host "Instalando bundler..." -ForegroundColor Cyan
gem install bundler
if ($LASTEXITCODE -eq 0) {
    Write-Host "OK: Bundler instalado!" -ForegroundColor Green
} else {
    Write-Host "ERRO: Falha ao instalar bundler" -ForegroundColor Red
}

# Instalar dependências Ruby
Write-Host "Instalando dependências Ruby..." -ForegroundColor Cyan
bundle install
if ($LASTEXITCODE -eq 0) {
    Write-Host "OK: Dependências Ruby instaladas!" -ForegroundColor Green
} else {
    Write-Host "ERRO: Falha ao instalar dependências Ruby" -ForegroundColor Red
    Write-Host "Verifique se PostgreSQL está instalado" -ForegroundColor Yellow
}

# Gerar SECRET_KEY_BASE
Write-Host "Gerando SECRET_KEY_BASE..." -ForegroundColor Cyan
$secretKey = bundle exec rails secret 2>$null
if ($secretKey) {
    $envContent = Get-Content ".env" -Raw
    $envContent = $envContent -replace "SECRET_KEY_BASE=", "SECRET_KEY_BASE=$secretKey"
    $envContent | Out-File -FilePath ".env" -Encoding UTF8 -NoNewline
    Write-Host "OK: SECRET_KEY_BASE gerado!" -ForegroundColor Green
} else {
    Write-Host "AVISO: Não foi possível gerar SECRET_KEY_BASE" -ForegroundColor Yellow
    Write-Host "Execute manualmente: bundle exec rails secret" -ForegroundColor Yellow
}

# Instalar dependências JavaScript
Write-Host "Instalando dependências JavaScript..." -ForegroundColor Cyan
pnpm install
if ($LASTEXITCODE -eq 0) {
    Write-Host "OK: Dependências JavaScript instaladas!" -ForegroundColor Green
} else {
    Write-Host "ERRO: Falha ao instalar dependências JavaScript" -ForegroundColor Red
}

Write-Host ""
Write-Host "Setup básico concluído!" -ForegroundColor Green
Write-Host ""
Write-Host "Próximos passos:" -ForegroundColor Cyan
Write-Host "1. Configure POSTGRES_PASSWORD no arquivo .env" -ForegroundColor White
Write-Host "2. bundle exec rails db:create" -ForegroundColor White
Write-Host "3. bundle exec rails db:migrate" -ForegroundColor White
Write-Host "4. bundle exec rails db:seed" -ForegroundColor White
Write-Host "5. pnpm run start:dev" -ForegroundColor White
Write-Host ""
Write-Host "Para mais detalhes, consulte SETUP_LOCAL.md" -ForegroundColor Yellow 