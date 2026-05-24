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

# --- Locate codex executable ---
try {
    $codexSource = (Get-Command codex -ErrorAction Stop).Source
} catch {
    [Console]::Error.WriteLine("Error: codex CLI not found in PATH")
    exit 1
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

# --- Run codex from %TEMP% to dodge non-ASCII cwd issues ---
$prev = Get-Location
Set-Location $env:TEMP
try {
    $raw = & $codexCmd @codexArgs 2>&1 | Out-String
    $exit = $LASTEXITCODE
} finally {
    Set-Location $prev
}

if ($exit -ne 0) {
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
