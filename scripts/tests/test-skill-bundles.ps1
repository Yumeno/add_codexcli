# test-skill-bundles.ps1 - Verify bundled skill helper scripts are in sync.
# Usage: powershell -ExecutionPolicy Bypass -NoProfile -File scripts/tests/test-skill-bundles.ps1

$RootDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$SyncTool = Join-Path (Join-Path $RootDir "tools") "sync-skill-scripts.ps1"

function Invoke-SyncCheck {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell"
    $psi.Arguments = "-ExecutionPolicy Bypass -NoProfile -File `"$SyncTool`" -Check"
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    [void]$process.Start()
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    return @{
        ExitCode = $process.ExitCode
        Output = (($stdout + $stderr).TrimEnd())
    }
}

$result = Invoke-SyncCheck
$code = $result.ExitCode
$text = $result.Output

if ($code -eq 0) {
    Write-Host "PASS: skill bundled scripts test"
    exit 0
}

[Console]::Error.WriteLine("FAIL: skill bundled scripts test")
if (-not [string]::IsNullOrWhiteSpace($text)) {
    [Console]::Error.WriteLine($text)
}
exit 1
