# codex-verify.ps1 - Snapshot and verify repository safety invariants.
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
    Write-Output "$ErrorSentinel $Message"
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
    return [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Value))
}

function From-Base64 {
    param([string]$Value)
    try { return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Value)) }
    catch { Fail "Invalid Base64 value in snapshot." }
}

function Get-ProtectedFiles {
    $result = @()
    @(".env") + @(Get-ChildItem -LiteralPath $script:RepoPath -Filter ".env.*" -File -ErrorAction SilentlyContinue |
        ForEach-Object { $_.Name }) | ForEach-Object {
        $candidate = Join-Path $script:RepoPath $_
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { $result += Get-Item -LiteralPath $candidate }
    }
    $result += Get-ChildItem -LiteralPath $script:RepoPath -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object {
            $_.FullName -notlike ((Join-Path $script:RepoPath ".git") + "\*") -and
            @(".pem", ".key", ".p12", ".pfx") -contains $_.Extension.ToLowerInvariant()
        }
    $hooks = Join-Path $script:RepoPath ".git\hooks"
    if (Test-Path -LiteralPath $hooks -PathType Container) {
        $result += Get-ChildItem -LiteralPath $hooks -File -ErrorAction SilentlyContinue |
            Where-Object { -not $_.Name.EndsWith(".sample", [StringComparison]::OrdinalIgnoreCase) }
    }
    return @($result | Sort-Object FullName -Unique)
}

function Get-RelativePath {
    param([string]$FullName)
    return $FullName.Substring($script:RepoPath.Length).TrimStart("\", "/").Replace("\", "/")
}

function Test-Allowed {
    param([string]$Path)
    foreach ($patternGroup in $Allow) {
        foreach ($pattern in ($patternGroup -split ",")) {
            if ($pattern -and $Path -like $pattern) { return $true }
        }
    }
    return $false
}

if (($Snapshot -and $Check) -or (-not $Snapshot -and -not $Check)) {
    Fail "Specify exactly one of -Snapshot or -Check."
}
if ([string]::IsNullOrWhiteSpace($Repo)) { $Repo = (Get-Location).Path }
try { $script:RepoPath = (Resolve-Path -LiteralPath $Repo -ErrorAction Stop).Path.TrimEnd("\", "/") }
catch { Fail "Repository directory not found: $Repo" }

& git -C $script:RepoPath rev-parse --is-inside-work-tree *> $null
if ($LASTEXITCODE -ne 0) { Fail "Not a git repository: $script:RepoPath" }

if ($Snapshot) {
    if ($SnapshotFile) { Fail "-SnapshotFile is only valid with -Check." }
    if (-not $Out) {
        $Out = Join-Path $env:TEMP ("codex_verify_snap_{0}.txt" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
    }
    $head = (Invoke-Git @("rev-parse", "HEAD")) -join "`n"
    $branch = (Invoke-Git @("branch", "--show-current")) -join "`n"
    $status = (Invoke-Git @("status", "--porcelain=v1", "--untracked-files=all")) -join "`n"
    $lines = @("format=1", "head=$head", "branch=$(To-Base64 $branch)", "status=$(To-Base64 $status)")
    foreach ($file in Get-ProtectedFiles) {
        $relative = Get-RelativePath $file.FullName
        $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        $lines += "protected=$(To-Base64 $relative):$hash"
    }
    try { [IO.File]::WriteAllLines($Out, $lines, (New-Object Text.UTF8Encoding($false))) }
    catch { Fail "Unable to write snapshot: $Out" }
    try { $fullOut = [IO.Path]::GetFullPath($Out) } catch { $fullOut = $Out }
    Write-Output "SNAPSHOT: $fullOut"
    exit 0
}

if ($Out) { Fail "-Out is only valid with -Snapshot." }
if (-not $SnapshotFile) { Fail "-Check requires -SnapshotFile." }
if (-not (Test-Path -LiteralPath $SnapshotFile -PathType Leaf)) {
    Fail "Snapshot file is not readable: $SnapshotFile"
}

$oldHead = $null
$oldBranch = $null
$oldHashes = @{}
try {
    foreach ($line in [IO.File]::ReadAllLines($SnapshotFile, [Text.Encoding]::UTF8)) {
        if ($line.StartsWith("head=")) { $oldHead = $line.Substring(5) }
        elseif ($line.StartsWith("branch=")) { $oldBranch = From-Base64 $line.Substring(7) }
        elseif ($line.StartsWith("protected=")) {
            $entry = $line.Substring(10)
            $separator = $entry.IndexOf(":")
            if ($separator -lt 1) { Fail "Invalid protected entry in snapshot." }
            $path = From-Base64 $entry.Substring(0, $separator)
            $oldHashes[$path] = $entry.Substring($separator + 1)
        }
    }
} catch { Fail "Unable to read snapshot file: $SnapshotFile" }
if ($null -eq $oldHead -or $null -eq $oldBranch) { Fail "Invalid snapshot file: $SnapshotFile" }

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
    $currentHashes[$path] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
}
foreach ($path in $oldHashes.Keys) {
    $action = $null
    if (-not $currentHashes.ContainsKey($path)) { $action = "deleted" }
    elseif ($oldHashes[$path] -ne $currentHashes[$path]) { $action = "modified" }
    if ($action) {
        if (Test-Allowed $path) { Write-Output "$AllowedSentinel protected file $action (allowed): $path" }
        else {
            Write-Output "$ViolationSentinel protected file ${action}: $path"
            $violations++
        }
    }
}
foreach ($path in $currentHashes.Keys) {
    if ($oldHashes.ContainsKey($path)) { continue }
    if (Test-Allowed $path) { Write-Output "$AllowedSentinel protected file added (allowed): $path" }
    else {
        Write-Output "$ViolationSentinel protected file added: $path"
        $violations++
    }
}

Write-Output "--- git status --porcelain=v1 --untracked-files=all ---"
Invoke-Git @("status", "--porcelain=v1", "--untracked-files=all") | ForEach-Object { Write-Output $_ }
Write-Output "--- git diff HEAD --stat ---"
Invoke-Git @("diff", "HEAD", "--stat") | ForEach-Object { Write-Output $_ }
if ($violations -gt 0) { exit 2 }
exit 0
