$ErrorActionPreference = "Stop"
$Installer = Join-Path (Split-Path $PSScriptRoot -Parent) "install-for-antigravity.ps1"
$TempRoot = Join-Path ([IO.Path]::GetTempPath()) ("add_codexcli_antigravity_日本語_" + [guid]::NewGuid().ToString("N"))
$DestinationRoot = Join-Path $TempRoot "install root"
$SkillNames = @("ask-codex", "ask-codex-with-context", "codex-implement", "list-codex-models", "set-codex-model")
$Passed = 0
$Failed = 0

function Test-Case {
    param([string]$Name, [scriptblock]$Body)
    try { & $Body; $script:Passed++; Write-Host "PASS $Name" }
    catch { $script:Failed++; Write-Host "FAIL $Name -- $_" }
}

try {
    New-Item -ItemType Directory -Force -Path (Join-Path $DestinationRoot "skills\unrelated") | Out-Null
    [IO.File]::WriteAllText((Join-Path $DestinationRoot "skills\unrelated\keep.txt"), "keep")
    New-Item -ItemType Directory -Force -Path (Join-Path $DestinationRoot "skills\ask-codex") | Out-Null
    [IO.File]::WriteAllText((Join-Path $DestinationRoot "skills\ask-codex\stale.txt"), "stale")
    & powershell -ExecutionPolicy Bypass -NoProfile -File $Installer -DestinationRoot $DestinationRoot | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "installer exited with $LASTEXITCODE" }

    Test-Case "installs exactly five managed skills" {
        foreach ($name in $SkillNames) {
            if (-not (Test-Path -LiteralPath (Join-Path $DestinationRoot "skills\$name\SKILL.md") -PathType Leaf)) { throw "missing skill: $name" }
        }
    }
    Test-Case "installs bundled helper directories" {
        foreach ($name in $SkillNames) {
            if (-not (Test-Path -LiteralPath (Join-Path $DestinationRoot "skills\$name\scripts") -PathType Container)) { throw "missing scripts directory: $name" }
        }
        foreach ($path in @(
            "skills\ask-codex\scripts\codex-wrapper.sh",
            "skills\ask-codex\scripts\codex-wrapper.ps1",
            "skills\codex-implement\scripts\codex-verify.sh",
            "skills\codex-implement\scripts\codex-verify.ps1",
            "skills\list-codex-models\scripts\list-codex-models.sh",
            "skills\list-codex-models\scripts\list-codex-models.ps1"
        )) {
            if (-not (Test-Path -LiteralPath (Join-Path $DestinationRoot $path) -PathType Leaf)) { throw "missing bundled helper: $path" }
        }
    }
    Test-Case "does not leave legacy placeholders" {
        foreach ($name in $SkillNames) {
            $content = Get-Content -LiteralPath (Join-Path $DestinationRoot "skills\$name\SKILL.md") -Raw -Encoding UTF8
            if ($content -match '\{\{SCRIPTS_ROOT\}\}') { throw "scripts placeholder remains in $name" }
        }
    }
    Test-Case "preserves unrelated skills and replaces managed skill" {
        if (-not (Test-Path -LiteralPath (Join-Path $DestinationRoot "skills\unrelated\keep.txt"))) { throw "unrelated skill was removed" }
        if (Test-Path -LiteralPath (Join-Path $DestinationRoot "skills\ask-codex\stale.txt")) { throw "stale managed skill content remains" }
    }
    Test-Case "is idempotent" {
        & powershell -ExecutionPolicy Bypass -NoProfile -File $Installer -DestinationRoot $DestinationRoot | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "second install exited with $LASTEXITCODE" }
    }
    Test-Case "absorbs stale new artifacts" {
        $staleSkill = Join-Path $DestinationRoot "skills\ask-codex.new"
        New-Item -ItemType Directory -Force -Path $staleSkill | Out-Null
        [IO.File]::WriteAllText((Join-Path $staleSkill "leftover.txt"), "leftover")
        & powershell -ExecutionPolicy Bypass -NoProfile -File $Installer -DestinationRoot $DestinationRoot | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "install with stale .new exited with $LASTEXITCODE" }
    }
    Test-Case "read-only skills directory preserves prior content on failure" {
        # Regression coverage for issue #30 (Windows-side rollback path
        # verification). Denies Write on the skills\ directory to force the
        # installer's Move-Item step to fail, then checks that the prior
        # ask-codex content survives (either via the try/catch rollback or
        # because the rename never started).
        $skillsDir = Join-Path $DestinationRoot "skills"
        $askCodexDir = Join-Path $skillsDir "ask-codex"
        $sentinelFile = Join-Path $askCodexDir "previous.txt"
        [IO.File]::WriteAllText($sentinelFile, "previous")

        $originalAcl = Get-Acl -LiteralPath $skillsDir
        $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $denyRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $currentUser,
            [System.Security.AccessControl.FileSystemRights]::Write,
            [System.Security.AccessControl.InheritanceFlags]::None,
            [System.Security.AccessControl.PropagationFlags]::None,
            [System.Security.AccessControl.AccessControlType]::Deny
        )
        $denyAcl = Get-Acl -LiteralPath $skillsDir
        $denyAcl.AddAccessRule($denyRule)

        # Some hosts (e.g. Administrator with SeRestorePrivilege) bypass ACL
        # deny; probe first and SKIP if enforcement doesn't stick. Same
        # SKIP pattern the bash test uses.
        Set-Acl -LiteralPath $skillsDir -AclObject $denyAcl -ErrorAction SilentlyContinue
        $enforcementProbe = Join-Path $skillsDir ".permission-probe.txt"
        $enforcementActive = $true
        try {
            [IO.File]::WriteAllText($enforcementProbe, "probe")
            $enforcementActive = $false
            Remove-Item -LiteralPath $enforcementProbe -Force -ErrorAction SilentlyContinue
        } catch {
            # Write blocked as expected; enforcement is active.
        }

        try {
            if (-not $enforcementActive) {
                Write-Host "SKIP read-only destination enforcement is unavailable on this host"
                return
            }
            $installerFailed = $false
            try {
                & powershell -ExecutionPolicy Bypass -NoProfile -File $Installer -DestinationRoot $DestinationRoot 2>&1 | Out-Null
                if ($LASTEXITCODE -ne 0) { $installerFailed = $true }
            } catch {
                $installerFailed = $true
            }
            if (-not $installerFailed) { throw "installer succeeded under Write-Deny ACL" }
        } finally {
            # Restore ACL before any assertion that reads the tree, so failures
            # here don't leak into $TempRoot cleanup.
            Set-Acl -LiteralPath $skillsDir -AclObject $originalAcl
        }
        if (-not (Test-Path -LiteralPath $sentinelFile)) { throw "previous skill content lost during failed promotion" }
    }
    Test-Case "cleans new and old promotion artifacts" {
        $skillArtifacts = @(Get-ChildItem -LiteralPath (Join-Path $DestinationRoot "skills") -Force | Where-Object { $_.Name -like "*.new" -or $_.Name -like "*.old" })
        if ($skillArtifacts.Count -ne 0) { throw "promotion artifacts remain" }
    }
    Test-Case "cleans staging directories" {
        if (Get-ChildItem -LiteralPath $DestinationRoot -Directory -Filter ".add-codexcli-stage-*") { throw "staging directory leaked" }
    }
    Test-Case "PowerShell sources use UTF-8 BOM" {
        foreach ($path in @($Installer, $PSCommandPath)) {
            $bytes = [IO.File]::ReadAllBytes($path)
            if ($bytes.Length -lt 3 -or $bytes[0] -ne 0xEF -or $bytes[1] -ne 0xBB -or $bytes[2] -ne 0xBF) { throw "UTF-8 BOM missing: $path" }
        }
    }
} finally {
    Remove-Item -LiteralPath $TempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "Passed: $Passed; Failed: $Failed"
if ($Failed -gt 0) { exit 1 }
