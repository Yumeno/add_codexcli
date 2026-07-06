$ErrorActionPreference = "Stop"
$Installer = Join-Path (Split-Path $PSScriptRoot -Parent) "install-for-antigravity.ps1"
$TempRoot = Join-Path ([IO.Path]::GetTempPath()) ("add_codexcli_antigravity_日本語_" + [guid]::NewGuid().ToString("N"))
$DestinationRoot = Join-Path $TempRoot "install root"
$ScriptsRoot = Join-Path $TempRoot "shared scripts"
$SkillNames = @("ask-codex", "ask-codex-with-context", "codex-implement", "list-codex-models", "set-codex-model")
$ScriptNames = @("codex-wrapper.ps1", "codex-wrapper.sh", "codex-verify.ps1", "codex-verify.sh", "list-codex-models.ps1", "list-codex-models.sh")
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
    & powershell -ExecutionPolicy Bypass -NoProfile -File $Installer -DestinationRoot $DestinationRoot -ScriptsRoot $ScriptsRoot | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "installer exited with $LASTEXITCODE" }

    Test-Case "installs exactly five managed skills" {
        foreach ($name in $SkillNames) {
            if (-not (Test-Path -LiteralPath (Join-Path $DestinationRoot "skills\$name\SKILL.md") -PathType Leaf)) { throw "missing skill: $name" }
        }
    }
    Test-Case "installs script allowlist" {
        foreach ($name in $ScriptNames) {
            if (-not (Test-Path -LiteralPath (Join-Path $ScriptsRoot $name) -PathType Leaf)) { throw "missing script: $name" }
        }
        $installed = @(Get-ChildItem -LiteralPath $ScriptsRoot -File | Select-Object -ExpandProperty Name | Sort-Object)
        if (($installed -join "`n") -ne (($ScriptNames | Sort-Object) -join "`n")) { throw "unexpected scripts: $($installed -join ', ')" }
    }
    Test-Case "resolves Antigravity script path placeholders" {
        foreach ($name in $SkillNames) {
            $content = Get-Content -LiteralPath (Join-Path $DestinationRoot "skills\$name\SKILL.md") -Raw -Encoding UTF8
            if ($content -match '\{\{SCRIPTS_ROOT\}\}') { throw "scripts placeholder remains in $name" }
            if ($content -notmatch [regex]::Escape(($ScriptsRoot -replace '\\', '/'))) { throw "installed scripts path missing in $name" }
        }
    }
    Test-Case "preserves unrelated skills and replaces managed skill" {
        if (-not (Test-Path -LiteralPath (Join-Path $DestinationRoot "skills\unrelated\keep.txt"))) { throw "unrelated skill was removed" }
        if (Test-Path -LiteralPath (Join-Path $DestinationRoot "skills\ask-codex\stale.txt")) { throw "stale managed skill content remains" }
    }
    Test-Case "is idempotent" {
        & powershell -ExecutionPolicy Bypass -NoProfile -File $Installer -DestinationRoot $DestinationRoot -ScriptsRoot $ScriptsRoot | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "second install exited with $LASTEXITCODE" }
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
