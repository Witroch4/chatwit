param(
    [Parameter(Position=0)]
    [string]$Version = "v4.3.1",
    [string]$Registry = "witrocha",
    [string]$ImageName = "chatwit",
    [switch]$Latest,
    [switch]$Enterprise,
    [switch]$DisableTelemetry = $true,  # Por padrão desabilita telemetria
    [switch]$NoCache  # Força build sem cache
)

# Construir array de tags
$Tags = @($Version)
if ($Latest) {
    $Tags += "latest"
}

$FullImage = "$Registry/$ImageName"
$DockerFile = if ($Enterprise) { "Dockerfile.enterprise" } else { "Dockerfile" }

Write-Host "[BUILD] Building ${FullImage} with tags: $($Tags -join ', ')" -ForegroundColor Green
Write-Host "[INFO] Using: $DockerFile" -ForegroundColor Cyan

# Preparar argumentos de build para telemetria
$BuildArgs = @()
if ($DisableTelemetry) {
    Write-Host "[PRIVACY] Desabilitando telemetria na imagem..." -ForegroundColor Green
    $BuildArgs += "--build-arg", "DISABLE_TELEMETRY=true"
    $BuildArgs += "--build-arg", "ANALYTICS_TOKEN="
    $BuildArgs += "--build-arg", "CHATWOOT_HUB_URL=http://localhost:9999"
}

# Build com a primeira tag (versão principal)
$PrimaryTag = $Tags[0]
Write-Host "[BUILD] Building ${FullImage}:${PrimaryTag}..." -ForegroundColor Yellow

# Adicionar flag --no-cache se solicitado
$DockerBuildCmd = @("docker", "build", "-f", $DockerFile)
if ($NoCache) {
    $DockerBuildCmd += "--no-cache"
    Write-Host "[INFO] Build sem cache habilitado" -ForegroundColor Yellow
}
if ($BuildArgs.Count -gt 0) {
    $DockerBuildCmd += $BuildArgs
}
$DockerBuildCmd += "-t", "${FullImage}:${PrimaryTag}", "."

# Executar comando de build
& $DockerBuildCmd[0] $DockerBuildCmd[1..($DockerBuildCmd.Length-1)]

if ($LASTEXITCODE -eq 0) {
    Write-Host "[SUCCESS] Build successful!" -ForegroundColor Green
    
    # Tag com as tags adicionais
    if ($Tags.Count -gt 1) {
        for ($i = 1; $i -lt $Tags.Count; $i++) {
            $AdditionalTag = $Tags[$i]
            docker tag "${FullImage}:${PrimaryTag}" "${FullImage}:${AdditionalTag}"
            Write-Host "[TAG] Tagged as ${AdditionalTag}" -ForegroundColor Green
        }
    }
    
    Write-Host "[COMPLETE] Imagem criada com sucesso:" -ForegroundColor Green
    foreach ($tag in $Tags) {
        Write-Host "  -> ${FullImage}:${tag}" -ForegroundColor Cyan
    }
    
    Write-Host "[INFO] Para fazer push manualmente:" -ForegroundColor Yellow
    foreach ($tag in $Tags) {
        Write-Host "  docker push ${FullImage}:${tag}" -ForegroundColor White
    }
    
    if ($DisableTelemetry) {
        Write-Host ""
        Write-Host "[PRIVACY] TELEMETRIA DESABILITADA NA IMAGEM!" -ForegroundColor Green
        Write-Host "[INFO] Para usar em producao com completa privacidade:" -ForegroundColor Cyan
        Write-Host "  docker run -e DISABLE_TELEMETRY=true [outras-variaveis] ${FullImage}:${PrimaryTag}" -ForegroundColor White
        Write-Host "  Ou use os arquivos em bkp/ para configuracao completa" -ForegroundColor White
    }
    
} else {
    Write-Host "[ERROR] Build failed!" -ForegroundColor Red
    exit 1
} 