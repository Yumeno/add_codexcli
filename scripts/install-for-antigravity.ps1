[CmdletBinding()]
param(
    [string]$DestinationRoot = (Join-Path $env:USERPROFILE ".gemini\antigravity-cli"),
    [string]$ScriptsRoot = (Join-Path $env:USERPROFILE ".gemini\scripts")
)

$ErrorActionPreference = "Stop"
$RepositoryRoot = Split-Path -Parent $PSScriptRoot
$SourceSkillsRoot = Join-Path $RepositoryRoot ".agents\skills"
$DestinationSkillsRoot = Join-Path $DestinationRoot "skills"
$SkillNames = @("ask-codex", "ask-codex-with-context", "codex-implement", "list-codex-models", "set-codex-model")
$ScriptNames = @("codex-wrapper.ps1", "codex-wrapper.sh", "codex-verify.ps1", "codex-verify.sh", "list-codex-models.ps1", "list-codex-models.sh")

function Assert-Sources {
    foreach ($name in $SkillNames) {
        $source = Join-Path (Join-Path $SourceSkillsRoot $name) "SKILL.md"
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Required skill source not found: $source" }
    }
    foreach ($name in $ScriptNames) {
        $source = Join-Path $PSScriptRoot $name
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Required script source not found: $source" }
    }
}

function Convert-SkillForAntigravity {
    param([string]$Source, [string]$Destination, [string]$InstalledScriptsRoot)
    $content = [IO.File]::ReadAllText($Source, [Text.Encoding]::UTF8)
    $windowsRoot = $InstalledScriptsRoot -replace '/', '\'
    $posixRoot = $InstalledScriptsRoot -replace '\\', '/'
    $content = $content.Replace('{{SCRIPTS_ROOT}}', $posixRoot)
    [IO.File]::WriteAllText($Destination, $content, (New-Object Text.UTF8Encoding($false)))
}

Assert-Sources
[IO.Directory]::CreateDirectory($DestinationRoot) | Out-Null
[IO.Directory]::CreateDirectory($DestinationSkillsRoot) | Out-Null
[IO.Directory]::CreateDirectory($ScriptsRoot) | Out-Null
$stage = Join-Path $DestinationRoot (".add-codexcli-stage-" + [guid]::NewGuid().ToString("N"))
try {
    $stageSkills = Join-Path $stage "skills"
    $stageScripts = Join-Path $stage "scripts"
    [IO.Directory]::CreateDirectory($stageSkills) | Out-Null
    [IO.Directory]::CreateDirectory($stageScripts) | Out-Null
    foreach ($name in $SkillNames) {
        $destinationDirectory = Join-Path $stageSkills $name
        [IO.Directory]::CreateDirectory($destinationDirectory) | Out-Null
        Convert-SkillForAntigravity `
            -Source (Join-Path (Join-Path $SourceSkillsRoot $name) "SKILL.md") `
            -Destination (Join-Path $destinationDirectory "SKILL.md") `
            -InstalledScriptsRoot $ScriptsRoot
    }
    foreach ($name in $ScriptNames) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination (Join-Path $stageScripts $name)
    }
    foreach ($name in $ScriptNames) {
        Copy-Item -LiteralPath (Join-Path $stageScripts $name) -Destination (Join-Path $ScriptsRoot $name) -Force
    }
    foreach ($name in $SkillNames) {
        $destination = Join-Path $DestinationSkillsRoot $name
        if (Test-Path -LiteralPath $destination) { Remove-Item -LiteralPath $destination -Recurse -Force }
        Move-Item -LiteralPath (Join-Path $stageSkills $name) -Destination $destination
    }
} finally {
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
}

Write-Output "Antigravity CLI用Skillをインストールしました。"
Write-Output "skills=$DestinationSkillsRoot"
Write-Output "scripts=$ScriptsRoot"
