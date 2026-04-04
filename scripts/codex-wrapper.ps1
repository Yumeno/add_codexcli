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
    # Write prompt to file for stdin passing (avoids cmdline length limits)
    $fullPrompt | Out-File -FilePath $promptFile -Encoding UTF8 -NoNewline

    # --- Build codex arguments (prompt passed via stdin, not cmdline) ---
    $codexArgs = @("exec", "-C", $WorkDir, "--skip-git-repo-check", "--ephemeral", "-o", $outFile)

    if (-not [string]::IsNullOrWhiteSpace($Model)) {
        $codexArgs += @("-m", $Model)
    }

    # Use "-" to tell codex to read prompt from stdin
    $codexArgs += "--"
    $codexArgs += "-"

    # --- Resolve codex executable ---
    # npm installs codex.ps1 + codex.cmd; we need the .cmd for Process.Start
    $codexSource = (Get-Command codex -ErrorAction Stop).Source
    $codexCmd = $codexSource -replace '\.ps1$', '.cmd'
    if (-not (Test-Path $codexCmd)) {
        $codexCmd = $codexSource
    }

    # --- Build argument string for Process.Start ---
    $escapedArgs = ($codexArgs | ForEach-Object {
        $escaped = $_ -replace '"', '\"'
        "`"$escaped`""
    }) -join " "

    # --- Execute codex via Process.Start (no cmd.exe, no batch file) ---
    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = $codexCmd
    $pinfo.Arguments = $escapedArgs
    $pinfo.UseShellExecute = $false
    $pinfo.CreateNoWindow = $true
    $pinfo.RedirectStandardInput = $true
    $pinfo.RedirectStandardOutput = $true
    $pinfo.RedirectStandardError = $true

    $process = [System.Diagnostics.Process]::Start($pinfo)

    # Write prompt to stdin using BOM-less UTF-8 (PS 5.1 compatible)
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $writer = New-Object System.IO.StreamWriter($process.StandardInput.BaseStream, $utf8NoBom)
    $writer.Write($fullPrompt)
    $writer.Close()

    # Read stdout and stderr asynchronously to avoid deadlock
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()

    $exited = $process.WaitForExit($Timeout * 1000)

    if (-not $exited) {
        try { $process.Kill() } catch {}
        [Console]::Error.WriteLine("Error: Codex CLI timed out after ${Timeout}s")
        Cleanup
        exit 2
    }

    $codexExit = $process.ExitCode
    $null = $stdoutTask.Result  # Consume stdout (we read from -o file instead)
    $stderrContent = $stderrTask.Result

    # Write stderr to file for error reporting
    if ($stderrContent) {
        $stderrContent | Out-File -FilePath $errFile -Encoding UTF8
    }

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
