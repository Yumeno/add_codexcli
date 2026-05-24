# codex-wrapper.ps1 - Invoke Codex CLI non-interactively from Claude Code
# Usage: powershell -ExecutionPolicy Bypass -File codex-wrapper.ps1 -Prompt "your question"
#
# Options:
#   -Prompt       (required for invocation) The prompt to send to Codex
#   -Model        (optional) Model name
#   -Timeout      (optional) Timeout in seconds (default: 120)
#   -WorkDir      (optional) Working directory for codex (default: $env:TEMP)
#   -Context      (optional) Additional context to prepend to the prompt
#   -ContextFile  (optional) Path to a file containing context (avoids cmdline length limits)
#
# Config subcommands (do not invoke codex):
#   -SetModel NAME  Persist NAME as the default model in codex-wrapper.conf
#   -ShowModel      Print the currently resolved model and its source, then exit

param(
    [string]$Prompt = "",
    [string]$Model = "",
    [int]$Timeout = 120,
    [string]$WorkDir = "",
    [string]$Context = "",
    [string]$ContextFile = "",
    [string]$SetModel = "",
    [switch]$ShowModel
)

# Max context size in bytes before warning (100KB)
$MaxContextSize = 102400

# Config file lives next to this script. Same relative position whether the
# install is project-local (<proj>\scripts\) or global (~\.claude\scripts\).
$ConfigFile = Join-Path $PSScriptRoot "codex-wrapper.conf"

function Read-ConfigModel {
    if (-not (Test-Path $ConfigFile)) { return "" }
    foreach ($line in (Get-Content $ConfigFile -Encoding UTF8)) {
        $trimmed = $line.Trim()
        if ($trimmed -eq "" -or $trimmed.StartsWith("#")) { continue }
        if ($trimmed -match '^\s*model\s*=\s*(.*?)\s*$') {
            $val = $matches[1]
            if (($val.StartsWith('"') -and $val.EndsWith('"')) -or
                ($val.StartsWith("'") -and $val.EndsWith("'"))) {
                $val = $val.Substring(1, $val.Length - 2)
            }
            return $val
        }
    }
    return ""
}

# --- Subcommand: -SetModel (write config, exit) ---
if (-not [string]::IsNullOrWhiteSpace($SetModel)) {
    if ($SetModel -notmatch '^[A-Za-z0-9._:/-]+$') {
        [Console]::Error.WriteLine("Error: model name '$SetModel' contains unsafe characters.")
        [Console]::Error.WriteLine("       Allowed: A-Z a-z 0-9 . _ : / -")
        exit 1
    }
    $confContent = @"
# codex-wrapper.conf
# Default options for codex-wrapper.sh / codex-wrapper.ps1.
# Edit this file directly, or use:
#   powershell -File codex-wrapper.ps1 -SetModel <name>
#
# Lookup priority for the model:
#   1. --model / -Model CLI flag
#   2. `$CODEX_WRAPPER_MODEL environment variable
#   3. this file (model=...)
#   4. unset (codex CLI default)

model=$SetModel
"@
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($ConfigFile, $confContent, $utf8NoBom)
    Write-Output "Saved model='$SetModel' to $ConfigFile"
    exit 0
}

# --- Resolve effective model (priority: -Model > env > config) ---
$ModelSource = ""
if (-not [string]::IsNullOrWhiteSpace($Model)) {
    $ModelSource = "cli"
} elseif (-not [string]::IsNullOrWhiteSpace($env:CODEX_WRAPPER_MODEL)) {
    $Model = $env:CODEX_WRAPPER_MODEL
    $ModelSource = "env"
} else {
    $cfgModel = Read-ConfigModel
    if (-not [string]::IsNullOrWhiteSpace($cfgModel)) {
        $Model = $cfgModel
        $ModelSource = "config"
    }
}

# --- Subcommand: -ShowModel (print resolved model, exit) ---
if ($ShowModel) {
    if (-not [string]::IsNullOrWhiteSpace($Model)) {
        Write-Output "model=$Model (source: $ModelSource)"
        if ($ModelSource -eq "config") {
            Write-Output "config_file=$ConfigFile"
        }
    } else {
        Write-Output "model=(unset; codex CLI default will be used)"
        if (Test-Path $ConfigFile) {
            Write-Output "config_file=$ConfigFile (no model= entry)"
        } else {
            Write-Output "config_file=$ConfigFile (does not exist)"
        }
    }
    exit 0
}

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
        # Announce the resolved model on stderr so callers (e.g. SKILLs) can
        # display it without guessing. Emitted whenever we have a concrete model
        # (cli / env / config); when nothing resolved we stay silent because we
        # cannot know which model codex itself picked.
        [Console]::Error.WriteLine("MODEL: $Model")
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
