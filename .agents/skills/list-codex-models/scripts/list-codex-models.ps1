# list-codex-models.ps1 - List models the codex CLI is aware of.
#
# Usage: powershell -ExecutionPolicy Bypass -File list-codex-models.ps1 [-Bundled] [-Json]
#   -Bundled  Use only the catalog bundled with the binary (no network).
#   -Json     Print the raw JSON from `codex debug models` instead of names.
#
# Notes:
# - Runs from $env:TEMP so non-ASCII cwd cannot trip codex's WebSocket layer,
#   mirroring the safety dance in codex-wrapper.ps1.
# - No JSON parser dependency beyond ConvertFrom-Json (built into PowerShell).
#   If parsing fails, raw JSON is printed as a fallback.

param(
    [switch]$Bundled,
    [switch]$Json
)

# Sentinel printed to stdout on every failure path so callers that cannot
# separate stdout/stderr can still detect failure from the stdout stream
# alone. Mirrors codex-wrapper.ps1.
$ErrorSentinel = "[CODEX_WRAPPER_ERROR]"

function Fail {
    param([int]$Code, [string]$Message)
    Write-Output ("{0} {1}" -f $ErrorSentinel, $Message)
    [Console]::Error.WriteLine("Error: $Message")
    exit $Code
}

# --- Locate codex executable ---
try {
    $codexSource = (Get-Command codex -ErrorAction Stop).Source
} catch {
    Fail 1 "codex CLI not found in PATH"
}

# npm installs codex.ps1 + codex.cmd; prefer .cmd for Process.Start
$codexCmd = $codexSource -replace '\.ps1$', '.cmd'
if (-not (Test-Path $codexCmd)) {
    $codexCmd = $codexSource
}

# --- Build args ---
$codexArgs = @("debug", "models")
if ($Bundled) {
    $codexArgs += "--bundled"
}

# --- Resolve an ASCII-only working directory (mirrors codex-wrapper.ps1) ---
# On a Windows box with a Japanese username, $env:TEMP itself is non-ASCII
# (`C:\Users\<jp>\AppData\Local\Temp`) and just `Set-Location $env:TEMP`
# reproduces the very WebSocket bug we are trying to dodge.
function Test-IsAscii { param([string]$Path) return ($Path -notmatch '[^\x20-\x7E]') }

function Resolve-AsciiTempDir {
    if (-not [string]::IsNullOrWhiteSpace($env:CODEX_WRAPPER_TEMP)) {
        if (-not (Test-IsAscii $env:CODEX_WRAPPER_TEMP)) {
            Fail 1 "`$env:CODEX_WRAPPER_TEMP must be ASCII-only: $($env:CODEX_WRAPPER_TEMP)"
        }
        return $env:CODEX_WRAPPER_TEMP
    }
    if ((-not [string]::IsNullOrWhiteSpace($env:TEMP)) -and (Test-IsAscii $env:TEMP)) {
        return $env:TEMP
    }
    $cand = "C:\tmp\codex-wrapper-$PID"
    try {
        New-Item -ItemType Directory -Path $cand -Force -ErrorAction Stop | Out-Null
    } catch {
        Fail 1 "`$env:TEMP is non-ASCII ('$($env:TEMP)') and fallback '$cand' is not creatable: $_. Set `$env:CODEX_WRAPPER_TEMP to an ASCII directory."
    }
    return $cand
}
$workDir = Resolve-AsciiTempDir

# --- Run codex from the validated ASCII workdir ---
$prev = Get-Location
Set-Location $workDir
try {
    $raw = & $codexCmd @codexArgs 2>&1 | Out-String
    $exit = $LASTEXITCODE
} finally {
    Set-Location $prev
}

if ($exit -ne 0) {
    Write-Output ("{0} codex debug models exited with code {1}" -f $ErrorSentinel, $exit)
    [Console]::Error.WriteLine("Error: codex debug models exited with code $exit")
    [Console]::Error.WriteLine($raw)
    exit $exit
}

if ($Json) {
    Write-Output $raw.Trim()
    exit 0
}

# Best-effort name extraction via ConvertFrom-Json.
$names = @()
try {
    $parsed = $raw | ConvertFrom-Json -ErrorAction Stop

    function Get-NamesRecursive {
        param($Node)
        if ($null -eq $Node) { return }
        if ($Node -is [System.Collections.IEnumerable] -and -not ($Node -is [string])) {
            foreach ($item in $Node) { Get-NamesRecursive $item }
            return
        }
        if ($Node -is [psobject]) {
            foreach ($prop in $Node.PSObject.Properties) {
                if ($prop.Name -in @("id", "name", "slug") -and $prop.Value -is [string]) {
                    $script:names += $prop.Value
                } else {
                    Get-NamesRecursive $prop.Value
                }
            }
        }
    }

    Get-NamesRecursive $parsed
} catch {
    [Console]::Error.WriteLine("Warning: could not parse JSON; printing raw output.")
    Write-Output $raw.Trim()
    exit 0
}

$unique = $names | Sort-Object -Unique
if ($unique.Count -gt 0) {
    $unique | ForEach-Object { Write-Output $_ }
} else {
    [Console]::Error.WriteLine("Warning: could not extract model names; printing raw JSON.")
    Write-Output $raw.Trim()
}
