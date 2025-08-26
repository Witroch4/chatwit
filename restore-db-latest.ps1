param(
    [string]$ContainerName = "chatwit-dev-postgres-1",
    [string]$Database = "chatwoot",
    [string]$User = "postgres",
    [string]$SearchPath = ".",
    [string]$Pattern = "chatwoot_backup_*.sql.gz",
    [string]$Prefer = ""  # ex.: "2025-08-13" para priorizar esse dia
)

$ErrorActionPreference = "Stop"

function Get-BackupDateFromName([string]$fileName) {
    # Extrai data/hora do padrão: chatwoot_backup_YYYY-MM-DD_HH_MM_SS_*.sql.gz
    $regex = [regex]"chatwoot_backup_(\d{4}-\d{2}-\d{2})_(\d{2}_\d{2}_\d{2})"
    $m = $regex.Match($fileName)
    if ($m.Success) {
        $datePart = $m.Groups[1].Value
        $timePart = $m.Groups[2].Value -replace "_", ":"
        return [datetime]::ParseExact("$datePart $timePart", "yyyy-MM-dd HH:mm:ss", $null)
    }
    return $null
}

Write-Host "[INFO] Procurando backups em: $SearchPath com padrão: $Pattern" -ForegroundColor Cyan
$files = Get-ChildItem -Path $SearchPath -Recurse -File -Filter $Pattern | ForEach-Object {
    $dt = Get-BackupDateFromName $_.Name
    if (-not $dt) { $dt = $_.LastWriteTime }
    $_ | Add-Member -NotePropertyName BackupDate -NotePropertyValue $dt -PassThru
}

if (-not $files -or $files.Count -eq 0) {
    Write-Host "[ERROR] Nenhum arquivo encontrado com o padrão $Pattern" -ForegroundColor Red
    exit 1
}

# Se Prefer informado, tenta casar primeiro
$selected = $null
if ([string]::IsNullOrWhiteSpace($Prefer) -eq $false) {
    $candidates = $files | Where-Object { $_.Name -like "*${Prefer}*" } | Sort-Object BackupDate -Descending
    if ($candidates.Count -gt 0) {
        $selected = $candidates[0]
        Write-Host "[INFO] Preferência encontrada: $($selected.Name)" -ForegroundColor Green
    } else {
        Write-Host "[WARN] Preferência '$Prefer' não encontrada. Selecionando o mais recente disponível." -ForegroundColor Yellow
    }
}

if (-not $selected) {
    $selected = $files | Sort-Object BackupDate -Descending | Select-Object -First 1
}

Write-Host "[SELECTED] Backup: $($selected.FullName) (Data: $($selected.BackupDate))" -ForegroundColor Green

# Verifica container
$containers = (docker ps --format "{{.Names}}")
if (-not ($containers -contains $ContainerName)) {
    Write-Host "[ERROR] Container '$ContainerName' não está em execução. Inicie-o antes de continuar." -ForegroundColor Red
    exit 1
}

$remoteTmp = "/tmp/" + $selected.Name
$remoteSql = $remoteTmp -replace "\.gz$", ""

Write-Host "[STEP] Copiando arquivo para container..." -ForegroundColor Cyan
docker cp $selected.FullName "$ContainerName`:/tmp/" | Out-Null

Write-Host "[STEP] Restaurando no PostgreSQL do container..." -ForegroundColor Cyan
$restoreCmd = "gunzip -f $remoteTmp && psql -U $User -d $Database -f $remoteSql && rm -f $remoteSql"
docker exec $ContainerName sh -c "$restoreCmd"

if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Falha na restauração." -ForegroundColor Red
    exit $LASTEXITCODE
}

Write-Host "[SUCCESS] Restauração concluída com sucesso a partir de: $($selected.Name)" -ForegroundColor Green











