param(
    [Parameter(Position=0)]
    [string]$Version = "v4.3.1",
    [string]$Registry = "witrocha",
    [string]$ImageName = "chatwit",
    [switch]$Latest,
    [switch]$Enterprise
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

# Build com a primeira tag (versão principal)
$PrimaryTag = $Tags[0]
Write-Host "[BUILD] Building ${FullImage}:${PrimaryTag}..." -ForegroundColor Yellow

docker build -f $DockerFile -t "${FullImage}:${PrimaryTag}" .

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
    
} else {
    Write-Host "[ERROR] Build failed!" -ForegroundColor Red
    exit 1
} 