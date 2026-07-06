$ErrorActionPreference = "Stop"
$Wrapper = Join-Path (Split-Path $PSScriptRoot -Parent) "codex-wrapper.ps1"
$Root = Join-Path ([IO.Path]::GetTempPath()) ("codex_media_unit_" + [guid]::NewGuid().ToString("N"))
$Shim = Join-Path $Root "shim"
$Media = Join-Path $Root "media 日本語"
$Argv = Join-Path $Root "argv.txt"
$Stdin = Join-Path $Root "stdin.txt"
$oldPath = $env:Path

try {
    New-Item -ItemType Directory -Force -Path $Shim, $Media | Out-Null
    $recorder = Join-Path $Shim "recorder.ps1"
    $body = @"
`$args | Out-File -LiteralPath '$Argv' -Encoding UTF8
[IO.File]::WriteAllText('$Stdin', [Console]::In.ReadToEnd())
`$out = ""
for (`$i=0; `$i -lt `$args.Count-1; `$i++) { if (`$args[`$i] -eq '-o') { `$out=`$args[`$i+1] } }
if (`$out) { [IO.File]::WriteAllText(`$out, 'media test output') }
"@
    [IO.File]::WriteAllText($recorder, $body, (New-Object Text.UTF8Encoding($true)))
    $cmd = "@echo off`r`npowershell -ExecutionPolicy Bypass -NoProfile -File `"$recorder`" %*`r`n"
    [IO.File]::WriteAllText((Join-Path $Shim "codex.cmd"), $cmd, [Text.Encoding]::ASCII)
    $png = Join-Path $Media "first, image.bin"
    $jpg = Join-Path $Media "second image.dat"
    [IO.File]::WriteAllBytes($png, [byte[]](0x89,0x50,0x4e,0x47,0x0d,0x0a,0x1a,0x0a))
    [IO.File]::WriteAllBytes($jpg, [byte[]](0xff,0xd8,0xff,0xe0))
    $list = Join-Path $Root "attachments.txt"
    [IO.File]::WriteAllLines($list, [string[]]@($png,$jpg), (New-Object Text.UTF8Encoding($false)))
    $env:Path = "$Shim;$oldPath"
    $ErrorActionPreference = "Continue"
    $output = & powershell -ExecutionPolicy Bypass -NoProfile -File $Wrapper `
        -Prompt "inspect" -Context "context marker" -AttachmentList $list 2>&1
    $ErrorActionPreference = "Stop"
    if ($LASTEXITCODE -ne 0) { throw ($output | Out-String) }
    $argsLines = @(Get-Content -LiteralPath $Argv -Encoding UTF8)
    $indexes = @(0..($argsLines.Count-1) | Where-Object { $argsLines[$_] -eq "-i" })
    if ($indexes.Count -ne 2) { throw "expected two -i flags: $($argsLines -join '|')" }
    $first = $argsLines[$indexes[0]+1]; $second = $argsLines[$indexes[1]+1]
    if (-not $first.EndsWith("image-001.png") -or -not $second.EndsWith("image-002.jpg")) {
        throw "attachment order/type mismatch: $first $second"
    }
    if ((Test-Path $first) -or (Test-Path $second)) { throw "staging directory leaked" }
    if ((Get-Content -LiteralPath $Stdin -Raw) -notmatch "context marker") { throw "context missing from stdin" }
    Write-Host "PASS: PowerShell media wrapper"
} finally {
    $env:Path = $oldPath
    Remove-Item -LiteralPath $Root -Recurse -Force -ErrorAction SilentlyContinue
}
