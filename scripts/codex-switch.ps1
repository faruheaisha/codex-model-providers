<#
    codex-switch.ps1 - switch the active model provider of Codex by rewriting
    the top-level keys of $CODEX_HOME/config.toml (Windows PowerShell 5.1+).

    Presets live in $CODEX_HOME/provider-presets.conf (created with defaults on
    first run):

        [deepseek]
        model = deepseek-flash
        model_provider = deepseek
        model_catalog_json = ~/.codex/model-catalog.deepseek.json
        web_search = disabled

    An empty value removes that key from config.toml, which is how you go back
    to the built-in OpenAI provider and its stock model catalog.

    Usage:
        .\codex-switch.ps1 -List
        .\codex-switch.ps1 -Preset deepseek
        .\codex-switch.ps1 -Status
        .\codex-switch.ps1 -Preset gpt -Restart
#>
[CmdletBinding()]
param(
    [string]$Preset,
    [switch]$List,
    [switch]$Status,
    [switch]$Restart,
    [string]$ConfigPath,
    [string]$PresetsPath
)

$ErrorActionPreference = 'Stop'

$codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }
if (-not $ConfigPath) { $ConfigPath = Join-Path $codexHome 'config.toml' }
if (-not $PresetsPath) { $PresetsPath = Join-Path $codexHome 'provider-presets.conf' }

$defaultPresets = @'
# Presets used by codex-switch.ps1 / codex-switch.sh.
# Empty value = remove the key from config.toml.

[gpt]
model = gpt-5.6-sol
model_provider =
model_catalog_json =
web_search =

[deepseek]
model = deepseek-flash
model_provider = deepseek
model_catalog_json = ~/.codex/model-catalog.deepseek.json
web_search = disabled
'@

if (-not (Test-Path -LiteralPath $PresetsPath)) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $PresetsPath) | Out-Null
    Set-Content -LiteralPath $PresetsPath -Value $defaultPresets -Encoding UTF8
    Write-Host "Created default presets: $PresetsPath"
}

function Read-Presets {
    param([string]$Path)
    $result = [ordered]@{}
    $current = $null
    foreach ($line in Get-Content -LiteralPath $Path) {
        $trimmed = $line.Trim()
        if ($trimmed -eq '' -or $trimmed.StartsWith('#')) { continue }
        if ($trimmed -match '^\[(.+)\]$') {
            $current = $Matches[1].Trim()
            if (-not $result.Contains($current)) { $result[$current] = [ordered]@{} }
            continue
        }
        if ($null -eq $current) { continue }
        if ($trimmed -match '^([A-Za-z0-9_\-\.]+)\s*=\s*(.*)$') {
            $key = $Matches[1]
            $value = $Matches[2].Trim().Trim('"').Trim("'")
            if ($value.StartsWith('~')) {
                $value = Join-Path $HOME $value.Substring(1).TrimStart('\', '/')
            }
            $result[$current][$key] = $value
        }
    }
    return $result
}

$presets = Read-Presets -Path $PresetsPath

if ($List -or (-not $Preset -and -not $Status)) {
    Write-Host "Presets in $PresetsPath"
    foreach ($name in $presets.Keys) {
        $keys = ($presets[$name].Keys | Where-Object { $presets[$name][$_] -ne '' }) -join ', '
        Write-Host ("  {0,-12} -> {1}" -f $name, $keys)
    }
    Write-Host ''
    Write-Host 'Use: codex-switch.ps1 -Preset <name>'
    return
}

if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "config.toml not found: $ConfigPath" }

$raw = Get-Content -LiteralPath $ConfigPath
$firstTable = -1
for ($i = 0; $i -lt $raw.Count; $i++) {
    if ($raw[$i] -match '^\s*\[') { $firstTable = $i; break }
}
if ($firstTable -lt 0) { $firstTable = $raw.Count }
$header = if ($firstTable -gt 0) { @($raw[0..($firstTable - 1)]) } else { @() }
$body = if ($firstTable -lt $raw.Count) { @($raw[$firstTable..($raw.Count - 1)]) } else { @() }

function Get-CurrentKey {
    param([string[]]$Lines, [string]$Key)
    foreach ($line in $Lines) {
        if ($line -match ("^\s*" + [regex]::Escape($Key) + "\s*=\s*(.+?)\s*$")) {
            return $Matches[1].Trim('"')
        }
    }
    return $null
}

if ($Status) {
    Write-Host "config : $ConfigPath"
    Write-Host "model  : $(Get-CurrentKey $header 'model')"
    $provider = Get-CurrentKey $header 'model_provider'
    if (-not $provider) { $provider = 'openai (built-in)' }
    Write-Host "provider: $provider"
    Write-Host "catalog: $(Get-CurrentKey $header 'model_catalog_json')"
    Write-Host "web_search: $(Get-CurrentKey $header 'web_search')"
    return
}

if (-not $presets.Contains($Preset)) {
    throw "Unknown preset '$Preset'. Available: $($presets.Keys -join ', ')"
}
$target = $presets[$Preset]

# Managed keys: every key any preset defines, so switching away cleans up.
$managed = New-Object System.Collections.Generic.HashSet[string]
foreach ($name in $presets.Keys) {
    foreach ($key in $presets[$name].Keys) { [void]$managed.Add($key) }
}

$backupDir = Join-Path $codexHome 'backups'
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
$backupPath = Join-Path $backupDir ("config.toml." + (Get-Date -Format 'yyyyMMdd-HHmmss'))
Copy-Item -LiteralPath $ConfigPath -Destination $backupPath -Force

$seen = @{}
$newHeader = New-Object System.Collections.Generic.List[string]
foreach ($line in $header) {
    if ($line -match '^\s*([A-Za-z0-9_\-\.]+)\s*=') {
        $key = $Matches[1]
        if ($managed.Contains($key)) {
            $seen[$key] = $true
            $value = $target[$key]
            if ($value) { $newHeader.Add("$key = `"$value`"") }
            continue
        }
        $newHeader.Add($line)
        continue
    }
    if ($line.Trim() -eq '') { continue }
    $newHeader.Add($line)
}
foreach ($key in $target.Keys) {
    if (-not $seen.ContainsKey($key) -and $target[$key]) {
        $newHeader.Add("$key = `"$($target[$key])`"")
    }
}
if (-not $seen.ContainsKey('model') -and $target['model']) {
    $newHeader.Insert(0, "model = `"$($target['model'])`"")
}

$output = @()
$output += $newHeader
if ($body.Count -gt 0) {
    $output += ''
    $output += $body
}
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllLines($ConfigPath, [string[]]$output, $utf8NoBom)

Write-Host "Switched Codex to preset: $Preset"
Write-Host "  backup: $backupPath"
Write-Host ''
Write-Host 'Start a NEW task in Codex; running tasks keep their provider.'

if ($Restart) {
    Write-Host ''
    Write-Host 'Restarting the Codex desktop app...'
    Get-Process -Name ChatGPT -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 2
    $codexCmd = (Get-Command codex -ErrorAction SilentlyContinue).Source
    if (-not $codexCmd) { $codexCmd = Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\bin\codex.exe' }
    if ($codexCmd -and (Test-Path -LiteralPath $codexCmd)) {
        Start-Process -FilePath $codexCmd -ArgumentList 'app'
    } else {
        Write-Warning 'Could not locate the codex CLI; start the Codex app manually.'
    }
}
