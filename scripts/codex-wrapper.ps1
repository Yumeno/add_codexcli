# codex-wrapper.ps1 - Invoke Codex CLI non-interactively from Claude Code
# Usage: powershell -ExecutionPolicy Bypass -File codex-wrapper.ps1 -Prompt "your question"
#
# Options:
#   -Prompt       (required) The prompt to send to Codex
#   -Model        (optional) Model name
#   -Timeout      (optional) Timeout in seconds (default: 120)
#   -WorkDir      (optional) Working directory for codex (default: $env:TEMP)
#   -Context      (optional) Additional context to prepend to the prompt
#   -ContextFile  (optional) Path to a file containing context (avoids cmdline length limits)

param(
    [string]$Prompt = "",
    [string]$Model = "",
    [int]$Timeout = 120,
    [string]$WorkDir = "",
    [string]$Context = "",
    [string]$ContextFile = ""
)

# Max context size in bytes before warning (100KB)
$MaxContextSize = 102400

# --- Input validation ---
if ([string]::IsNullOrWhiteSpace($Prompt)) {
    [Console]::Error.WriteLine("Error: -Prompt is required.")
    exit 1
}

# --- Load context from file if specified ---
if (-not [string]::IsNullOrWhiteSpace($ContextFile)) {
    if (-not (Test-Path $ContextFile)) {
        [Console]::Error.WriteLine("Error: Context file not found: $ContextFile")
        exit 1
    }
    $Context = Get-Content $ContextFile -Raw -Encoding UTF8
}

# --- Context size warning ---
if (-not [string]::IsNullOrWhiteSpace($Context)) {
    if ($Context.Length -gt $MaxContextSize) {
        $sizeKB = [math]::Floor($Context.Length / 1024)
        [Console]::Error.WriteLine("Warning: Context is large (${sizeKB}KB). This may slow down the request.")
    }
}

# --- Determine safe working directory (avoid non-ASCII paths) ---
if ([string]::IsNullOrWhiteSpace($WorkDir)) {
    $WorkDir = $env:TEMP
}

# --- Build the full prompt ---
if (-not [string]::IsNullOrWhiteSpace($Context)) {
    $fullPrompt = "$Context`n`n---`n`n$Prompt"
} else {
    $fullPrompt = $Prompt
}

# --- Write prompt to temp file (avoids cmdline length limits) ---
$suffix = Get-Random -Minimum 10000 -Maximum 99999
$outFile = Join-Path $env:TEMP "codex_out_${suffix}.txt"
$errFile = Join-Path $env:TEMP "codex_err_${suffix}.txt"
$promptFile = Join-Path $env:TEMP "codex_prompt_${suffix}.txt"

function Cleanup {
    foreach ($f in @($script:outFile, $script:errFile, $script:promptFile)) {
        if (Test-Path $f) { Remove-Item $f -Force -ErrorAction SilentlyContinue }
    }
}

try {
    # Write prompt to file for stdin passing
    $fullPrompt | Out-File -FilePath $promptFile -Encoding UTF8 -NoNewline

    # --- Build codex arguments (-- separates options from prompt) ---
    $codexArgs = @("exec", "-C", $WorkDir, "--skip-git-repo-check", "--ephemeral", "-o", $outFile, "--")

    if (-not [string]::IsNullOrWhiteSpace($Model)) {
        # Insert model before --
        $codexArgs = @("exec", "-C", $WorkDir, "--skip-git-repo-check", "--ephemeral", "-o", $outFile, "-m", $Model, "--")
    }

    $codexArgs += $fullPrompt

    # --- Execute codex directly (not in a job, to preserve terminal) ---
    # Redirect stderr to file
    $codexArgsStr = ($codexArgs | ForEach-Object {
        if ($_ -match '[\s"''\\]' -or $_.Length -eq 0) {
            $escaped = $_ -replace '"', '\"'
            "`"$escaped`""
        } else { $_ }
    }) -join " "

    # Use cmd.exe /c with proper escaping via a temp batch file
    $batFile = Join-Path $env:TEMP "codex_run_${suffix}.cmd"
    $codexCmd = (Get-Command codex -ErrorAction Stop).Source -replace '\.ps1$', '.cmd'
    if (-not (Test-Path $codexCmd)) {
        # Fallback to .ps1
        $codexCmd = (Get-Command codex -ErrorAction Stop).Source
    }

    # Build the command - pass prompt as last argument
    "@echo off" | Out-File -FilePath $batFile -Encoding ASCII
    "call `"$codexCmd`" $codexArgsStr 2>`"$errFile`"" | Out-File -FilePath $batFile -Encoding ASCII -Append

    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = "cmd.exe"
    $pinfo.Arguments = "/c `"$batFile`""
    $pinfo.UseShellExecute = $false
    $pinfo.CreateNoWindow = $true
    $pinfo.RedirectStandardOutput = $false
    $pinfo.RedirectStandardError = $false

    $process = [System.Diagnostics.Process]::Start($pinfo)
    $exited = $process.WaitForExit($Timeout * 1000)

    if (-not $exited) {
        try { $process.Kill() } catch {}
        [Console]::Error.WriteLine("Error: Codex CLI timed out after ${Timeout}s")
        Cleanup
        if (Test-Path $batFile) { Remove-Item $batFile -Force -ErrorAction SilentlyContinue }
        exit 2
    }

    $codexExit = $process.ExitCode
    if (Test-Path $batFile) { Remove-Item $batFile -Force -ErrorAction SilentlyContinue }

    # --- Read output ---
    if (Test-Path $outFile) {
        $output = (Get-Content $outFile -Raw -Encoding UTF8).Trim()
        if ($output.Length -gt 0) {
            Write-Output $output
        } else {
            [Console]::Error.WriteLine("Codex CLI returned empty output.")
            if ((Test-Path $errFile) -and (Get-Item $errFile).Length -gt 0) {
                [Console]::Error.WriteLine("Stderr:")
                [Console]::Error.WriteLine((Get-Content $errFile -Raw -Encoding UTF8))
            }
            Cleanup
            exit 1
        }
    } else {
        [Console]::Error.WriteLine("Codex CLI produced no output file. Exit code: $codexExit")
        if ((Test-Path $errFile) -and (Get-Item $errFile).Length -gt 0) {
            [Console]::Error.WriteLine("Stderr:")
            [Console]::Error.WriteLine((Get-Content $errFile -Raw -Encoding UTF8))
        }
        Cleanup
        exit 1
    }
} catch {
    [Console]::Error.WriteLine("Error: $_")
    Cleanup
    exit 1
}

Cleanup

# If output was successfully read, exit 0 (cmd.exe exit codes are unreliable
# due to stderr noise from codex deprecation warnings setting ERRORLEVEL).
# Only propagate non-zero if no output was produced (handled above).
exit 0
