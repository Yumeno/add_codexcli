# Tests for codex-verify.ps1.
$Verify = Join-Path $PSScriptRoot "..\codex-verify.ps1"
$Root = Join-Path $env:TEMP "codex_verify_test_ps_$PID"
$SnapshotPath = "$Root.snapshot.txt"
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
    Remove-Item $SnapshotPath -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $Root | Out-Null
    & git -C $Root init -q
    & git -C $Root config user.email test@example.com
    & git -C $Root config user.name Test
    [IO.File]::WriteAllText((Join-Path $Root "tracked.txt"), "initial`n")
    & git -C $Root add tracked.txt
    & git -C $Root commit -qm initial
}

function New-Snapshot {
    & powershell -ExecutionPolicy Bypass -NoProfile -File $Verify -Snapshot -Repo $Root -Out $SnapshotPath | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Snapshot failed with exit $LASTEXITCODE" }
}

function Invoke-Check {
    param([string[]]$Extra = @())
    $output = & powershell -ExecutionPolicy Bypass -NoProfile -File $Verify -Check `
        -Repo $Root -SnapshotFile $SnapshotPath @Extra 2>&1
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
    Test-Case "git config modification is a violation" {
        New-Repo; New-Snapshot; & git -C $Root config verify.test changed
        $r = Invoke-Check
        if ($r.Code -ne 2 -or $r.Output -notmatch "protected file modified: .git/config") { throw $r.Output }
    }
    Test-Case "non-sample hook addition is a violation" {
        New-Repo; New-Snapshot
        [IO.File]::WriteAllText((Join-Path $Root ".git\hooks\pre-commit"), "echo hook`n")
        $r = Invoke-Check
        if ($r.Code -ne 2 -or $r.Output -notmatch "protected file added: .git/hooks/pre-commit") { throw $r.Output }
    }
    Test-Case "subdirectory repo is normalized" {
        New-Repo; $sub = Join-Path $Root "sub"; New-Item -ItemType Directory $sub | Out-Null
        [IO.File]::WriteAllText((Join-Path $Root ".env"), "A=1`n")
        $output = & powershell -ExecutionPolicy Bypass -NoProfile -File $Verify -Snapshot `
            -Repo $sub -Out $SnapshotPath 2>&1
        if ($LASTEXITCODE -ne 0) { throw ($output | Out-String) }
        [IO.File]::WriteAllText((Join-Path $Root ".env"), "A=2`n")
        $output = & powershell -ExecutionPolicy Bypass -NoProfile -File $Verify -Check `
            -Repo $sub -SnapshotFile $SnapshotPath 2>&1
        $text = $output | Out-String
        if ($LASTEXITCODE -ne 2 -or $text -notmatch "Note: repo normalized to" -or
            $text -notmatch "protected file modified: .env") { throw $text }
    }
    Test-Case "protected .env deletion is a violation" {
        New-Repo; [IO.File]::WriteAllText((Join-Path $Root ".env"), "A=1`n"); New-Snapshot
        Remove-Item (Join-Path $Root ".env"); $r = Invoke-Check
        if ($r.Code -ne 2 -or $r.Output -notmatch "protected file deleted: .env") { throw $r.Output }
    }
    Test-Case "invalid protected hash fails" {
        New-Repo; [IO.File]::WriteAllText((Join-Path $Root ".env"), "A=1`n"); New-Snapshot
        $content = [IO.File]::ReadAllText($SnapshotPath)
        $content = [Text.RegularExpressions.Regex]::Replace($content, ":[0-9a-f]{64}(?=`r?`n|$)", ":bad")
        [IO.File]::WriteAllText($SnapshotPath, $content, (New-Object Text.UTF8Encoding($false)))
        $r = Invoke-Check
        if ($r.Code -ne 1 -or $r.Output -notmatch "\[CODEX_VERIFY_ERROR\]") { throw $r.Output }
    }
    Test-Case "detached HEAD is supported" {
        New-Repo; & git -C $Root checkout -q --detach HEAD; New-Snapshot; $r = Invoke-Check
        if ($r.Code -ne 0 -or $r.Output -match "\[CODEX_VERIFY_VIOLATION\]") { throw $r.Output }
    }
    Test-Case "allow matching is case-sensitive" {
        New-Repo; [IO.File]::WriteAllText((Join-Path $Root ".env"), "A=1`n"); New-Snapshot
        [IO.File]::WriteAllText((Join-Path $Root ".env"), "A=2`n"); $r = Invoke-Check @("-Allow", ".ENV")
        if ($r.Code -ne 2 -or $r.Output -notmatch "protected file modified: .env") { throw $r.Output }
    }
    Test-Case "snapshot inside repository fails" {
        New-Repo
        $output = & powershell -ExecutionPolicy Bypass -NoProfile -File $Verify -Snapshot `
            -Repo $Root -Out (Join-Path $Root "inside.txt") 2>&1
        if ($LASTEXITCODE -ne 1 -or ($output | Out-String) -notmatch
            "\[CODEX_VERIFY_ERROR\] snapshot file must be outside the repository") {
            throw ($output | Out-String)
        }
    }
    Test-Case "symlink target change is a violation" {
        New-Repo
        [IO.File]::WriteAllText((Join-Path $Root "target-one"), "one`n")
        [IO.File]::WriteAllText((Join-Path $Root "target-two"), "two`n")
        try {
            New-Item -ItemType SymbolicLink -Path (Join-Path $Root ".env") `
                -Target "target-one" -ErrorAction Stop | Out-Null
        } catch {
            Write-Host "SKIP: symlinks are not available"
            return
        }
        $item = Get-Item -LiteralPath (Join-Path $Root ".env") -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) {
            Write-Host "SKIP: symlinks are not available"
            return
        }
        New-Snapshot
        Remove-Item (Join-Path $Root ".env")
        New-Item -ItemType SymbolicLink -Path (Join-Path $Root ".env") `
            -Target "target-two" -ErrorAction Stop | Out-Null
        $r = Invoke-Check
        if ($r.Code -ne 2 -or $r.Output -notmatch "protected file modified: .env") { throw $r.Output }
    }
} finally {
    Remove-Item $Root -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $SnapshotPath -Force -ErrorAction SilentlyContinue
}

Write-Host "Passed: $script:Passed / $script:Total"
if ($script:Passed -ne $script:Total) { exit 1 }
exit 0
