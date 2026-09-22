# Inject FindReference2-CN into a Find Reference 2 install.
#   .\apply.ps1 -PluginPath "D:\...\Assets\FindReference2"
param(
    [Parameter(Mandatory = $true)][string]$PluginPath,
    [switch]$NoBackup
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'common.ps1')

$pluginRoot = Resolve-PluginPath $PluginPath

if (-not $NoBackup) {
    $projectRoot = Find-UnityProjectRoot $pluginRoot
    $backupBase = if ($projectRoot) { Split-Path -Parent $projectRoot } else { Split-Path -Parent $pluginRoot }
    $backupDir = Join-Path $backupBase 'FindReference2-CN-backups'
    if (-not (Test-Path -LiteralPath $backupDir)) {
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    }
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $zip = Join-Path $backupDir "FindReference2_$stamp.zip"
    if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
    Write-Output "Backup : $zip"
    Compress-Archive -Path $pluginRoot -DestinationPath $zip -CompressionLevel Optimal
}

$locDir = Join-Path $pluginRoot 'Editor\Script\Localization'
if (-not (Test-Path -LiteralPath $locDir)) {
    New-Item -ItemType Directory -Path $locDir -Force | Out-Null
}
foreach ($name in @('FR2Loc.cs', 'FR2Json.cs')) {
    $src = Join-Path $root "runtime/$name"
    if (-not (Test-Path -LiteralPath $src)) { throw "Missing runtime/$name" }
    Write-SourceFile (Join-Path $locDir $name) (Read-SourceFile $src).Text $true
}
$tableSrc = Join-Path $root 'table/zh-CN.json'
if (-not (Test-Path -LiteralPath $tableSrc)) { throw 'Missing table/zh-CN.json' }
Write-SourceFile (Join-Path $locDir 'fr2-zh-CN.json') (Read-SourceFile $tableSrc).Text $false
Write-Output "Runtime: $locDir"

$api = @(
    @{ From = 'GUILayout.Button('; To = 'FR2Loc.Button(' },
    @{ From = 'GUILayout.Label('; To = 'FR2Loc.Label(' },
    @{ From = 'GUILayout.Toggle('; To = 'FR2Loc.Toggle(' },
    @{ From = 'EditorGUILayout.HelpBox('; To = 'FR2Loc.HelpBox(' },
    @{ From = 'EditorGUILayout.IntSlider('; To = 'FR2Loc.IntSlider(' },
    @{ From = 'EditorGUILayout.Foldout('; To = 'FR2Loc.Foldout(' },
    @{ From = 'EditorGUILayout.ColorField('; To = 'FR2Loc.ColorField(' },
    @{ From = 'EditorGUILayout.EnumPopup('; To = 'FR2Loc.EnumPopup(' }
)

$script:toolbarsMethod = @'
static GUIContent[] Toolbars()
{
    return new[]
    {
        FR2Loc.C("Uses"),
        FR2Loc.C("Used By"),
        FR2Loc.C("Duplicate"),
        FR2Loc.C("GUIDs"),
        FR2Loc.C("Unused Assets"),
        FR2Loc.C("Uses In Build")
    };
}
'@

function Apply-Hooks {
    param([string]$Rel, [string]$Text)
    $count = 0
    $leaf = Split-Path -Leaf $Rel
    if ($leaf -eq 'FR2_WindowBase.cs') {
        $toolbarRe = '(?s)protected static GUIContent\[\] TOOLBARS\s*=\s*\{.*?\};'
        $next = [regex]::Replace($Text, $toolbarRe, { param($m) $script:toolbarsMethod }, 1)
        if ($next -eq $Text) { Write-Warning "Hook not found in ${Rel}: TOOLBARS field" }
        else { $Text = $next; $count++ }
        $idNext = [regex]::Replace($Text, '(?<![\w])TOOLBARS(?![\w])', 'Toolbars()')
        if ($idNext -eq $Text) { Write-Warning "Hook not found in ${Rel}: TOOLBARS uses" }
        else { $Text = $idNext; $count++ }
        $commitRe = 'FR2Loc\.Button\(\s*"Commit Selection \[" \+ FR2_Selection\.SelectionCount \+ "\]"\s*,\s*EditorStyles\.toolbarButton\s*\)'
        $commitTo = 'FR2Loc.Button("Commit Selection [{0}]", FR2_Selection.SelectionCount, EditorStyles.toolbarButton)'
        $cNext = [regex]::Replace($Text, $commitRe, $commitTo, 1)
        if ($cNext -eq $Text) { Write-Warning "Hook not found in ${Rel}: Commit Selection button" }
        else { $Text = $cNext; $count++ }
    }
    if ($leaf -eq 'FR2_Ref.cs') {
        $re = 'GUI\.Label\(r, label \+ " \(" \+ childCount \+ "\)", EditorStyles\.boldLabel\);'
        $to = 'GUI.Label(r, FR2Loc.T(label) + " (" + childCount + ")", EditorStyles.boldLabel);'
        $n = [regex]::Replace($Text, $re, $to, 1)
        if ($n -eq $Text) { Write-Warning "Hook not found in ${Rel}: ref group label" }
        else { $Text = $n; $count++ }
    }
    if ($leaf -eq 'FR2_AssetType.cs') {
        $from = 'GUI.Label(r, id, EditorStyles.boldLabel);'
        $to = 'GUI.Label(r, FR2Loc.T(id), EditorStyles.boldLabel);'
        if ($Text.Contains($from)) { $Text = $Text.Replace($from, $to); $count++ }
        else { Write-Warning "Hook not found in ${Rel}: ignore group label" }
    }
    return [PSCustomObject]@{ Text = $Text; Count = $count }
}

$patched = 0
$skipped = 0
$edits = 0
foreach ($t in (Get-PluginScriptFiles $pluginRoot)) {
    $file = Read-SourceFile $t.Full
    if ($file.Text.Contains('FR2Loc.')) {
        Write-Output ("  skip   {0} (already patched)" -f $t.Rel)
        $skipped++
        continue
    }
    $text = $file.Text
    $count = 0
    foreach ($r in $api) {
        $hits = ([regex]::Matches($text, [regex]::Escape($r.From))).Count
        if ($hits -gt 0) {
            $text = $text.Replace($r.From, $r.To)
            $count += $hits
        }
    }
    $hooked = Apply-Hooks $t.Rel $text
    $text = $hooked.Text
    $count += $hooked.Count
    if ($count -eq 0) {
        Write-Output ("  skip   {0} (nothing to rewrite)" -f $t.Rel)
        $skipped++
        continue
    }
    Write-SourceFile $t.Full $text $file.HasBom
    Write-Output ("  patch  {0}  ({1} edits)" -f $t.Rel, $count)
    $patched++
    $edits += $count
}

Write-Output ''
Write-Output '--- apply result ---'
Write-Output ("patched files : {0}" -f $patched)
Write-Output ("skipped files : {0}" -f $skipped)
Write-Output ("total edits   : {0}" -f $edits)
