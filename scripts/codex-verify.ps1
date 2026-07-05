# codex-verify.ps1 - Snapshot and verify repository safety invariants.
# Symlinks are recorded by link target; changes behind the target are not tracked.
# -Allow accepts comma-bound arrays; patterns containing commas cannot be specified.
param(
    [switch]$Snapshot,
    [switch]$Check,
    [string]$Repo = "",
    [string]$Out = "",
    [string]$SnapshotFile = "",
    [string[]]$Allow = @()
)

[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$OutputEncoding = [Console]::OutputEncoding
$ErrorSentinel = "[CODEX_VERIFY_ERROR]"
$ViolationSentinel = "[CODEX_VERIFY_VIOLATION]"
$AllowedSentinel = "[CODEX_VERIFY_ALLOWED]"

function Fail {
    param([string]$Message)
    [Console]::Error.WriteLine("$ErrorSentinel $Message")
    exit 1
}

function Invoke-Git {
    param([string[]]$Arguments)
    $result = & git -C $script:RepoPath @Arguments 2>$null
    if ($LASTEXITCODE -ne 0) { Fail "Git command failed: git $($Arguments -join ' ')" }
    return @($result)
}

function To-Base64 {
    param([string]$Value)
    [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Value))
}

function From-Base64 {
    param([string]$Value)
    try { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Value)) }
    catch { Fail "Invalid Base64 value in snapshot." }
}

function Test-ReparsePoint {
    param([string]$Path)
    try {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        return (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)
    } catch { Fail "Unable to inspect path: $Path" }
}

function Get-SnapshotFullPath {
    param([string]$Path)
    try { $full = [IO.Path]::GetFullPath($Path) } catch { Fail "Invalid snapshot path: $Path" }
    $parent = [IO.Path]::GetDirectoryName($full)
    while (-not [string]::IsNullOrEmpty($parent)) {
        if ([IO.Directory]::Exists($parent) -and (Test-ReparsePoint $parent)) {
            Fail "Snapshot path parent must not be a reparse point."
        }
        $next = [IO.Path]::GetDirectoryName($parent)
        if ($next -eq $parent) { break }
        $parent = $next
    }
    $prefix = $script:RepoPath + [IO.Path]::DirectorySeparatorChar
    if ($full.Equals($script:RepoPath, [StringComparison]::OrdinalIgnoreCase) -or
        $full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        Fail "snapshot file must be outside the repository"
    }
    if ([IO.File]::Exists($full) -and (Test-ReparsePoint $full)) {
        Fail "Snapshot file must not be a reparse point."
    }
    return $full
}

function Get-LinkValue {
    param($Item)
    if (($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) { return $null }
    $target = $Item.Target
    if ($target -is [array]) { $target = $target -join "`n" }
    if ($null -eq $target) { Fail "Unable to read symlink target: $($Item.FullName)" }
    return "symlink:$target"
}

function Get-ProtectedFiles {
    try {
        $result = New-Object System.Collections.ArrayList
        Get-ChildItem -LiteralPath $script:RepoPath -Force -ErrorAction Stop |
            Where-Object { $_.Name -eq ".env" -or $_.Name -like ".env.*" } |
            ForEach-Object { [void]$result.Add($_) }
        Get-ChildItem -LiteralPath $script:RepoPath -Recurse -Force -ErrorAction Stop |
            Where-Object {
                -not $_.PSIsContainer -and
                -not $_.FullName.StartsWith($script:GitDirPrefix, [StringComparison]::OrdinalIgnoreCase) -and
                @(".pem", ".key", ".p12", ".pfx") -contains $_.Extension.ToLowerInvariant()
            } | ForEach-Object { [void]$result.Add($_) }
        if ([IO.File]::Exists($script:ConfigPath)) {
            [void]$result.Add((Get-Item -LiteralPath $script:ConfigPath -Force -ErrorAction Stop))
        }
        if ([IO.Directory]::Exists($script:HooksPath)) {
            Get-ChildItem -LiteralPath $script:HooksPath -Force -ErrorAction Stop |
                Where-Object { -not $_.PSIsContainer -and
                    -not $_.Name.EndsWith(".sample", [StringComparison]::Ordinal) } |
                ForEach-Object { [void]$result.Add($_) }
        }
        return @($result | Sort-Object FullName -Unique)
    } catch { Fail "Unable to enumerate protected files: $($_.Exception.Message)" }
}

function Get-RelativePath {
    param([string]$FullName)
    if ($FullName.Equals($script:ConfigPath, [StringComparison]::OrdinalIgnoreCase)) {
        return ".git/config"
    }
    $hookPrefix = $script:HooksPath.TrimEnd("\", "/") + [IO.Path]::DirectorySeparatorChar
    if ($FullName.StartsWith($hookPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        return ".git/hooks/" + $FullName.Substring($hookPrefix.Length).Replace("\", "/")
    }
    return $FullName.Substring($script:RepoPath.Length).TrimStart("\", "/").Replace("\", "/")
}

function Get-ProtectedValue {
    param($Item)
    $link = Get-LinkValue $Item
    if ($null -ne $link) { return $link }
    try { return (Get-FileHash -LiteralPath $Item.FullName -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant() }
    catch { Fail "Unable to hash protected file: $($Item.FullName)" }
}

function Test-Allowed {
    param([string]$Path)
    foreach ($patternGroup in $Allow) {
        foreach ($pattern in ($patternGroup -split ",")) {
            if ($pattern) {
                $wildcard = New-Object System.Management.Automation.WildcardPattern(
                    $pattern, [System.Management.Automation.WildcardOptions]::None)
                if ($wildcard.IsMatch($Path)) { return $true }
            }
        }
    }
    return $false
}

if (($Snapshot -and $Check) -or (-not $Snapshot -and -not $Check)) {
    Fail "Specify exactly one of -Snapshot or -Check."
}
if ([string]::IsNullOrWhiteSpace($Repo)) { $Repo = (Get-Location).Path }
try { $requested = (Resolve-Path -LiteralPath $Repo -ErrorAction Stop).Path.TrimEnd("\", "/") }
catch { Fail "Repository directory not found: $Repo" }
$script:RepoPath = $requested
$root = (Invoke-Git @("rev-parse", "--show-toplevel")) -join "`n"
try { $script:RepoPath = (Resolve-Path -LiteralPath $root -ErrorAction Stop).Path.TrimEnd("\", "/") }
catch { Fail "Unable to resolve repository root." }
if (-not $requested.Equals($script:RepoPath, [StringComparison]::OrdinalIgnoreCase)) {
    [Console]::Error.WriteLine("Note: repo normalized to $script:RepoPath")
}
$script:ConfigPath = ((Invoke-Git @("rev-parse", "--path-format=absolute", "--git-path", "config")) -join "`n")
$script:HooksPath = ((Invoke-Git @("rev-parse", "--path-format=absolute", "--git-path", "hooks")) -join "`n").TrimEnd("\", "/")
$gitDir = ((Invoke-Git @("rev-parse", "--path-format=absolute", "--git-dir")) -join "`n").TrimEnd("\", "/")
$script:GitDirPrefix = $gitDir + [IO.Path]::DirectorySeparatorChar

if ($Snapshot) {
    if ($SnapshotFile) { Fail "-SnapshotFile is only valid with -Check." }
    if (-not $Out) {
        $Out = Join-Path $env:TEMP ("codex_verify_snap_{0}_{1:x8}.txt" -f
            (Get-Date -Format "yyyyMMdd-HHmmss"), (Get-Random))
    }
    $fullOut = Get-SnapshotFullPath $Out
    $head = (Invoke-Git @("rev-parse", "HEAD")) -join "`n"
    $branch = (Invoke-Git @("branch", "--show-current")) -join "`n"
    $status = (Invoke-Git @("status", "--porcelain=v1", "--untracked-files=all")) -join "`n"
    $stream = $null
    $writer = $null
    try {
        $stream = New-Object IO.FileStream($fullOut, [IO.FileMode]::CreateNew,
            [IO.FileAccess]::Write, [IO.FileShare]::None)
        $writer = New-Object IO.StreamWriter($stream, (New-Object Text.UTF8Encoding($false)))
        $writer.WriteLine("format=1")
        $writer.WriteLine("head=$head")
        $writer.WriteLine("branch=$(To-Base64 $branch)")
        $writer.WriteLine("status=$(To-Base64 $status)")
        foreach ($file in Get-ProtectedFiles) {
            $relative = Get-RelativePath $file.FullName
            $writer.WriteLine("protected=$(To-Base64 $relative):$(Get-ProtectedValue $file)")
        }
    } catch { Fail "Unable to write snapshot: $fullOut" }
    finally {
        if ($null -ne $writer) { $writer.Dispose() }
        elseif ($null -ne $stream) { $stream.Dispose() }
    }
    Write-Output "SNAPSHOT: $fullOut"
    exit 0
}

if ($Out) { Fail "-Out is only valid with -Snapshot." }
if (-not $SnapshotFile) { Fail "-Check requires -SnapshotFile." }
$fullSnapshot = Get-SnapshotFullPath $SnapshotFile
if (-not [IO.File]::Exists($fullSnapshot)) { Fail "Snapshot file is not readable: $fullSnapshot" }

$oldHead = $null
$oldBranch = $null
$oldHashes = @{}
$formatCount = 0
$headCount = 0
$branchCount = 0
try {
    foreach ($line in [IO.File]::ReadAllLines($fullSnapshot, [Text.Encoding]::UTF8)) {
        if ($line.StartsWith("format=")) {
            $formatCount++
            if ($line -ne "format=1") { Fail "Invalid snapshot format." }
        } elseif ($line.StartsWith("head=")) {
            $headCount++; $oldHead = $line.Substring(5)
        } elseif ($line.StartsWith("branch=")) {
            $branchCount++; $oldBranch = From-Base64 $line.Substring(7)
        } elseif ($line.StartsWith("protected=")) {
            $entry = $line.Substring(10)
            $separator = $entry.IndexOf(":")
            if ($separator -lt 0) { Fail "Invalid protected entry in snapshot." }
            $path = From-Base64 $entry.Substring(0, $separator)
            if ([string]::IsNullOrEmpty($path)) { Fail "Invalid snapshot protected path." }
            $value = $entry.Substring($separator + 1)
            if ($value -notmatch "^[0-9A-Fa-f]{64}$" -and -not $value.StartsWith("symlink:")) {
                Fail "Invalid protected hash in snapshot."
            }
            if ($oldHashes.ContainsKey($path)) { Fail "Duplicate protected path in snapshot." }
            $oldHashes[$path] = $value
        }
    }
} catch { Fail "Unable to read snapshot file: $fullSnapshot" }
if ($formatCount -ne 1 -or $headCount -ne 1 -or $branchCount -ne 1 -or
    [string]::IsNullOrEmpty($oldHead) -or $null -eq $oldBranch) {
    Fail "Invalid snapshot file: $fullSnapshot"
}

$currentHead = (Invoke-Git @("rev-parse", "HEAD")) -join "`n"
$currentBranch = (Invoke-Git @("branch", "--show-current")) -join "`n"
$violations = 0
if ($oldHead -ne $currentHead) {
    Write-Output "$ViolationSentinel HEAD changed: $oldHead -> $currentHead"
    $violations++
}
if ($oldBranch -ne $currentBranch) {
    Write-Output "$ViolationSentinel branch changed: $oldBranch -> $currentBranch"
    $violations++
}

$currentHashes = @{}
foreach ($file in Get-ProtectedFiles) {
    $path = Get-RelativePath $file.FullName
    $currentHashes[$path] = Get-ProtectedValue $file
}
foreach ($path in $oldHashes.Keys) {
    $action = $null
    if (-not $currentHashes.ContainsKey($path)) { $action = "deleted" }
    elseif ($oldHashes[$path] -ne $currentHashes[$path]) { $action = "modified" }
    if ($action) {
        if (Test-Allowed $path) { Write-Output "$AllowedSentinel protected file $action (allowed): $path" }
        else { Write-Output "$ViolationSentinel protected file ${action}: $path"; $violations++ }
    }
}
foreach ($path in $currentHashes.Keys) {
    if ($oldHashes.ContainsKey($path)) { continue }
    if (Test-Allowed $path) { Write-Output "$AllowedSentinel protected file added (allowed): $path" }
    else { Write-Output "$ViolationSentinel protected file added: $path"; $violations++ }
}

Write-Output "--- git status --porcelain=v1 --untracked-files=all ---"
Invoke-Git @("status", "--porcelain=v1", "--untracked-files=all") | ForEach-Object { Write-Output $_ }
Write-Output "--- git diff HEAD --stat ---"
Invoke-Git @("diff", "HEAD", "--stat") | ForEach-Object { Write-Output $_ }
if ($violations -gt 0) { exit 2 }
