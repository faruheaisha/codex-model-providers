<#
    codex-switch-launcher.ps1 - optional short-path launcher for the switcher
    that lives in the codex-model-providers skill.

    Copy this file to $CODEX_HOME\codex-switch.ps1 when you want a short
    command to type:

        powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\codex-switch.ps1" -Preset deepseek

    Keep this file a launcher only. Duplicating the switching logic here is how
    the two files drift apart: a real failure looked like
    "A parameter cannot be found that matches parameter name 'Preset'", because
    the copy on the short path still had the older -Target parameter set.

    Parameters are forwarded to the skill script unchanged. The older spelling
    is still accepted: -Target <preset>, and -Target status for -Status.

    Resolution order for the real script:
      1. $env:CODEX_SWITCH_IMPL (set this to override)
      2. <this folder>\skills\codex-model-providers\scripts\codex-switch.ps1
      3. <parent of this folder>\skills\codex-model-providers\scripts\codex-switch.ps1
      4. $CODEX_HOME\skills\codex-model-providers\scripts\codex-switch.ps1
      5. $HOME\.codex\skills\codex-model-providers\scripts\codex-switch.ps1
      6. $HOME\.agents\skills\codex-model-providers\scripts\codex-switch.ps1
#>

$ErrorActionPreference = 'Stop'

$relative = 'skills\codex-model-providers\scripts\codex-switch.ps1'
$candidates = @()
if ($env:CODEX_SWITCH_IMPL) { $candidates += $env:CODEX_SWITCH_IMPL }
if ($PSScriptRoot) {
    $candidates += (Join-Path $PSScriptRoot $relative)
    $candidates += (Join-Path (Split-Path -Parent $PSScriptRoot) $relative)
}
$codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }
$candidates += (Join-Path $codexHome $relative)
$candidates += (Join-Path (Join-Path $HOME '.codex') $relative)
$candidates += (Join-Path (Join-Path $HOME '.agents') $relative)

$target = $candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
if (-not $target) {
    throw ("codex-model-providers skill not found. Looked in:`n  " + ($candidates -join "`n  "))
}

# No param block on purpose: it keeps switches such as -Preset away from
# PowerShell's parameter binder so any argument the real script accepts works.
$forward = @{}
$switches = @('list', 'status', 'restart')
$index = 0
while ($index -lt $args.Count) {
    $argument = $args[$index]
    $index++

    if ($argument -isnot [string] -or -not $argument.StartsWith('-')) { continue }

    $name = $argument.Substring(1)
    $value = $null
    if ($name -match '^([A-Za-z]+)=(.*)$') {
        $name = $Matches[1]
        $value = $Matches[2]
    }
    if ($name -ieq 'target') { $name = 'preset' }

    if ($null -eq $value -and $switches -contains $name.ToLowerInvariant()) {
        $forward[$name] = $true
        continue
    }

    if ($null -eq $value -and $index -lt $args.Count) {
        $value = $args[$index]
        $index++
    }

    # legacy: -Target status
    if ($name -ieq 'preset' -and $value -eq 'status') {
        $forward['status'] = $true
        continue
    }

    $forward[$name] = $value
}

# Named parameters need hashtable splatting; an array would be positional.
& $target @forward
if ($LASTEXITCODE -is [int]) { exit $LASTEXITCODE }
exit 0
