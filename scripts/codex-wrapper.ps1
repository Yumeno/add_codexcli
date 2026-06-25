# codex-wrapper.ps1 - Invoke Codex CLI non-interactively from Claude Code
# Usage: powershell -ExecutionPolicy Bypass -File codex-wrapper.ps1 -Prompt "your question"
#
# Options:
#   -Prompt        (required for invocation) The prompt to send to Codex
#   -Model         (optional) Model name
#   -Timeout       (optional) Timeout in seconds (default: 120)
#   -Cd            (optional) Working directory for codex (default: ASCII temp)
#   -WorkDir       (optional, alias for -Cd; kept for backward compatibility)
#                  Passing both is an error — there is no silent precedence.
#   -Context       (optional) Additional context to prepend to the prompt
#   -ContextFile   (optional) Path to a file containing context (avoids cmdline length limits)
#   -SandboxMode   (optional) Codex sandbox mode: read-only | workspace-write | danger-full-access
#                  Default: read-only. Mirrors the bash wrapper (issue #14): codex CLI's implicit
#                  default for non-VCS workdirs and prevents the workspace-write+on-request stall
#                  when -Cd points at a git repository.
#
# Config subcommands (do not invoke codex):
#   -SetModel NAME  Persist NAME as the default model in codex-wrapper.conf
#   -ShowModel      Print the currently resolved model and its source, then exit

param(
    [string]$Prompt = "",
    [string]$Model = "",
    [int]$Timeout = 120,
    [string]$WorkDir = "",
    [string]$Cd = "",
    [string]$Context = "",
    [string]$ContextFile = "",
    # NOTE: deliberately no [ValidateSet] here. PS's own ValidateSet rejection
    # happens before the script body runs, so we cannot route it through Fail
    # and the sentinel is never emitted. We validate manually below instead.
    [string]$SandboxMode = "read-only",
    [string]$SetModel = "",
    [switch]$ShowModel
)

# Force UTF-8 on stdout/stderr so Japanese (and other non-ASCII) round-trips
# correctly through msys/bash pipes. On JP Windows the Console default is
# CP932 (Shift-JIS), which corrupts the UTF-8 we already produce internally.
# - [Console]::OutputEncoding: bytes .NET writes to stdout/stderr
# - $OutputEncoding: encoding PS uses when piping to external processes
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# Sentinel printed to stdout on every failure path so callers that cannot
# separate stdout/stderr (the documented "bare single command" SKILL.md
# invocation under Claude Code's permit umbrella) can still detect failure
# from the stdout stream alone. See issue #19 review feedback / issue #20.
$ErrorSentinel = "[CODEX_WRAPPER_ERROR]"

# Fail <code> <message>
# Emits "<sentinel> <message>" to stdout, the same message to stderr, exits.
function Fail {
    param([int]$Code, [string]$Message)
    Write-Output ("{0} {1}" -f $ErrorSentinel, $Message)
    [Console]::Error.WriteLine("Error: $Message")
    exit $Code
}

# -Cd / -WorkDir reconciliation. Both name the same concept; -Cd matches the
# Codex CLI's own --cd / -C flag. We reject the both-specified case rather
# than silently picking one — silent precedence is the kind of thing that
# bites callers months later, when the value they thought they had is being
# ignored.
if ((-not [string]::IsNullOrWhiteSpace($Cd)) -and (-not [string]::IsNullOrWhiteSpace($WorkDir))) {
    Fail 1 "-Cd and -WorkDir are aliases; pass only one."
}
if (-not [string]::IsNullOrWhiteSpace($Cd)) {
    $WorkDir = $Cd
}

# Max context size in bytes before warning (100KB)
$MaxContextSize = 102400

# Config file lives next to this script. Same relative position whether the
# install is project-local (<proj>\scripts\) or global (~\.claude\scripts\).
$ConfigFile = Join-Path $PSScriptRoot "codex-wrapper.conf"

# Single regex used to validate every model name we touch, regardless of source
# (CLI flag, env var, conf file, -SetModel). The wrapper announces the model
# on stderr as `MODEL: <name>` and SKILLs grep that line back out, so any
# newline or shell-meta character here is a protocol-spoofing vector.
$ModelNameRegex = '^[A-Za-z0-9._:/-]+$'

function Test-ModelName {
    param([string]$Value, [string]$Source)
    if ($Value -notmatch $ModelNameRegex) {
        Fail 1 ("model name from {0} contains unsafe characters: '{1}' (allowed: A-Z a-z 0-9 . _ : / -)" -f $Source, $Value)
    }
}

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
    Test-ModelName -Value $SetModel -Source "-SetModel"
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
    Test-ModelName -Value $Model -Source "-Model"
    $ModelSource = "cli"
} elseif (-not [string]::IsNullOrWhiteSpace($env:CODEX_WRAPPER_MODEL)) {
    Test-ModelName -Value $env:CODEX_WRAPPER_MODEL -Source '$env:CODEX_WRAPPER_MODEL'
    $Model = $env:CODEX_WRAPPER_MODEL
    $ModelSource = "env"
} else {
    $cfgModel = Read-ConfigModel
    if (-not [string]::IsNullOrWhiteSpace($cfgModel)) {
        Test-ModelName -Value $cfgModel -Source $ConfigFile
        $Model = $cfgModel
        $ModelSource = "config"
    }
}

# --- Subcommand: -ShowModel (print resolved model, exit) ---
if ($ShowModel) {
    if (-not [string]::IsNullOrWhiteSpace($Model)) {
        # $Model has been Test-ModelName'd above, so printing it here cannot
        # smuggle extra lines or shell metacharacters.
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
    Fail 1 "-Prompt is required."
}

# Manual whitelist for -SandboxMode (see param block comment). Anything outside
# the documented set fails fast through Fail so the sentinel is emitted.
$AllowedSandboxModes = @("read-only", "workspace-write", "danger-full-access")
if ($AllowedSandboxModes -notcontains $SandboxMode) {
    Fail 1 ("-SandboxMode must be one of: read-only | workspace-write | danger-full-access (got: '{0}')." -f $SandboxMode)
}

# --- Load context from file if specified ---
if (-not [string]::IsNullOrWhiteSpace($ContextFile)) {
    if (-not (Test-Path $ContextFile)) {
        Fail 1 "Context file not found: $ContextFile"
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

# --- Resolve & verify an ASCII-only working directory ---
# Codex CLI's WebSocket layer fails on non-ASCII paths (Windows users with
# Japanese usernames hit this through $env:TEMP -> C:\Users\<jp>\AppData\...),
# so non-ASCII is a hard error rather than a silent fallback.
# Resolution chain:
#   1. -WorkDir if given (ASCII-checked)
#   2. $env:CODEX_WRAPPER_TEMP if set
#   3. $env:TEMP if ASCII
#   4. auto-create C:\tmp\codex-wrapper-<PID>
#   5. explicit error
function Test-IsAscii {
    param([string]$Path)
    return ($Path -notmatch '[^\x20-\x7E]')
}

function Resolve-AsciiWorkDir {
    if (-not [string]::IsNullOrWhiteSpace($script:WorkDir)) {
        if (-not (Test-IsAscii $script:WorkDir)) {
            Fail 1 "-Cd / -WorkDir must be ASCII-only due to Codex CLI WebSocket limitations: $($script:WorkDir)"
        }
        $candidate = $script:WorkDir
    } elseif (-not [string]::IsNullOrWhiteSpace($env:CODEX_WRAPPER_TEMP)) {
        if (-not (Test-IsAscii $env:CODEX_WRAPPER_TEMP)) {
            Fail 1 "`$env:CODEX_WRAPPER_TEMP must be ASCII-only: $($env:CODEX_WRAPPER_TEMP)"
        }
        $candidate = $env:CODEX_WRAPPER_TEMP
    } elseif ((-not [string]::IsNullOrWhiteSpace($env:TEMP)) -and (Test-IsAscii $env:TEMP)) {
        $candidate = $env:TEMP
    } else {
        # Build a per-process ASCII fallback under C:\tmp.
        $candidate = "C:\tmp\codex-wrapper-$PID"
        try {
            New-Item -ItemType Directory -Path $candidate -Force -ErrorAction Stop | Out-Null
        } catch {
            Fail 1 "`$env:TEMP is non-ASCII ('$($env:TEMP)') and fallback '$candidate' is not creatable: $_. Set `$env:CODEX_WRAPPER_TEMP or -WorkDir to an ASCII directory."
        }
    }
    if (-not (Test-Path $candidate -PathType Container)) {
        Fail 1 "workdir does not exist: $candidate"
    }
    return $candidate
}
$WorkDir = Resolve-AsciiWorkDir

# Whether the caller supplied any context (via -Context or -ContextFile). We
# track this as a boolean separate from the string value so that an explicit
# empty context is preserved (rather than silently re-interpreted as "no
# context, fall back to argv-only").
$hasContext = -not [string]::IsNullOrWhiteSpace($Context)

# --- Temp files (placed under the validated ASCII workdir) ---
$suffix = Get-Random -Minimum 10000 -Maximum 99999
$outFile = Join-Path $WorkDir "codex_out_${suffix}.txt"
$errFile = Join-Path $WorkDir "codex_err_${suffix}.txt"

function Cleanup {
    foreach ($f in @($script:outFile, $script:errFile)) {
        if (Test-Path $f) { Remove-Item $f -Force -ErrorAction SilentlyContinue }
    }
}

# --- Argv quoting per CommandLineToArgvW rules (issue #11) ---
# Naive quoting (`replace " with \" then wrap in "`) gets the boundary cases
# wrong: trailing backslashes inside a quoted token get doubled by the
# de-quoter into closing it early. The Microsoft-documented rule is:
#   - 2n backslashes followed by " → n backslashes plus a literal "
#   - 2n+1 backslashes followed by " → n backslashes plus an escaped "
#   - Any other backslash run is literal
# We implement that, plus only wrap the argument in quotes when it contains
# whitespace, " or is empty. Single backslashes in middle-of-path positions
# stay untouched.
function Convert-ArgumentToCommandLine {
    param([string]$Argument)
    if ($null -eq $Argument) { return '""' }
    if ($Argument -eq "") { return '""' }

    $needsQuoting = ($Argument -match '[\s"]')
    if (-not $needsQuoting) { return $Argument }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('"')
    $i = 0
    while ($i -lt $Argument.Length) {
        $backslashes = 0
        while ($i -lt $Argument.Length -and $Argument[$i] -eq '\') {
            $backslashes++
            $i++
        }
        if ($i -eq $Argument.Length) {
            # Trailing backslashes: must double them so the closing " stays a delimiter.
            [void]$sb.Append('\' * ($backslashes * 2))
            break
        } elseif ($Argument[$i] -eq '"') {
            # Backslashes before a literal " — double them and escape the quote.
            [void]$sb.Append('\' * ($backslashes * 2 + 1))
            [void]$sb.Append('"')
            $i++
        } else {
            # Backslashes followed by something else — keep them literal.
            [void]$sb.Append('\' * $backslashes)
            [void]$sb.Append($Argument[$i])
            $i++
        }
    }
    [void]$sb.Append('"')
    return $sb.ToString()
}

$codexExit = 0
try {
    # --- Build codex arguments ---
    # Sandbox is always passed. Default read-only mirrors the bash wrapper
    # (issue #14 / PR #15) and codex CLI's implicit default for non-VCS
    # workdirs; it avoids the workspace-write + on-request stall when -Cd
    # points at a git repository.
    $codexArgs = @("exec", "-C", $WorkDir, "-s", $SandboxMode, "--skip-git-repo-check", "--ephemeral", "-o", $outFile)

    if (-not [string]::IsNullOrWhiteSpace($Model)) {
        $codexArgs += @("-m", $Model)
        # Announce the resolved model on stderr so callers (e.g. SKILLs) can
        # display it without guessing. Emitted whenever we have a concrete model
        # (cli / env / config); when nothing resolved we stay silent because we
        # cannot know which model codex itself picked.
        [Console]::Error.WriteLine("MODEL: $Model")
    }

    # Prompt goes as the positional argument after `--`. Context (if any) is
    # streamed via stdin in a separate step; `codex exec --help` documents
    # that "if stdin is piped and a prompt is also provided, stdin is appended
    # as a <stdin> block", which is exactly the segmentation we want.
    $codexArgs += @("--", $Prompt)

    # --- Resolve codex executable ---
    # npm installs codex.ps1 + codex.cmd; we need the .cmd for Process.Start
    $codexSource = (Get-Command codex -ErrorAction Stop).Source
    $codexCmd = $codexSource -replace '\.ps1$', '.cmd'
    if (-not (Test-Path $codexCmd)) {
        $codexCmd = $codexSource
    }

    # --- Build argument string for Process.Start ---
    $escapedArgs = ($codexArgs | ForEach-Object {
        Convert-ArgumentToCommandLine -Argument $_
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

    # Stdin protocol:
    #   - With context: write context bytes (no trailing newline so the file
    #     boundary is preserved), then close stdin. codex sees a <stdin> block.
    #   - Without context: close stdin immediately so codex doesn't block
    #     waiting for input.
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $writer = New-Object System.IO.StreamWriter($process.StandardInput.BaseStream, $utf8NoBom)
    if ($hasContext) {
        $writer.Write($Context)
    }
    $writer.Close()

    # Read stdout and stderr asynchronously to avoid deadlock
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()

    $exited = $process.WaitForExit($Timeout * 1000)

    if (-not $exited) {
        try { $process.Kill() } catch {}
        Cleanup
        Fail 2 "Codex CLI timed out after ${Timeout}s"
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
            # Codex ran but produced no usable content. We emit the sentinel
            # + short reason on stdout (so skills detecting failure via the
            # combined stream still see it), and also dump codex's own stderr
            # to wrapper's stderr for human debugging.
            Write-Output ("{0} Codex CLI returned empty output (exit={1})." -f $ErrorSentinel, $codexExit)
            [Console]::Error.WriteLine("Error: Codex CLI returned empty output.")
            if ((Test-Path $errFile) -and (Get-Item $errFile).Length -gt 0) {
                [Console]::Error.WriteLine("Stderr:")
                [Console]::Error.WriteLine((Get-Content $errFile -Raw -Encoding UTF8))
            }
            Cleanup
            exit 1
        }
    } else {
        Write-Output ("{0} Codex CLI produced no output file (exit={1})." -f $ErrorSentinel, $codexExit)
        [Console]::Error.WriteLine("Error: Codex CLI produced no output file. Exit code: $codexExit")
        if ((Test-Path $errFile) -and (Get-Item $errFile).Length -gt 0) {
            [Console]::Error.WriteLine("Stderr:")
            [Console]::Error.WriteLine((Get-Content $errFile -Raw -Encoding UTF8))
        }
        Cleanup
        exit 1
    }
} catch {
    Cleanup
    Fail 1 ("{0}" -f $_)
}

Cleanup

# Propagate codex's exit code so CI / upstream callers can detect failures.
# Matches the bash wrapper's contract; the legacy "always exit 0" behaviour
# was a workaround for cmd.exe ERRORLEVEL noise that no longer applies now
# that we invoke codex via Process.Start instead of through cmd.exe.
#
# Sentinel: codex produced *some* output (it was printed above), but the run
# itself failed; without the sentinel the skill would see only the partial
# content and read it as a normal answer.
if ($codexExit -ne 0) {
    Write-Output ("{0} Codex CLI exited with non-zero status: {1}" -f $ErrorSentinel, $codexExit)
    [Console]::Error.WriteLine("Error: Codex CLI exited with non-zero status: $codexExit")
    exit $codexExit
}
exit 0
