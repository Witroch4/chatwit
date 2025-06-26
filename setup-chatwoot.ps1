# Script PowerShell para Setup do Chatwoot
# Execute como Administrador se necessário

Write-Host "Iniciando setup do Chatwoot..." -ForegroundColor Green

# Verificar se estamos no diretório correto
if (-not (Test-Path "chatwit")) {
    Write-Host "ERRO: Diretório 'chatwit' não encontrado!" -ForegroundColor Red
    Write-Host "Execute este script na pasta raiz do projeto (onde está o diretório chatwit)" -ForegroundColor Yellow
    exit 1
}

# Navegar para o diretório do projeto
Set-Location "chatwit"

Write-Host "Navegado para o diretório chatwit" -ForegroundColor Cyan

# Verificar Ruby
Write-Host "Verificando Ruby..." -ForegroundColor Cyan
try {
    $rubyVersion = ruby --version
    Write-Host "OK: Ruby encontrado: $rubyVersion" -ForegroundColor Green
} catch {
    Write-Host "ERRO: Ruby não encontrado! Instale Ruby 3.4.4 primeiro." -ForegroundColor Red
    Write-Host "   Baixe em: https://rubyinstaller.org/" -ForegroundColor Yellow
    exit 1
}

# Verificar Node.js
Write-Host "Verificando Node.js..." -ForegroundColor Cyan
try {
    $nodeVersion = node --version
    Write-Host "OK: Node.js encontrado: $nodeVersion" -ForegroundColor Green
} catch {
    Write-Host "ERRO: Node.js não encontrado! Instale Node.js 23.x primeiro." -ForegroundColor Red
    Write-Host "   Baixe em: https://nodejs.org/" -ForegroundColor Yellow
    exit 1
}

# Verificar pnpm
Write-Host "Verificando pnpm..." -ForegroundColor Cyan
try {
    $pnpmVersion = pnpm --version
    Write-Host "OK: pnpm encontrado: $pnpmVersion" -ForegroundColor Green
} catch {
    Write-Host "AVISO: pnpm não encontrado. Instalando..." -ForegroundColor Yellow
    npm install -g pnpm@10.x
    Write-Host "OK: pnpm instalado!" -ForegroundColor Green
}

# Verificar PostgreSQL
Write-Host "Verificando PostgreSQL..." -ForegroundColor Cyan
try {
    $pgVersion = psql --version
    Write-Host "OK: PostgreSQL encontrado: $pgVersion" -ForegroundColor Green
} catch {
    Write-Host "ERRO: PostgreSQL não encontrado!" -ForegroundColor Red
    Write-Host "   Instale PostgreSQL: https://www.postgresql.org/download/windows/" -ForegroundColor Yellow
    Write-Host "   Ou continue manualmente após a instalação." -ForegroundColor Yellow
}

# Criar arquivo .env se não existir
if (-not (Test-Path ".env")) {
    Write-Host "Criando arquivo .env..." -ForegroundColor Cyan
    
    $envContent = @"
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
"@
    
    $envContent | Out-File -FilePath ".env" -Encoding UTF8
    Write-Host "OK: Arquivo .env criado!" -ForegroundColor Green
    Write-Host "IMPORTANTE: Edite o arquivo .env e configure:" -ForegroundColor Yellow
    Write-Host "   - POSTGRES_PASSWORD (senha do PostgreSQL)" -ForegroundColor Yellow
    Write-Host "   - SECRET_KEY_BASE (será gerado)" -ForegroundColor Yellow
} else {
    Write-Host "OK: Arquivo .env já existe" -ForegroundColor Green
}

# Instalar bundler
Write-Host "Instalando/Verificando Bundler..." -ForegroundColor Cyan
try {
    gem install bundler
    Write-Host "OK: Bundler pronto!" -ForegroundColor Green
} catch {
    Write-Host "ERRO: Erro ao instalar Bundler" -ForegroundColor Red
    exit 1
}

# Instalar dependências Ruby
Write-Host "Instalando dependências Ruby..." -ForegroundColor Cyan
try {
    bundle install
    Write-Host "OK: Dependências Ruby instaladas!" -ForegroundColor Green
} catch {
    Write-Host "ERRO: Erro ao instalar dependências Ruby" -ForegroundColor Red
    Write-Host "   Verifique se PostgreSQL está instalado e rodando" -ForegroundColor Yellow
}

# Gerar SECRET_KEY_BASE
Write-Host "Gerando SECRET_KEY_BASE..." -ForegroundColor Cyan
try {
    $secretKey = bundle exec rails secret
    
    # Atualizar arquivo .env
    $envContent = Get-Content ".env" -Raw
    $envContent = $envContent -replace "SECRET_KEY_BASE=", "SECRET_KEY_BASE=$secretKey"
    $envContent | Out-File -FilePath ".env" -Encoding UTF8 -NoNewline
    
    Write-Host "OK: SECRET_KEY_BASE gerado e adicionado ao .env!" -ForegroundColor Green
} catch {
    Write-Host "AVISO: Não foi possível gerar SECRET_KEY_BASE automaticamente" -ForegroundColor Yellow
    Write-Host "   Execute manualmente: bundle exec rails secret" -ForegroundColor Yellow
}

# Instalar dependências JavaScript
Write-Host "Instalando dependências JavaScript..." -ForegroundColor Cyan
try {
    pnpm install
    Write-Host "OK: Dependências JavaScript instaladas!" -ForegroundColor Green
} catch {
    Write-Host "ERRO: Erro ao instalar dependências JavaScript" -ForegroundColor Red
}

Write-Host ""
Write-Host "Setup básico concluído!" -ForegroundColor Green
Write-Host ""
Write-Host "Próximos passos:" -ForegroundColor Cyan
Write-Host "1. Configure a senha do PostgreSQL no arquivo .env" -ForegroundColor White
Write-Host "2. Execute: bundle exec rails db:create" -ForegroundColor White
Write-Host "3. Execute: bundle exec rails db:migrate" -ForegroundColor White
Write-Host "4. Execute: bundle exec rails db:seed" -ForegroundColor White
Write-Host "5. Execute: pnpm run start:dev" -ForegroundColor White
Write-Host ""
Write-Host "Para mais detalhes, consulte o arquivo SETUP_LOCAL.md" -ForegroundColor Yellow

# Voltar ao diretório original
Set-Location ".." 