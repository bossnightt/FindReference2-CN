# Shared helpers. ASCII only: Windows PowerShell 5.1 reads a BOM-less
# ps1 as the system ANSI code page.

function Resolve-PluginPath {
    param([string]$PluginPath)
    if ([string]::IsNullOrWhiteSpace($PluginPath)) { throw 'PluginPath is required.' }
    $full = (Resolve-Path -LiteralPath $PluginPath -ErrorAction Stop).Path
    $scriptDir = Join-Path $full 'Editor\Script'
    if (-not (Test-Path -LiteralPath $scriptDir)) {
        throw "Not a Find Reference 2 root (missing Editor\Script): $full"
    }
    return $full
}

function Find-UnityProjectRoot {
    param([string]$Start)
    $dir = Get-Item -LiteralPath $Start
    while ($null -ne $dir) {
        $assets = Join-Path $dir.FullName 'Assets'
        $settings = Join-Path $dir.FullName 'ProjectSettings'
        if ((Test-Path -LiteralPath $assets) -and (Test-Path -LiteralPath $settings)) {
            return $dir.FullName
        }
        $dir = $dir.Parent
    }
    return $null
}

function Read-SourceFile {
    param([string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $offset = if ($hasBom) { 3 } else { 0 }
    $text = [System.Text.Encoding]::UTF8.GetString($bytes, $offset, $bytes.Length - $offset)
    return [PSCustomObject]@{ Text = $text; HasBom = $hasBom }
}

function Write-SourceFile {
    param([string]$Path, [string]$Text, [bool]$HasBom)
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $enc = New-Object System.Text.UTF8Encoding($HasBom)
    [System.IO.File]::WriteAllText($Path, $Text, $enc)
}

function Get-PluginScriptFiles {
    param([string]$PluginRoot)
    $scriptDir = Join-Path $PluginRoot 'Editor\Script'
    $list = @()
    foreach ($file in (Get-ChildItem -LiteralPath $scriptDir -Recurse -File -Filter *.cs)) {
        $rel = $file.FullName.Substring($PluginRoot.Length).TrimStart('\', '/')
        if ($rel -match '(^|[\\/])Localization[\\/]') { continue }
        $list += [PSCustomObject]@{ Rel = $rel; Full = $file.FullName }
    }
    return $list
}

function Escape-JsonString {
    param([string]$Text)
    if ($null -eq $Text) { return '""' }
    $s = $Text.Replace('\', '\\').Replace('"', '\"').Replace("`r", '\r').Replace("`n", '\n').Replace("`t", '\t')
    return '"' + $s + '"'
}

function Write-StringMapJson {
    param([string]$Path, $Strings, $Enums)
    $nl = "`n"
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('{')
    [void]$sb.Append($nl)
    [void]$sb.Append('  "strings": {')
    [void]$sb.Append($nl)
    $keys = @($Strings.Keys | Sort-Object)
    for ($i = 0; $i -lt $keys.Count; $i++) {
        $comma = $(if ($i -lt $keys.Count - 1) { ',' } else { '' })
        [void]$sb.Append('    ' + (Escape-JsonString $keys[$i]) + ': ' + (Escape-JsonString $Strings[$keys[$i]]) + $comma + $nl)
    }
    [void]$sb.Append('  },')
    [void]$sb.Append($nl)
    [void]$sb.Append('  "enums": {')
    [void]$sb.Append($nl)
    $ekeys = @($Enums.Keys | Sort-Object)
    for ($i = 0; $i -lt $ekeys.Count; $i++) {
        [void]$sb.Append('    ' + (Escape-JsonString $ekeys[$i]) + ': {')
        [void]$sb.Append($nl)
        $members = $Enums[$ekeys[$i]]
        $mkeys = @($members.Keys | Sort-Object)
        for ($j = 0; $j -lt $mkeys.Count; $j++) {
            $comma = $(if ($j -lt $mkeys.Count - 1) { ',' } else { '' })
            [void]$sb.Append('      ' + (Escape-JsonString $mkeys[$j]) + ': ' + (Escape-JsonString $members[$mkeys[$j]]) + $comma + $nl)
        }
        $comma = $(if ($i -lt $ekeys.Count - 1) { ',' } else { '' })
        [void]$sb.Append('    }' + $comma + $nl)
    }
    [void]$sb.Append('  }')
    [void]$sb.Append($nl)
    [void]$sb.Append('}')
    [void]$sb.Append($nl)
    Write-SourceFile $Path $sb.ToString() $false
}
