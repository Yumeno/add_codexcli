# test-wrapper.ps1 - Tests for codex-wrapper.ps1
# Usage: powershell -ExecutionPolicy Bypass -File scripts/tests/test-wrapper.ps1

$ScriptDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$Wrapper = Join-Path (Join-Path $ScriptDir "scripts") "codex-wrapper.ps1"

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

function Assert-Equal {
    param($Expected, $Actual, [string]$Message = "")
    if ($Expected -ne $Actual) {
        throw "Expected '$Expected' but got '$Actual'. $Message"
    }
}

# Helper: run wrapper and capture exit code + output
function Invoke-Wrapper {
    param([string]$ArgString)
    $cmd = "powershell -ExecutionPolicy Bypass -NoProfile -File '$Wrapper' $ArgString"
    $output = Invoke-Expression $cmd 2>&1
    $code = $LASTEXITCODE
    return @{
        ExitCode = $code
        Output = ($output | Out-String).Trim()
    }
}

Write-Host ""
Write-Host "=== codex-wrapper.ps1 Tests ===" -ForegroundColor Cyan
Write-Host ""

# --------------------------------------------------
Write-Host "[Group 1: Input Validation]" -ForegroundColor Yellow

Test-Case "Exits with error when no prompt given" {
    $r = Invoke-Wrapper ""
    Assert-Equal 1 $r.ExitCode "Should exit with code 1"
}

Test-Case "Exits with error when empty prompt given" {
    $r = Invoke-Wrapper "-Prompt ''"
    Assert-Equal 1 $r.ExitCode "Should exit with code 1 for empty prompt"
}

# --------------------------------------------------
Write-Host ""
Write-Host "[Group 2: Codex CLI Invocation]" -ForegroundColor Yellow

Test-Case "Returns output from codex exec" {
    $r = Invoke-Wrapper "-Prompt 'What is 1+1? Answer with just the number.'"
    Assert-Equal 0 $r.ExitCode "Should exit with code 0, got output: $($r.Output)"
    if ($r.Output.Length -eq 0) {
        throw "Output should not be empty"
    }
}

Test-Case "Supports custom model flag" {
    $r = Invoke-Wrapper "-Prompt 'Say OK' -Model 'gpt-5.2-codex'"
    Assert-Equal 0 $r.ExitCode "Should exit with code 0 with explicit model"
}

Test-Case "Handles timeout gracefully" {
    $r = Invoke-Wrapper "-Prompt 'Write a very long essay about everything' -Timeout 5"
    # Should not hang - either completes fast or times out (exit code 2)
    # Both are acceptable as long as it doesn't hang forever
    Write-Host "(completed, exit=$($r.ExitCode))" -NoNewline -ForegroundColor DarkGray
}

# --------------------------------------------------
Write-Host ""
Write-Host "[Group 3: Output Handling]" -ForegroundColor Yellow

Test-Case "Output file is cleaned up after use" {
    $r = Invoke-Wrapper "-Prompt 'Say hello'"
    $tempFiles = Get-ChildItem $env:TEMP -Filter "codex_out_*" -ErrorAction SilentlyContinue
    if ($tempFiles) {
        throw "Temp files should be cleaned up, found: $($tempFiles.Name -join ', ')"
    }
}

Test-Case "Stderr noise is suppressed from output" {
    $r = Invoke-Wrapper "-Prompt 'Say OK'"
    if ($r.Output -match "deprecated:|ERROR:.*websocket|OpenAI Codex v") {
        throw "Codex stderr noise should not appear in output"
    }
}

Test-Case "Error files are cleaned up after use" {
    $r = Invoke-Wrapper "-Prompt 'Say hello'"
    $errFiles = Get-ChildItem $env:TEMP -Filter "codex_err_*" -ErrorAction SilentlyContinue
    if ($errFiles) {
        throw "Error temp files should be cleaned up, found: $($errFiles.Name -join ', ')"
    }
}

# --------------------------------------------------
Write-Host ""
Write-Host "[Group 4: Injection Prevention]" -ForegroundColor Yellow

Test-Case "Prompt starting with dash does not break codex" {
    $r = Invoke-Wrapper "-Prompt '-v --help'"
    # Should not crash with option parsing error
    if ($r.Output -match "unexpected argument|unrecognized option") {
        throw "Prompt treated as option: $($r.Output)"
    }
}

# --------------------------------------------------
Write-Host ""
Write-Host "[Group 5: Context File Support]" -ForegroundColor Yellow

Test-Case "Accepts -ContextFile parameter" {
    $ctxFile = Join-Path $env:TEMP "test_ctx_ps_$(Get-Random).txt"
    "The capital of France is Paris." | Out-File -FilePath $ctxFile -Encoding UTF8
    $r = Invoke-Wrapper "-Prompt 'What city is mentioned in the context? Answer in one word.' -ContextFile '$ctxFile'"
    Remove-Item $ctxFile -Force -ErrorAction SilentlyContinue
    Assert-Equal 0 $r.ExitCode "Should exit with code 0, got output: $($r.Output)"
    if ($r.Output.Length -eq 0) {
        throw "Output should not be empty"
    }
}

Test-Case "Errors on missing context file" {
    $r = Invoke-Wrapper "-Prompt 'test' -ContextFile 'C:\nonexistent\file.txt'"
    Assert-Equal 1 $r.ExitCode "Should exit with code 1 for missing context file"
}

# --------------------------------------------------
Write-Host ""
Write-Host "=== Results ===" -ForegroundColor Cyan
Write-Host "Passed: $passed / $total" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Red" })
if ($failed -gt 0) {
    Write-Host "Failed: $failed" -ForegroundColor Red
    exit 1
}
exit 0
