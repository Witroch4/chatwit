#!/usr/bin/env pwsh

param(
    [Parameter(Mandatory=$true)]
    [string]$Version,
    
    [Parameter(Mandatory=$false)]
    [string]$Registry = "witrocha",
    
    [Parameter(Mandatory=$false)]
    [string]$ImageName = "chatwoot",
    
    [Parameter(Mandatory=$false)]
    [switch]$Enterprise,
    
    [Parameter(Mandatory=$false)]
    [switch]$Push,
    
    [Parameter(Mandatory=$false)]
    [switch]$Latest
)

$FullImageName = "$Registry/$ImageName"
$DockerFile = if ($Enterprise) { "Dockerfile.enterprise" } else { "Dockerfile" }
$ImageType = if ($Enterprise) { "Enterprise" } else { "Standard" }

Write-Host "🚀 Iniciando build da imagem $ImageType..." -ForegroundColor Green
Write-Host "📦 Imagem: ${FullImageName}:${Version}" -ForegroundColor Cyan
Write-Host "🐳 Dockerfile: $DockerFile" -ForegroundColor Cyan

# Verificar se há mudanças não commitadas
$gitStatus = git status --porcelain
if ($gitStatus) {
    Write-Host "⚠️  Existem mudanças não commitadas:" -ForegroundColor Yellow
    Write-Host $gitStatus -ForegroundColor Yellow
    $continue = Read-Host "Continuar mesmo assim? (y/N)"
    if ($continue -ne "y" -and $continue -ne "Y") {
        Write-Host "❌ Build cancelado" -ForegroundColor Red
        exit 1
    }
}

# Build da imagem
Write-Host "🔨 Construindo imagem..." -ForegroundColor Green
$buildStart = Get-Date
docker build -f $DockerFile -t "${FullImageName}:${Version}" .

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Falha no build da imagem!" -ForegroundColor Red
    exit 1
}

$buildEnd = Get-Date
$buildTime = ($buildEnd - $buildStart).TotalSeconds
Write-Host "✅ Build concluído em $([math]::Round($buildTime, 1))s" -ForegroundColor Green

# Criar tag 'latest' se solicitado
if ($Latest) {
    Write-Host "🏷️  Criando tag 'latest'..." -ForegroundColor Green
    docker tag "${FullImageName}:${Version}" "${FullImageName}:latest"
}

# Push para registry se solicitado
if ($Push) {
    Write-Host "📤 Fazendo push para registry..." -ForegroundColor Green
    
    # Push da versão específica
    docker push "${FullImageName}:${Version}"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Falha no push da versão ${Version}!" -ForegroundColor Red
        exit 1
    }
    
    # Push da tag 'latest' se criada
    if ($Latest) {
        docker push "${FullImageName}:latest"
        if ($LASTEXITCODE -ne 0) {
            Write-Host "❌ Falha no push da tag latest!" -ForegroundColor Red
            exit 1
        }
    }
    
    Write-Host "✅ Push concluído com sucesso!" -ForegroundColor Green
}

# Resumo final
Write-Host "`n🎉 Build finalizado com sucesso!" -ForegroundColor Green
Write-Host "📦 Imagem: ${FullImageName}:${Version}" -ForegroundColor Cyan
Write-Host "⏱️  Tempo total: $([math]::Round($buildTime, 1))s" -ForegroundColor Cyan

if ($Latest) {
    Write-Host "🏷️  Tag 'latest' criada" -ForegroundColor Cyan
}

if ($Push) {
    Write-Host "📤 Imagem enviada para registry" -ForegroundColor Cyan
    Write-Host "🔗 Disponível em: https://hub.docker.com/r/$Registry/$ImageName" -ForegroundColor Cyan
}

Write-Host "`n📋 Para usar em produção:" -ForegroundColor Yellow
Write-Host "   docker pull ${FullImageName}:${Version}" -ForegroundColor White
Write-Host "   # Ou atualize seu docker-compose.yml com a nova versão" -ForegroundColor Gray 