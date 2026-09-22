# Restore a Find Reference 2 folder from a FindReference2-CN backup zip.
#   .\revert.ps1 -PluginPath "D:\...\Assets\FindReference2"
#   .\revert.ps1 -PluginPath "..." -BackupZip "D:\...\FindReference2_20260922_180000.zip"
param(
    [Parameter(Mandatory = $true)][string]$PluginPath,
    [string]$BackupZip
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$pluginRoot = Resolve-PluginPath $PluginPath
$projectRoot = Find-UnityProjectRoot $pluginRoot
$backupBase = if ($projectRoot) { Split-Path -Parent $projectRoot } else { Split-Path -Parent $pluginRoot }
$backupDir = Join-Path $backupBase 'FindReference2-CN-backups'

if (-not $BackupZip) {
    $latest = Get-ChildItem -LiteralPath $backupDir -Filter 'FindReference2_*.zip' -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $latest) { throw "No backup zip in $backupDir" }
    $BackupZip = $latest.FullName
}
if (-not (Test-Path -LiteralPath $BackupZip)) { throw "Backup zip not found: $BackupZip" }

$temp = Join-Path ([System.IO.Path]::GetTempPath()) ("fr2cn-revert-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp | Out-Null
try {
    Expand-Archive -LiteralPath $BackupZip -DestinationPath $temp -Force
    $child = @(Get-ChildItem -LiteralPath $temp -Directory)
    if ($child.Count -ne 1) { throw "Expected one root folder in $BackupZip" }
    $parent = Split-Path -Parent $pluginRoot
    $destName = Split-Path -Leaf $pluginRoot
    if ($child[0].Name -ne $destName) { throw "Zip root '$($child[0].Name)' is not '$destName'" }
    Remove-Item -LiteralPath $pluginRoot -Recurse -Force
    Move-Item -LiteralPath $child[0].FullName -Destination (Join-Path $parent $destName)
}
finally {
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}
Write-Host "Restored $pluginRoot from $BackupZip"
