# Tests for codex-verify.ps1.
$Verify = Join-Path $PSScriptRoot "..\codex-verify.ps1"
$Root = Join-Path $env:TEMP "codex_verify_test_ps_$PID"
$script:Total = 0
$script:Passed = 0

function Test-Case {
    param([string]$Name, [scriptblock]$Body)
    $script:Total++
    try {
        & $Body
        $script:Passed++
        Write-Host "PASS: $Name"
    } catch {
        Write-Host "FAIL: $Name - $($_.Exception.Message)"
    }
}

function New-Repo {
    Remove-Item $Root -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $Root | Out-Null
    & git -C $Root init -q
    & git -C $Root config user.email test@example.com
    & git -C $Root config user.name Test
    [IO.File]::WriteAllText((Join-Path $Root "tracked.txt"), "initial`n")
    & git -C $Root add tracked.txt
    & git -C $Root commit -qm initial
}

function New-Snapshot {
    & powershell -ExecutionPolicy Bypass -NoProfile -File $Verify -Snapshot -Repo $Root -Out (Join-Path $Root "snapshot.txt") | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Snapshot failed with exit $LASTEXITCODE" }
}

function Invoke-Check {
    param([string[]]$Extra = @())
    $output = & powershell -ExecutionPolicy Bypass -NoProfile -File $Verify -Check `
        -Repo $Root -SnapshotFile (Join-Path $Root "snapshot.txt") @Extra 2>&1
    return @{ Code = $LASTEXITCODE; Output = ($output | Out-String) }
}

try {
    Write-Host "=== codex-verify PowerShell tests ==="
    Test-Case "snapshot then unchanged check" {
        New-Repo; New-Snapshot; $r = Invoke-Check
        if ($r.Code -ne 0 -or $r.Output -match "\[CODEX_VERIFY_VIOLATION\]") { throw $r.Output }
    }
    Test-Case "ordinary tracked edit is allowed" {
        New-Repo; New-Snapshot; Add-Content (Join-Path $Root "tracked.txt") "changed"
        $r = Invoke-Check
        if ($r.Code -ne 0 -or $r.Output -notmatch "tracked.txt") { throw $r.Output }
    }
    Test-Case "HEAD change is a violation" {
        New-Repo; New-Snapshot; Add-Content (Join-Path $Root "tracked.txt") "next"
        & git -C $Root add tracked.txt; & git -C $Root commit -qm next
        $r = Invoke-Check
        if ($r.Code -ne 2 -or $r.Output -notmatch "\[CODEX_VERIFY_VIOLATION\] HEAD changed:") { throw $r.Output }
    }
    Test-Case "branch change is a violation" {
        New-Repo; New-Snapshot; & git -C $Root checkout -qb other
        $r = Invoke-Check
        if ($r.Code -ne 2 -or $r.Output -notmatch "\[CODEX_VERIFY_VIOLATION\] branch changed:") { throw $r.Output }
    }
    Test-Case "protected .env modification is a violation" {
        New-Repo; [IO.File]::WriteAllText((Join-Path $Root ".env"), "A=1`n"); New-Snapshot
        [IO.File]::WriteAllText((Join-Path $Root ".env"), "A=2`n"); $r = Invoke-Check
        if ($r.Code -ne 2 -or $r.Output -notmatch "protected file modified: .env") { throw $r.Output }
    }
    Test-Case "allowed .env modification is informational" {
        New-Repo; [IO.File]::WriteAllText((Join-Path $Root ".env"), "A=1`n"); New-Snapshot
        [IO.File]::WriteAllText((Join-Path $Root ".env"), "A=2`n"); $r = Invoke-Check @("-Allow", ".env")
        if ($r.Code -ne 0 -or $r.Output -notmatch "\[CODEX_VERIFY_ALLOWED\]") { throw $r.Output }
    }
    Test-Case "new protected .env is a violation" {
        New-Repo; New-Snapshot; [IO.File]::WriteAllText((Join-Path $Root ".env"), "A=1`n")
        $r = Invoke-Check
        if ($r.Code -ne 2 -or $r.Output -notmatch "protected file added: .env") { throw $r.Output }
    }
    Test-Case "ordinary untracked file is allowed" {
        New-Repo; New-Snapshot; [IO.File]::WriteAllText((Join-Path $Root "untracked.txt"), "new`n")
        $r = Invoke-Check
        if ($r.Code -ne 0 -or $r.Output -notmatch "untracked.txt") { throw $r.Output }
    }
    Test-Case "snapshot outside git repository fails" {
        Remove-Item $Root -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Path $Root | Out-Null
        $output = & powershell -ExecutionPolicy Bypass -NoProfile -File $Verify -Snapshot -Repo $Root 2>&1
        if ($LASTEXITCODE -ne 1 -or ($output | Out-String) -notmatch "\[CODEX_VERIFY_ERROR\]") { throw ($output | Out-String) }
    }
    Test-Case "missing snapshot fails" {
        New-Repo
        $output = & powershell -ExecutionPolicy Bypass -NoProfile -File $Verify -Check -Repo $Root `
            -SnapshotFile (Join-Path $Root "missing.txt") 2>&1
        if ($LASTEXITCODE -ne 1 -or ($output | Out-String) -notmatch "\[CODEX_VERIFY_ERROR\]") { throw ($output | Out-String) }
    }
} finally {
    Remove-Item $Root -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "Passed: $script:Passed / $script:Total"
if ($script:Passed -ne $script:Total) { exit 1 }
exit 0
