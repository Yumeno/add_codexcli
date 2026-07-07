[CmdletBinding()]
param(
    [string]$DestinationRoot = (Join-Path $env:USERPROFILE ".claude")
)

$ErrorActionPreference = "Stop"
$RepositoryRoot = Split-Path -Parent $PSScriptRoot
$SourceSkillsRoot = Join-Path $RepositoryRoot ".claude\skills"
$DestinationSkillsRoot = Join-Path $DestinationRoot "skills"
$SkillNames = @("ask-codex", "ask-codex-with-context", "codex-implement", "list-codex-models", "set-codex-model")

function Assert-Sources {
    foreach ($name in $SkillNames) {
        $sourceDirectory = Join-Path $SourceSkillsRoot $name
        $sourceSkill = Join-Path $sourceDirectory "SKILL.md"
        if (-not (Test-Path -LiteralPath $sourceDirectory -PathType Container)) { throw "Required skill source not found: $sourceDirectory" }
        if (-not (Test-Path -LiteralPath $sourceSkill -PathType Leaf)) { throw "Required SKILL.md not found: $sourceSkill" }
    }
}

Assert-Sources
[IO.Directory]::CreateDirectory($DestinationSkillsRoot) | Out-Null
$stage = Join-Path $DestinationRoot (".add-codexcli-stage-" + [guid]::NewGuid().ToString("N"))
try {
    $stageSkills = Join-Path $stage "skills"
    [IO.Directory]::CreateDirectory($stageSkills) | Out-Null
    foreach ($name in $SkillNames) {
        Copy-Item -LiteralPath (Join-Path $SourceSkillsRoot $name) -Destination (Join-Path $stageSkills $name) -Recurse
    }
    foreach ($name in $SkillNames) {
        $destination = Join-Path $DestinationSkillsRoot $name
        $newDestination = "$destination.new"
        $oldDestination = "$destination.old"
        Remove-Item -LiteralPath $newDestination -Recurse -Force -ErrorAction SilentlyContinue
        Move-Item -LiteralPath (Join-Path $stageSkills $name) -Destination $newDestination
        if (Test-Path -LiteralPath $destination) {
            Remove-Item -LiteralPath $oldDestination -Recurse -Force -ErrorAction SilentlyContinue
            Move-Item -LiteralPath $destination -Destination $oldDestination
        }
        try {
            Move-Item -LiteralPath $newDestination -Destination $destination
        } catch {
            if (Test-Path -LiteralPath $oldDestination) {
                Move-Item -LiteralPath $oldDestination -Destination $destination
            }
            throw "Failed to promote new skill: $name"
        }
        Remove-Item -LiteralPath $oldDestination -Recurse -Force -ErrorAction SilentlyContinue
    }
} finally {
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
}

Write-Output "Claude Code用Skillをインストールしました。"
Write-Output "skills=$DestinationSkillsRoot"
