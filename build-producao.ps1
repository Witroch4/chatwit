<#
.SYNOPSIS
    Constrói e envia imagens Docker para um registro.

.DESCRIPTION
    Este script automatiza o processo de build de uma imagem Docker, aplicando múltiplas tags (versão e 'latest').
    Por padrão, o script realiza um build da versão 'Enterprise' e envia a imagem para o registro após o build.
    Use as flags -NoEnterprise e -NoPush para alterar o comportamento padrão.

.PARAMETER Version
    A versão da imagem a ser construída (ex: v4.3.1).

.PARAMETER Registry
    O nome do registro Docker para onde a imagem será enviada (ex: witrocha).

.PARAMETER ImageName
    O nome da imagem (ex: chatwit).

.PARAMETER Latest
    Se presente, adiciona a tag 'latest' à imagem.

.PARAMETER NoEnterprise
    Se presente, utiliza o Dockerfile padrão em vez do Dockerfile.enterprise.

.PARAMETER NoPush
    Se presente, desabilita o push automático da imagem para o registro após o build.

.EXAMPLE
    .\build.ps1 -Version "v5.0.0" -Latest
    Constrói a imagem enterprise witrocha/chatwit:v5.0.0 e witrocha/chatwit:latest e as envia para o registro.

.EXAMPLE
    .\build.ps1 -NoPush
    Constrói a imagem enterprise mas não a envia para o registro.

.EXAMPLE
    .\build.ps1 -NoEnterprise -Latest
    Constrói a imagem padrão (não-enterprise) com as tags de versão e 'latest' e as envia para o registro.
#>
param(
    [Parameter(Position=0)]
    [string]$Version = "v4.3.1",
    [string]$Registry = "witrocha",
    [string]$ImageName = "chatwit",
    [switch]$Latest,
    [switch]$NoEnterprise,              # NOVO: Flag para desabilitar o build enterprise (padrão)
    [switch]$DisableTelemetry = $true,  # Por padrão desabilita telemetria
    [switch]$NoCache,                   # Força build sem cache
    [switch]$NoPush                     # NOVO: Flag para desabilitar o push (padrão)
)

# Construir array de tags
$Tags = @($Version)
if ($Latest) {
    $Tags += "latest"
}

$FullImage = "$Registry/$ImageName"

# --- LÓGICA DE DOCKERFILE MODIFICADA ---
# Por padrão, o build é enterprise. A flag -NoEnterprise usa o Dockerfile padrão.
$IsEnterprise = -not $NoEnterprise
$DockerFile = if ($IsEnterprise) { "Dockerfile.enterprise" } else { "Dockerfile" }

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
    
    # --- LÓGICA DE PUSH MODIFICADA ---
    # Por padrão, o push é habilitado. A flag -NoPush o desabilita.
    if (-not $NoPush.IsPresent) {
        Write-Host "[PUSH] Iniciando push para o registro (padrão)..." -ForegroundColor Yellow
        Write-Host "[INFO] Para desabilitar, use a flag -NoPush." -ForegroundColor Cyan
        foreach ($tag in $Tags) {
            Write-Host "[PUSH] Enviando ${FullImage}:${tag}..." -ForegroundColor Cyan
            docker push "${FullImage}:${tag}"
            if ($LASTEXITCODE -ne 0) {
                Write-Host "[ERROR] Falha no push da tag ${tag}!" -ForegroundColor Red
                exit 1 # Interrompe o script se o push falhar
            } else {
                Write-Host "[SUCCESS] Push da tag ${tag} concluído." -ForegroundColor Green
            }
        }
        Write-Host "[COMPLETE] Todas as tags foram enviadas para o registro." -ForegroundColor Green
    }
    else {
        Write-Host "[INFO] Push automático desabilitado pela flag -NoPush." -ForegroundColor Yellow
        Write-Host "[INFO] Para fazer push manualmente:" -ForegroundColor Yellow
        foreach ($tag in $Tags) {
            Write-Host "  docker push ${FullImage}:${tag}" -ForegroundColor White
        }
    }
    
    if ($DisableTelemetry) {
        Write-Host ""
        Write-Host "[PRIVACY] TELEMETRIA DESABILITADA NA IMAGEM!" -ForegroundColor Green
    }
    
} else {
    Write-Host "[ERROR] Build failed!" -ForegroundColor Red
    exit 1
}
