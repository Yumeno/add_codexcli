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
Write-Host "[Group 4a: Model resolution & config file]" -ForegroundColor Yellow

$ConfPath = Join-Path (Join-Path $ScriptDir "scripts") "codex-wrapper.conf"
$ConfBackup = ""
if (Test-Path $ConfPath) {
    $ConfBackup = Join-Path $env:TEMP "codex_conf_bak_$(Get-Random).txt"
    Copy-Item $ConfPath $ConfBackup -Force
}

Test-Case "-SetModel writes config and exits 0" {
    if (Test-Path $script:ConfPath) { Remove-Item $script:ConfPath -Force }
    $r = Invoke-Wrapper "-SetModel 'gpt-5.2-codex'"
    if ($r.ExitCode -ne 0) { throw "Expected exit 0, got $($r.ExitCode). Output: $($r.Output)" }
    if (-not (Test-Path $script:ConfPath)) { throw "Config file was not written" }
    $content = Get-Content $script:ConfPath -Raw
    if ($content -notmatch '(?m)^model=gpt-5\.2-codex\s*$') {
        throw "Config does not contain expected model= line. Content: $content"
    }
}

Test-Case "-SetModel rejects unsafe characters" {
    $r = Invoke-Wrapper "-SetModel 'foo; rm -rf /'"
    if ($r.ExitCode -ne 1) { throw "Expected exit 1, got $($r.ExitCode)" }
}

Test-Case "-ShowModel reports config source after set" {
    $null = Invoke-Wrapper "-SetModel 'gpt-5.2-codex'"
    $r = Invoke-Wrapper "-ShowModel"
    if ($r.ExitCode -ne 0) { throw "Expected exit 0, got $($r.ExitCode)" }
    if ($r.Output -notmatch 'model=gpt-5\.2-codex.*source: config') {
        throw "Expected config source, got: $($r.Output)"
    }
}

Test-Case "-ShowModel reports cli source when -Model also passed" {
    $r = Invoke-Wrapper "-Model 'gpt-X' -ShowModel"
    if ($r.Output -notmatch 'model=gpt-X.*source: cli') {
        throw "Expected cli source, got: $($r.Output)"
    }
}

Test-Case "-ShowModel reports env source when env set and no -Model" {
    if (Test-Path $script:ConfPath) { Remove-Item $script:ConfPath -Force }
    $env:CODEX_WRAPPER_MODEL = "gpt-env"
    try {
        $r = Invoke-Wrapper "-ShowModel"
        if ($r.Output -notmatch 'model=gpt-env.*source: env') {
            throw "Expected env source, got: $($r.Output)"
        }
    } finally {
        Remove-Item Env:CODEX_WRAPPER_MODEL -ErrorAction SilentlyContinue
    }
}

Test-Case "-ShowModel reports unset when no config and no env" {
    if (Test-Path $script:ConfPath) { Remove-Item $script:ConfPath -Force }
    Remove-Item Env:CODEX_WRAPPER_MODEL -ErrorAction SilentlyContinue
    $r = Invoke-Wrapper "-ShowModel"
    if ($r.Output -notmatch 'model=\(unset') {
        throw "Expected unset state, got: $($r.Output)"
    }
}

# Clean up config so next group runs from a known state.
if (Test-Path $script:ConfPath) { Remove-Item $script:ConfPath -Force }

# --------------------------------------------------
Write-Host ""
Write-Host "[Group 4b: Model announcement on stderr]" -ForegroundColor Yellow

# Helper that captures stdout and stderr into separate streams.
function Invoke-WrapperSplit {
    param([string]$ArgString)
    $stdoutFile = Join-Path $env:TEMP "test_wrapper_stdout_$(Get-Random).txt"
    $stderrFile = Join-Path $env:TEMP "test_wrapper_stderr_$(Get-Random).txt"
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell"
    $psi.Arguments = "-ExecutionPolicy Bypass -NoProfile -File `"$Wrapper`" $ArgString"
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()
    $p.WaitForExit()
    return @{
        ExitCode = $p.ExitCode
        StdOut = $stdout
        StdErr = $stderr
    }
}

Test-Case "Emits MODEL: line on stderr when -Model is given" {
    $r = Invoke-WrapperSplit "-Prompt 'Say OK' -Model 'gpt-5.2-codex'"
    if ($r.StdErr -notmatch '(?m)^MODEL: gpt-5\.2-codex\s*$') {
        throw "Expected 'MODEL: gpt-5.2-codex' on stderr, got: $($r.StdErr)"
    }
}

Test-Case "Does NOT emit MODEL: line on stderr when nothing resolves" {
    # Strip env and config so we exercise the truly-unresolved path.
    if (Test-Path $script:ConfPath) { Remove-Item $script:ConfPath -Force }
    Remove-Item Env:CODEX_WRAPPER_MODEL -ErrorAction SilentlyContinue
    $r = Invoke-WrapperSplit "-Prompt 'Say OK'"
    if ($r.StdErr -match '(?m)^MODEL: ') {
        throw "Should not announce a model when nothing resolves, but got: $($r.StdErr)"
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
# Restore original config (if any) before reporting results.
if (Test-Path $ConfPath) { Remove-Item $ConfPath -Force }
if ($ConfBackup -and (Test-Path $ConfBackup)) {
    Move-Item $ConfBackup $ConfPath -Force
}

Write-Host ""
Write-Host "=== Results ===" -ForegroundColor Cyan
Write-Host "Passed: $passed / $total" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Red" })
if ($failed -gt 0) {
    Write-Host "Failed: $failed" -ForegroundColor Red
    exit 1
}
exit 0
