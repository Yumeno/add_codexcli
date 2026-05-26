# test-list-models.ps1 - Tests for list-codex-models.ps1
# Usage: powershell -ExecutionPolicy Bypass -File scripts/tests/test-list-models.ps1

$ScriptDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$Helper = Join-Path (Join-Path $ScriptDir "scripts") "list-codex-models.ps1"

$passed = 0
$failed = 0
$total = 0

function Test-Case {
    param([string]$Name, [scriptblock]$Block)
    $script:total++
    Write-Host -NoNewline "  TEST: $Name ... "
    try {
        & $Block
        Write-Host "PASS" -ForegroundColor Green
        $script:passed++
    } catch {
        Write-Host "FAIL: $_" -ForegroundColor Red
        $script:failed++
    }
}

function Invoke-Helper {
    param([string]$ArgString)
    $cmd = "powershell -ExecutionPolicy Bypass -NoProfile -File '$Helper' $ArgString"
    $output = Invoke-Expression $cmd 2>&1
    $code = $LASTEXITCODE
    return @{
        ExitCode = $code
        Output = ($output | Out-String).Trim()
    }
}

Write-Host ""
Write-Host "=== list-codex-models.ps1 Tests ===" -ForegroundColor Cyan
Write-Host ""

Test-Case "Lists at least one model name (default mode)" {
    $r = Invoke-Helper ""
    if ($r.ExitCode -ne 0) { throw "Expected exit 0, got $($r.ExitCode). Output: $($r.Output)" }
    if ([string]::IsNullOrWhiteSpace($r.Output)) { throw "Output should not be empty" }
}

Test-Case "-Json mode emits JSON (starts with { or [)" {
    $r = Invoke-Helper "-Json"
    if ($r.ExitCode -ne 0) { throw "Expected exit 0, got $($r.ExitCode)" }
    $trimmed = $r.Output.TrimStart()
    if (-not ($trimmed.StartsWith("{") -or $trimmed.StartsWith("["))) {
        throw "Expected JSON output, got: $($r.Output)"
    }
}

Test-Case "-Bundled mode also produces output" {
    $r = Invoke-Helper "-Bundled"
    if ($r.ExitCode -ne 0) { throw "Expected exit 0, got $($r.ExitCode). Output: $($r.Output)" }
    if ([string]::IsNullOrWhiteSpace($r.Output)) { throw "Output should not be empty" }
}

Write-Host ""
Write-Host "=== Results ===" -ForegroundColor Cyan
Write-Host "Passed: $passed / $total" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Red" })
if ($failed -gt 0) {
    Write-Host "Failed: $failed" -ForegroundColor Red
    exit 1
}
exit 0
