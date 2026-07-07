# sync-skill-scripts.ps1 - Sync canonical helper scripts into skill bundles.
# Usage: powershell -ExecutionPolicy Bypass -NoProfile -File tools/sync-skill-scripts.ps1 [-Check]

param(
    [switch]$Check
)

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $PSScriptRoot
$Hosts = @(".claude", ".agents")
$Skills = @(
    "ask-codex",
    "ask-codex-with-context",
    "codex-implement",
    "list-codex-models",
    "set-codex-model"
)

function Write-ToolError {
    param([string]$Message)
    [Console]::Error.WriteLine("[SYNC_SKILL_SCRIPTS_ERROR] $Message")
}

function Get-DisplayPath {
    param([string]$Path)
    $full = [IO.Path]::GetFullPath($Path)
    $root = [IO.Path]::GetFullPath($RootDir)
    if (-not $root.EndsWith([IO.Path]::DirectorySeparatorChar)) {
        $root = $root + [IO.Path]::DirectorySeparatorChar
    }
    if ($full.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
        return $full.Substring($root.Length).Replace("\", "/")
    }
    return $full.Replace("\", "/")
}

function Get-SkillHelpers {
    param([string]$Skill)
    switch ($Skill) {
        "ask-codex" { return @("codex-wrapper.sh", "codex-wrapper.ps1") }
        "ask-codex-with-context" { return @("codex-wrapper.sh", "codex-wrapper.ps1") }
        "set-codex-model" { return @("codex-wrapper.sh", "codex-wrapper.ps1") }
        "codex-implement" {
            return @("codex-wrapper.sh", "codex-wrapper.ps1", "codex-verify.sh", "codex-verify.ps1")
        }
        "list-codex-models" {
            return @("codex-wrapper.sh", "codex-wrapper.ps1", "list-codex-models.sh", "list-codex-models.ps1")
        }
        default { throw "Unknown skill: $Skill" }
    }
}

function Test-BytesEqual {
    param([string]$Left, [string]$Right)
    if (-not [IO.File]::Exists($Left) -or -not [IO.File]::Exists($Right)) {
        return $false
    }
    $leftBytes = [IO.File]::ReadAllBytes($Left)
    $rightBytes = [IO.File]::ReadAllBytes($Right)
    if ($leftBytes.Length -ne $rightBytes.Length) {
        return $false
    }
    for ($i = 0; $i -lt $leftBytes.Length; $i++) {
        if ($leftBytes[$i] -ne $rightBytes[$i]) {
            return $false
        }
    }
    return $true
}

function Sync-Skill {
    param([string]$HostDir, [string]$Skill)
    $skillDir = Join-Path (Join-Path (Join-Path $RootDir $HostDir) "skills") $Skill
    $scriptsDir = Join-Path $skillDir "scripts"
    $helpers = @(Get-SkillHelpers $Skill)

    if (-not [IO.Directory]::Exists($skillDir)) {
        throw "Skill directory not found: $(Get-DisplayPath $skillDir)"
    }
    if (-not [IO.Directory]::Exists($scriptsDir)) {
        New-Item -ItemType Directory -Path $scriptsDir | Out-Null
    }

    Get-ChildItem -LiteralPath $scriptsDir -File | ForEach-Object {
        Remove-Item -LiteralPath $_.FullName -Force
    }

    foreach ($helper in $helpers) {
        $source = Join-Path (Join-Path $RootDir "scripts") $helper
        if (-not [IO.File]::Exists($source)) {
            throw "Source helper not found: scripts/$helper"
        }
        Copy-Item -LiteralPath $source -Destination (Join-Path $scriptsDir $helper) -Force
    }

    Write-Host ("synced {0}: {1} files" -f (Get-DisplayPath $skillDir), $helpers.Count)
}

function Test-Skill {
    param([string]$HostDir, [string]$Skill)
    $skillDir = Join-Path (Join-Path (Join-Path $RootDir $HostDir) "skills") $Skill
    $scriptsDir = Join-Path $skillDir "scripts"
    $helpers = @(Get-SkillHelpers $Skill)
    $ok = $true

    if (-not [IO.Directory]::Exists($scriptsDir)) {
        [Console]::Error.WriteLine("scripts directory missing: $(Get-DisplayPath $skillDir)")
        return $false
    }

    foreach ($helper in $helpers) {
        $source = Join-Path (Join-Path $RootDir "scripts") $helper
        $dest = Join-Path $scriptsDir $helper
        if (-not [IO.File]::Exists($source)) {
            throw "Source helper not found: scripts/$helper"
        }
        if (-not (Test-BytesEqual $source $dest)) {
            [Console]::Error.WriteLine("out of sync: $(Get-DisplayPath $dest)")
            $ok = $false
        }
    }

    Get-ChildItem -LiteralPath $scriptsDir -File | ForEach-Object {
        if ($helpers -notcontains $_.Name) {
            [Console]::Error.WriteLine("unexpected bundled script: $(Get-DisplayPath $_.FullName)")
            $script:CheckOk = $false
        }
    }

    return $ok
}

try {
    $script:CheckOk = $true
    foreach ($hostDir in $Hosts) {
        foreach ($skill in $Skills) {
            if ($Check) {
                if (-not (Test-Skill $hostDir $skill)) {
                    $script:CheckOk = $false
                }
            } else {
                Sync-Skill $hostDir $skill
            }
        }
    }

    if ($Check) {
        if ($script:CheckOk) {
            Write-Host "PASS: skill bundled scripts in sync"
            exit 0
        }
        exit 1
    }
    exit 0
} catch {
    Write-ToolError $_.Exception.Message
    exit 1
}
