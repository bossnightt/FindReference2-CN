# Scan Find Reference 2 editor scripts for localization keys.
#   .\extract.ps1 -PluginPath "D:\...\Assets\FindReference2"
param(
    [Parameter(Mandatory = $true)][string]$PluginPath,
    [string]$TablePath,
    [string]$OutDir
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'common.ps1')

if (-not $TablePath) { $TablePath = Join-Path $root 'table\zh-CN.json' }
if (-not $OutDir) { $OutDir = Join-Path $root 'out' }

$pluginRoot = Resolve-PluginPath $PluginPath
$files = @(Get-PluginScriptFiles $pluginRoot)

function ConvertFrom-CSharpString {
    param([string]$Raw)
    $sb = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt $Raw.Length; $i++) {
        $c = $Raw[$i]
        if ($c -ne '\') { [void]$sb.Append($c); continue }
        if ($i + 1 -ge $Raw.Length) { [void]$sb.Append($c); break }
        $i++
        switch ($Raw[$i]) {
            'n' { [void]$sb.Append("`n") }
            'r' { [void]$sb.Append("`r") }
            't' { [void]$sb.Append("`t") }
            '\' { [void]$sb.Append('\') }
            '"' { [void]$sb.Append('"') }
            default { [void]$sb.Append($Raw[$i]) }
        }
    }
    return $sb.ToString()
}

function Get-StringLiterals {
    param([string]$Text)
    $found = @()
    foreach ($m in [regex]::Matches($Text, '"((?:\\.|[^"\\])*)"')) {
        $found += (ConvertFrom-CSharpString $m.Groups[1].Value)
    }
    return $found
}

function Get-Balanced {
    param([string]$Text, [int]$OpenIndex, [char]$Open, [char]$Close)
    $depth = 0
    for ($i = $OpenIndex; $i -lt $Text.Length; $i++) {
        $c = $Text[$i]
        if ($c -eq '"') {
            $i++
            while ($i -lt $Text.Length) {
                if ($Text[$i] -eq '\') { $i += 2; continue }
                if ($Text[$i] -eq '"') { break }
                $i++
            }
            continue
        }
        if ($c -eq $Open) { $depth++ }
        elseif ($c -eq $Close) {
            $depth--
            if ($depth -eq 0) {
                return $Text.Substring($OpenIndex + 1, $i - $OpenIndex - 1)
            }
        }
    }
    return $null
}

function Add-CallStrings {
    param($Set, [string]$Text, [string]$CallPattern)
    foreach ($m in [regex]::Matches($Text, $CallPattern)) {
        $open = $m.Index + $m.Length - 1
        $body = Get-Balanced $Text $open '(' ')'
        if ($null -eq $body) { continue }
        foreach ($lit in (Get-StringLiterals $body)) {
            if ($lit.Length -gt 0) { [void]$Set.Add($lit) }
        }
    }
}

function Get-EnumMemberMap {
    param([string]$Text, [string]$EnumName)
    $em = [regex]::Match($Text, "enum\s+$EnumName\b[^{]*\{")
    if (-not $em.Success) { return $null }
    $open = $Text.IndexOf('{', $em.Index)
    $body = Get-Balanced $Text $open '{' '}'
    if (-not $body) { return $null }
    $body = [regex]::Replace($body, '//[^\r\n]*', '')
    $members = @{}
    foreach ($part in ($body -split ',')) {
        $id = (($part -split '=')[0]).Trim()
        if ($id -match '^[A-Za-z_][A-Za-z0-9_]*$') { $members[$id] = $true }
    }
    if ($members.Count -eq 0) { return $null }
    return $members
}

$strings = New-Object 'System.Collections.Generic.HashSet[string]'
$enums = @{}
$fileTexts = @{}

$callPatterns = @(
    '(?:GUILayout|FR2Loc)\.(?:Button|Label|Toggle)\(',
    '(?:EditorGUILayout|FR2Loc)\.(?:HelpBox|IntSlider|ColorField|Foldout|EnumPopup)\(',
    'FR2Loc\.[CT]\(',
    'DrawToggle(?:Toolbar)?\('
)

foreach ($f in $files) {
    $fileTexts[$f.Full] = (Read-SourceFile $f.Full).Text
}
foreach ($f in $files) {
    $text = $fileTexts[$f.Full]
    foreach ($pat in $callPatterns) { Add-CallStrings $strings $text $pat }

    foreach ($m in [regex]::Matches($text, 'new\s+AssetType\(')) {
        $open = $m.Index + $m.Length - 1
        $body = Get-Balanced $text $open '(' ')'
        if ($body) {
            $first = [regex]::Match($body, '"((?:\\.|[^"\\])*)"')
            if ($first.Success) {
                $lit = ConvertFrom-CSharpString $first.Groups[1].Value
                if ($lit.Length -gt 0) { [void]$strings.Add($lit) }
            }
        }
    }

    foreach ($m in [regex]::Matches($text, '(?s)GUIContent\[\]\s+TOOLBARS\s*=\s*\{')) {
        $open = $text.IndexOf('{', $m.Index)
        $body = Get-Balanced $text $open '{' '}'
        if ($body) {
            foreach ($lit in (Get-StringLiterals $body)) {
                if ($lit.Length -gt 0) { [void]$strings.Add($lit) }
            }
        }
    }

    foreach ($m in [regex]::Matches($text, '\bstring\s+GetGroup\s*\(')) {
        $open = $text.IndexOf('{', $m.Index)
        if ($open -lt 0) { continue }
        $body = Get-Balanced $text $open '{' '}'
        if ($body) {
            foreach ($lit in (Get-StringLiterals $body)) {
                if ($lit.Length -gt 0) { [void]$strings.Add($lit) }
            }
        }
    }

    foreach ($m in [regex]::Matches($text, 'Lable\s*=\s*"((?:\\.|[^"\\])*)"')) {
        $lit = ConvertFrom-CSharpString $m.Groups[1].Value
        if ($lit.Length -gt 0) { [void]$strings.Add($lit) }
    }

    foreach ($m in [regex]::Matches($text, '\(([\w\.]+)\)\s*(?:EditorGUILayout|FR2Loc)\.EnumPopup')) {
        $typeName = $m.Groups[1].Value
        $enumName = $typeName
        $outer = ''
        $dot = $typeName.LastIndexOf('.')
        if ($dot -ge 0) {
            $outer = $typeName.Substring(0, $dot)
            $enumName = $typeName.Substring($dot + 1)
        }
        $members = $null
        foreach ($candidate in $fileTexts.Values) {
            if ($outer -and $candidate.IndexOf($outer) -lt 0) { continue }
            $members = Get-EnumMemberMap $candidate $enumName
            if ($members) { break }
        }
        if (-not $members) { continue }
        if (-not $enums.ContainsKey($typeName)) { $enums[$typeName] = @{} }
        foreach ($id in $members.Keys) { $enums[$typeName][$id] = $true }
    }
}

$table = Get-Content -LiteralPath $TablePath -Raw -Encoding UTF8 | ConvertFrom-Json
function Get-TableString {
    param($Name)
    $p = $table.strings.PSObject.Properties[$Name]
    if ($p) { return [string]$p.Value }
    return $null
}
function Get-TableEnum {
    param($TypeName, $Member)
    $scope = $table.enums.PSObject.Properties[$TypeName]
    if (-not $scope) { return $null }
    $p = $scope.Value.PSObject.Properties[$Member]
    if ($p) { return [string]$p.Value }
    return $null
}

$extractedStrings = @{}
$missingStrings = @{}
foreach ($key in $strings) {
    $zh = Get-TableString $key
    if ($zh) { $extractedStrings[$key] = $zh }
    else {
        $extractedStrings[$key] = $key
        $missingStrings[$key] = $key
    }
}
$extractedEnums = @{}
$missingEnums = @{}
foreach ($typeName in $enums.Keys) {
    $extractedEnums[$typeName] = @{}
    $missingEnums[$typeName] = @{}
    foreach ($member in $enums[$typeName].Keys) {
        $zh = Get-TableEnum $typeName $member
        if ($zh) { $extractedEnums[$typeName][$member] = $zh }
        else {
            $extractedEnums[$typeName][$member] = $member
            $missingEnums[$typeName][$member] = $member
        }
    }
    if ($missingEnums[$typeName].Count -eq 0) { $missingEnums.Remove($typeName) }
}

if (-not (Test-Path -LiteralPath $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
}
Write-StringMapJson (Join-Path $OutDir 'extracted.json') $extractedStrings $extractedEnums
Write-StringMapJson (Join-Path $OutDir 'missing.json') $missingStrings $missingEnums
Write-Host ("strings: {0}   missing strings: {1}" -f $extractedStrings.Count, $missingStrings.Count)
