# Compile FR2Json plus TableTest and run them. No Unity.
param(
    [string]$SamplePath,
    [string]$TablePath
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not $SamplePath) { $SamplePath = Join-Path $PSScriptRoot 'test-table/sample.json' }

$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $csc)) {
    $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe'
}
if (-not (Test-Path -LiteralPath $csc)) { throw "csc.exe not found" }

$outDir = Join-Path $root 'out'
if (-not (Test-Path -LiteralPath $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}
$exe = Join-Path $outDir 'TableTest.exe'
$sources = @(
    (Join-Path $root 'runtime/FR2Json.cs'),
    (Join-Path $PSScriptRoot 'test-table/TableTest.cs')
)

& $csc /nologo /target:exe "/out:$exe" $sources
if ($LASTEXITCODE -ne 0) { throw "compile failed (exit $LASTEXITCODE)" }

$argsList = @($SamplePath)
if ($TablePath) { $argsList += $TablePath }
& $exe @argsList
if ($LASTEXITCODE -ne 0) { throw "table test failed (exit $LASTEXITCODE)" }
Write-Host "table test passed"
