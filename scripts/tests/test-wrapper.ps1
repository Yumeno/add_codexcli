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

# Helper: run wrapper with explicit string[] args (no Invoke-Expression).
# Pass arguments as an array so quoting survives the child process boundary.
function Invoke-Wrapper {
    param([string[]]$Arguments = @())
    $output = & powershell -ExecutionPolicy Bypass -NoProfile -File $Wrapper @Arguments 2>&1
    $code = $LASTEXITCODE
    return @{
        ExitCode = $code
        Output = ($output | Out-String).Trim()
    }
}

# Helper: same as Invoke-Wrapper but separates stdout/stderr.
function Invoke-WrapperSplit {
    param([string[]]$Arguments = @())
    $stderrFile = Join-Path $env:TEMP "test_wrapper_stderr_$(Get-Random).txt"
    try {
        $stdout = & powershell -ExecutionPolicy Bypass -NoProfile -File $Wrapper @Arguments 2> $stderrFile
        $code = $LASTEXITCODE
        $stderr = if (Test-Path $stderrFile) { Get-Content $stderrFile -Raw -ErrorAction SilentlyContinue } else { "" }
        return @{
            ExitCode = $code
            StdOut = ($stdout | Out-String)
            StdErr = ($stderr | Out-String)
        }
    } finally {
        Remove-Item $stderrFile -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ""
Write-Host "=== codex-wrapper.ps1 Tests ===" -ForegroundColor Cyan
Write-Host ""

# --------------------------------------------------
Write-Host "[Group 1: Input Validation]" -ForegroundColor Yellow

Test-Case "Exits with error when no prompt given" {
    $r = Invoke-Wrapper @()
    Assert-Equal 1 $r.ExitCode "Should exit with code 1"
}

Test-Case "Exits with error when empty prompt given" {
    $r = Invoke-Wrapper @("-Prompt", "")
    Assert-Equal 1 $r.ExitCode "Should exit with code 1 for empty prompt"
}

# --------------------------------------------------
Write-Host ""
Write-Host "[Group 2: Codex CLI Invocation]" -ForegroundColor Yellow

Test-Case "Returns output from codex exec" {
    $r = Invoke-Wrapper @("-Prompt", "What is 1+1? Answer with just the number.")
    Assert-Equal 0 $r.ExitCode "Should exit with code 0, got output: $($r.Output)"
    if ($r.Output.Length -eq 0) {
        throw "Output should not be empty"
    }
}

Test-Case "Supports custom model flag" {
    $r = Invoke-Wrapper @("-Prompt", "Say OK", "-Model", "gpt-5.5")
    Assert-Equal 0 $r.ExitCode "Should exit with code 0 with explicit model"
}

Test-Case "Handles timeout gracefully" {
    $r = Invoke-Wrapper @("-Prompt", "Write a very long essay about everything", "-Timeout", "5")
    # Should not hang - either completes fast or times out (exit code 2)
    Write-Host "(completed, exit=$($r.ExitCode))" -NoNewline -ForegroundColor DarkGray
}

# --------------------------------------------------
Write-Host ""
Write-Host "[Group 3: Output Handling]" -ForegroundColor Yellow

Test-Case "Output file is cleaned up after use" {
    $r = Invoke-Wrapper @("-Prompt", "Say hello")
    $tempFiles = Get-ChildItem $env:TEMP -Filter "codex_out_*" -ErrorAction SilentlyContinue
    if ($tempFiles) {
        throw "Temp files should be cleaned up, found: $($tempFiles.Name -join ', ')"
    }
}

Test-Case "Stderr noise is suppressed from output" {
    $r = Invoke-Wrapper @("-Prompt", "Say OK")
    if ($r.Output -match "deprecated:|ERROR:.*websocket|OpenAI Codex v") {
        throw "Codex stderr noise should not appear in output"
    }
}

Test-Case "Error files are cleaned up after use" {
    $r = Invoke-Wrapper @("-Prompt", "Say hello")
    $errFiles = Get-ChildItem $env:TEMP -Filter "codex_err_*" -ErrorAction SilentlyContinue
    if ($errFiles) {
        throw "Error temp files should be cleaned up, found: $($errFiles.Name -join ', ')"
    }
}

# --------------------------------------------------
Write-Host ""
Write-Host "[Group 4: Injection Prevention]" -ForegroundColor Yellow

Test-Case "Prompt starting with dash does not break codex" {
    $r = Invoke-Wrapper @("-Prompt", "-v --help")
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
    $r = Invoke-Wrapper @("-SetModel", "gpt-5.5")
    if ($r.ExitCode -ne 0) { throw "Expected exit 0, got $($r.ExitCode). Output: $($r.Output)" }
    if (-not (Test-Path $script:ConfPath)) { throw "Config file was not written" }
    $content = Get-Content $script:ConfPath -Raw
    if ($content -notmatch '(?m)^model=gpt-5\.5\s*$') {
        throw "Config does not contain expected model= line. Content: $content"
    }
}

Test-Case "-SetModel rejects unsafe characters" {
    $r = Invoke-Wrapper @("-SetModel", "foo; rm -rf /")
    if ($r.ExitCode -ne 1) { throw "Expected exit 1, got $($r.ExitCode)" }
}

Test-Case "-Model rejects unsafe characters too" {
    $r = Invoke-Wrapper @("-Prompt", "Say OK", "-Model", "foo`nMODEL: spoof")
    if ($r.ExitCode -ne 1) { throw "Expected exit 1 for unsafe -Model, got $($r.ExitCode). Output: $($r.Output)" }
}

Test-Case "Config with unsafe model is rejected on read" {
    # The parser only ever reads the first model= line, so a newline-injected
    # value would still parse cleanly. Use a same-line unsafe value (semicolon
    # + space) to actually exercise validation of the conf-sourced model.
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($script:ConfPath, "model=foo bar; rm -rf /`n", $utf8NoBom)
    $r = Invoke-Wrapper @("-Prompt", "Say OK")
    if ($r.ExitCode -ne 1) {
        throw "Expected exit 1 for tampered conf, got $($r.ExitCode). Output: $($r.Output)"
    }
    if (Test-Path $script:ConfPath) { Remove-Item $script:ConfPath -Force }
}

Test-Case "Comment-only conf does not crash --show-model" {
    # Regression for codex's review: an awk/grep no-match used to kill the
    # whole script under set -euo pipefail. PS doesn't have that exact bug,
    # but symmetry across platforms is worth pinning down.
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($script:ConfPath, "# nothing useful here`n", $utf8NoBom)
    $r = Invoke-Wrapper @("-ShowModel")
    if ($r.ExitCode -ne 0) {
        throw "Expected exit 0 with comment-only conf, got $($r.ExitCode). Output: $($r.Output)"
    }
    if ($r.Output -notmatch 'model=\(unset') {
        throw "Expected unset state for comment-only conf, got: $($r.Output)"
    }
    if (Test-Path $script:ConfPath) { Remove-Item $script:ConfPath -Force }
}

Test-Case "Prompt starting with -- is accepted (not treated as missing value)" {
    # Regression: require_value used to reject any value starting with "--",
    # breaking prompts like "--help" which are perfectly legal to send to codex.
    $r = Invoke-Wrapper @("-Prompt", "--help")
    # We don't care what codex itself says; we only care that the wrapper
    # didn't bail out with a "requires a value" error before invoking codex.
    if ($r.Output -match "requires a value") {
        throw "Wrapper rejected -- prefixed prompt as missing value: $($r.Output)"
    }
}

Test-Case "-ShowModel reports config source after set" {
    $null = Invoke-Wrapper @("-SetModel", "gpt-5.5")
    $r = Invoke-Wrapper @("-ShowModel")
    if ($r.ExitCode -ne 0) { throw "Expected exit 0, got $($r.ExitCode)" }
    if ($r.Output -notmatch 'model=gpt-5\.5.*source: config') {
        throw "Expected config source, got: $($r.Output)"
    }
}

Test-Case "-ShowModel reports cli source when -Model also passed" {
    $r = Invoke-Wrapper @("-Model", "gpt-X", "-ShowModel")
    if ($r.Output -notmatch 'model=gpt-X.*source: cli') {
        throw "Expected cli source, got: $($r.Output)"
    }
}

Test-Case "-ShowModel reports env source when env set and no -Model" {
    if (Test-Path $script:ConfPath) { Remove-Item $script:ConfPath -Force }
    $env:CODEX_WRAPPER_MODEL = "gpt-env"
    try {
        $r = Invoke-Wrapper @("-ShowModel")
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
    $r = Invoke-Wrapper @("-ShowModel")
    if ($r.Output -notmatch 'model=\(unset') {
        throw "Expected unset state, got: $($r.Output)"
    }
}

# Clean up config so next group runs from a known state.
if (Test-Path $script:ConfPath) { Remove-Item $script:ConfPath -Force }

# --------------------------------------------------
Write-Host ""
Write-Host "[Group 4b: Model announcement on stderr]" -ForegroundColor Yellow

Test-Case "Emits MODEL: line on stderr when -Model is given" {
    $r = Invoke-WrapperSplit @("-Prompt", "Say OK", "-Model", "gpt-5.5")
    # PowerShell's 2> redirection prefixes the line with "powershell.exe :" wrapping,
    # so match the MODEL token anywhere in stderr rather than requiring a clean line start.
    if ($r.StdErr -notmatch 'MODEL:\s*gpt-5\.5') {
        throw "Expected 'MODEL: gpt-5.5' on stderr, got: $($r.StdErr)"
    }
}

Test-Case "Does NOT emit MODEL: line on stderr when nothing resolves" {
    if (Test-Path $script:ConfPath) { Remove-Item $script:ConfPath -Force }
    Remove-Item Env:CODEX_WRAPPER_MODEL -ErrorAction SilentlyContinue
    $r = Invoke-WrapperSplit @("-Prompt", "Say OK")
    # Match the token anywhere; the wrapper must stay completely silent on
    # model when there is nothing to announce.
    if ($r.StdErr -match 'MODEL:\s*\S') {
        throw "Should not announce a model when nothing resolves, but got: $($r.StdErr)"
    }
}

# --------------------------------------------------
Write-Host ""
Write-Host "[Group 4c: Exit code propagation via fake codex shim]" -ForegroundColor Yellow

# These tests stub `codex` with a script we control so we can prove the wrapper
# propagates the child's exit code regardless of what the real codex would do.
# A throwaway directory is prepended to PATH; the shim there shadows the real
# codex binary for the duration of the test.

function With-FakeCodex {
    param(
        [string]$ExitCodeToReturn,
        [string]$OutputContent = "fake codex output",
        [bool]$EmitStderrWarning = $false,
        [scriptblock]$Body
    )
    $shimDir = Join-Path $env:TEMP "codex_fake_$(Get-Random)"
    New-Item -ItemType Directory -Path $shimDir -Force | Out-Null
    try {
        # Build a .cmd that mimics codex enough for the wrapper:
        #   - parses -o <file> and writes $OutputContent to it
        #   - optionally writes a deprecation-style warning to stderr
        #   - exits with $ExitCodeToReturn
        $cmdLines = @(
            '@echo off',
            'setlocal enabledelayedexpansion',
            'set OUTFILE=',
            ':loop',
            'if "%~1"=="" goto done',
            'if "%~1"=="-o" (set OUTFILE=%~2 & shift & shift & goto loop)',
            'shift',
            'goto loop',
            ':done',
            ('if not "%OUTFILE%"=="" echo ' + $OutputContent + ' > "%OUTFILE%"')
        )
        if ($EmitStderrWarning) {
            $cmdLines += 'echo deprecated: fake warning 1>&2'
        }
        $cmdLines += ('exit /b ' + $ExitCodeToReturn)
        Set-Content -Path (Join-Path $shimDir "codex.cmd") -Value $cmdLines -Encoding ASCII

        $origPath = $env:Path
        try {
            $env:Path = "$shimDir;$origPath"
            & $Body
        } finally {
            $env:Path = $origPath
        }
    } finally {
        Remove-Item $shimDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test-Case "Wrapper exit code matches fake codex exit 0" {
    With-FakeCodex -ExitCodeToReturn 0 -Body {
        $r = Invoke-Wrapper @("-Prompt", "anything")
        if ($r.ExitCode -ne 0) {
            throw "Expected exit 0, got $($r.ExitCode). Output: $($r.Output)"
        }
    }
}

Test-Case "Wrapper exit code matches fake codex exit 42" {
    With-FakeCodex -ExitCodeToReturn 42 -Body {
        $r = Invoke-Wrapper @("-Prompt", "anything")
        if ($r.ExitCode -ne 42) {
            throw "Expected exit 42, got $($r.ExitCode). Output: $($r.Output)"
        }
    }
}

Test-Case "Wrapper still exits 0 when codex prints stderr noise + exits 0" {
    With-FakeCodex -ExitCodeToReturn 0 -EmitStderrWarning $true -Body {
        $r = Invoke-Wrapper @("-Prompt", "anything")
        if ($r.ExitCode -ne 0) {
            throw "Expected exit 0 (stderr noise should not corrupt exit), got $($r.ExitCode). Output: $($r.Output)"
        }
    }
}

# --------------------------------------------------
Write-Host ""
Write-Host "[Group 4d: ASCII workdir enforcement]" -ForegroundColor Yellow

Test-Case "-WorkDir with non-ASCII path is rejected" {
    $r = Invoke-Wrapper @("-Prompt", "Say OK", "-WorkDir", "C:\tmp\日本語")
    if ($r.ExitCode -ne 1) {
        throw "Expected exit 1 for non-ASCII -WorkDir, got $($r.ExitCode). Output: $($r.Output)"
    }
    if ($r.Output -notmatch "ASCII") {
        throw "Expected ASCII error message, got: $($r.Output)"
    }
}

Test-Case "-WorkDir with non-existent ASCII path is rejected" {
    $r = Invoke-Wrapper @("-Prompt", "Say OK", "-WorkDir", "C:\tmp\definitely-does-not-exist-xyz")
    if ($r.ExitCode -ne 1) {
        throw "Expected exit 1 for non-existent -WorkDir, got $($r.ExitCode). Output: $($r.Output)"
    }
}

# --------------------------------------------------
Write-Host ""
Write-Host "[Group 5: Context File Support]" -ForegroundColor Yellow

Test-Case "Accepts -ContextFile parameter" {
    $ctxFile = Join-Path $env:TEMP "test_ctx_ps_$(Get-Random).txt"
    "The capital of France is Paris." | Out-File -FilePath $ctxFile -Encoding UTF8
    $r = Invoke-Wrapper @("-Prompt", "What city is mentioned in the context? Answer in one word.", "-ContextFile", $ctxFile)
    Remove-Item $ctxFile -Force -ErrorAction SilentlyContinue
    Assert-Equal 0 $r.ExitCode "Should exit with code 0, got output: $($r.Output)"
    if ($r.Output.Length -eq 0) {
        throw "Output should not be empty"
    }
}

Test-Case "Errors on missing context file" {
    $r = Invoke-Wrapper @("-Prompt", "test", "-ContextFile", "C:\nonexistent\file.txt")
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
