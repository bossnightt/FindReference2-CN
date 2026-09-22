# Build a fake Unity project, apply the patch, and check the rewrite.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$work = Join-Path ([System.IO.Path]::GetTempPath()) 'fr2cn-apply-test'
if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
$project = Join-Path $work 'Proj'
$plugin = Join-Path $project 'Assets\FindReference2'
$scriptDir = Join-Path $plugin 'Editor\Script'
New-Item -ItemType Directory -Path $scriptDir -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $project 'ProjectSettings') -Force | Out-Null
Set-Content -LiteralPath (Join-Path $project 'ProjectSettings\ProjectVersion.txt') -Value 'm_EditorVersion: 2022.3.0f1' -Encoding ASCII
Copy-Item -Path (Join-Path $PSScriptRoot 'fixtures\*.cs') -Destination $scriptDir

$beforeAssets = Join-Path $work 'Before\Assets'
New-Item -ItemType Directory -Path $beforeAssets -Force | Out-Null
Copy-Item -LiteralPath $plugin -Destination $beforeAssets -Recurse
$before = Join-Path $beforeAssets 'FindReference2'

function Assert-Has {
    param([string]$Path, [string]$Needle)
    $text = [System.IO.File]::ReadAllText($Path)
    if ($text.IndexOf($Needle) -lt 0) { throw "Missing [$Needle] in $Path" }
}
function Assert-Lacks {
    param([string]$Path, [string]$Needle)
    $text = [System.IO.File]::ReadAllText($Path)
    if ($text.IndexOf($Needle) -ge 0) { throw "Unexpected [$Needle] in $Path" }
}

& (Join-Path $PSScriptRoot 'apply.ps1') -PluginPath $plugin
$backupDir = Join-Path $work 'FindReference2-CN-backups'
$zips = @(Get-ChildItem -LiteralPath $backupDir -Filter 'FindReference2_*.zip' -File)
if ($zips.Count -lt 1) { throw 'backup zip was not written next to the fake project' }

$loc = Join-Path $scriptDir 'Localization'
$locBytes = [System.IO.File]::ReadAllBytes((Join-Path $loc 'FR2Loc.cs'))
if ($locBytes.Length -lt 3 -or $locBytes[0] -ne 0xEF -or $locBytes[1] -ne 0xBB -or $locBytes[2] -ne 0xBF) {
    throw 'FR2Loc.cs was not written with a UTF-8 BOM'
}
$jsonBytes = [System.IO.File]::ReadAllBytes((Join-Path $loc 'fr2-zh-CN.json'))
if ($jsonBytes.Length -ge 3 -and $jsonBytes[0] -eq 0xEF -and $jsonBytes[1] -eq 0xBB -and $jsonBytes[2] -eq 0xBF) {
    throw 'fr2-zh-CN.json must not start with a BOM'
}

$window = Join-Path $scriptDir 'FR2_WindowBase.cs'
Assert-Has $window 'static GUIContent[] Toolbars()'
Assert-Has $window 'FR2Loc.C("Uses")'
Assert-Has $window 'FR2Loc.Button("Scan project")'
Assert-Has $window 'FR2Loc.Button("Commit Selection [{0}]", FR2_Selection.SelectionCount, EditorStyles.toolbarButton)'
Assert-Has $window 'Toolbars().Length'
Assert-Has $window 'Toolbars()[i]'
Assert-Has $window 'FR2Loc.Toggle(false, Toolbars()[i], EditorStyles.toolbarButton)'
Assert-Has $window 'GUI.Label(r, assetName, EditorStyles.boldLabel)'
Assert-Has $window 'new GUIContent("Open")'
Assert-Lacks $window 'FR2Loc.C("Open")'

$ref = Join-Path $scriptDir 'FR2_Ref.cs'
Assert-Has $ref 'FR2Loc.T(label)'
Assert-Has $ref 'return "Direct Usage"'

$assetType = Join-Path $scriptDir 'FR2_AssetType.cs'
Assert-Has $assetType 'FR2Loc.T(id)'
Assert-Has $assetType 'new AssetType("Scene"'

$cache = Join-Path $scriptDir 'FR2_Cache.cs'
Assert-Has $cache 'FR2_Unity.DrawToggle(ref pingRow, "Full Row click to Ping")'
Assert-Has $cache 'EditorGUI.ProgressBar'
Assert-Lacks $cache 'FR2Loc.ProgressBar'

$once = [System.IO.File]::ReadAllText($window)
$log = & (Join-Path $PSScriptRoot 'apply.ps1') -PluginPath $plugin -NoBackup 2>&1 | Out-String
if ([System.IO.File]::ReadAllText($window) -ne $once) { throw 'second apply changed an already patched file' }
if ($log -notmatch 'already patched') { throw 'second apply did not skip patched files' }

$extract = Join-Path $PSScriptRoot 'extract.ps1'
$beforeOut = Join-Path $work 'extract-before'
& $extract -PluginPath $before -OutDir $beforeOut
$missing = Get-Content -LiteralPath (Join-Path $beforeOut 'missing.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$extracted = Get-Content -LiteralPath (Join-Path $beforeOut 'extracted.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($key in @('Scan project', 'Uses', 'Direct Usage', 'Scene', 'Full Row click to Ping', 'Unsed Asset', 'Group')) {
    if (-not $extracted.strings.PSObject.Properties[$key]) { throw "extracted missing $key" }
    if ($missing.strings.PSObject.Properties[$key]) { throw "table key landed in missing.json: $key" }
}
foreach ($banned in @('Open', 'Refreshing ...', '.unity')) {
    if ($extracted.strings.PSObject.Properties[$banned]) { throw "extracted unexpectedly contains $banned" }
}
$mode = $extracted.enums.PSObject.Properties['FR2_RefDrawer.Mode']
if (-not $mode) { throw 'extracted enums missing FR2_RefDrawer.Mode' }
foreach ($member in @('Dependency', 'Type', 'None')) {
    if (-not $mode.Value.PSObject.Properties[$member]) { throw "Mode missing $member" }
}
if ($mode.Value.PSObject.Properties['Extension']) { throw 'fixture Mode must not invent Extension' }
$sort = $extracted.enums.PSObject.Properties['FR2_RefDrawer.Sort']
if (-not $sort) { throw 'extracted enums missing FR2_RefDrawer.Sort' }
foreach ($member in @('Type', 'Path', 'Size')) {
    if (-not $sort.Value.PSObject.Properties[$member]) { throw "Sort missing $member" }
}

$afterOut = Join-Path $work 'extract-after'
& $extract -PluginPath $plugin -OutDir $afterOut
$afterMissing = Get-Content -LiteralPath (Join-Path $afterOut 'missing.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($key in @('Scan project', 'Uses')) {
    if ($afterMissing.strings.PSObject.Properties[$key]) { throw "patched missing.json still has $key" }
}

Assert-Has $window 'FR2Loc.Button("Scan project")'
& (Join-Path $PSScriptRoot 'revert.ps1') -PluginPath $plugin
Assert-Has $window 'protected static GUIContent[] TOOLBARS'
Assert-Lacks $window 'FR2Loc'
if (Test-Path -LiteralPath (Join-Path $scriptDir 'Localization')) {
    throw 'revert left the Localization folder in place'
}

Write-Host 'apply test passed'
