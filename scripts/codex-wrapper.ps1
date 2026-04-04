# codex-wrapper.ps1 - Invoke Codex CLI non-interactively from Claude Code
# Usage: powershell -ExecutionPolicy Bypass -File codex-wrapper.ps1 -Prompt "your question"
#
# Options:
#   -Prompt   (required) The prompt to send to Codex
#   -Model    (optional) Model name (default: gpt-5.2-codex)
#   -Timeout  (optional) Timeout in seconds (default: 120)
#   -WorkDir  (optional) Working directory for codex (default: $env:TEMP)
#   -Context  (optional) Additional context to prepend to the prompt

param(
    [string]$Prompt = "",
    [string]$Model = "",
    [int]$Timeout = 120,
    [string]$WorkDir = "",
    [string]$Context = ""
)

# --- Input validation ---
if ([string]::IsNullOrWhiteSpace($Prompt)) {
    [Console]::Error.WriteLine("Error: -Prompt is required.")
    exit 1
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

# --- Temp file for output ---
$suffix = Get-Random -Minimum 10000 -Maximum 99999
$outFile = Join-Path $env:TEMP "codex_out_${suffix}.txt"

function Cleanup {
    if (Test-Path $script:outFile) { Remove-Item $script:outFile -Force -ErrorAction SilentlyContinue }
}

try {
    # --- Build codex arguments ---
    $codexArgs = @("exec", "-C", $WorkDir, "--skip-git-repo-check", "--ephemeral", "-o", $outFile)

    if (-not [string]::IsNullOrWhiteSpace($Model)) {
        $codexArgs += @("-m", $Model)
    }

    $codexArgs += $fullPrompt

    # --- Execute codex as a background job with timeout ---
    $job = Start-Job -ScriptBlock {
        param($args_list)
        & codex @args_list 2>$null
    } -ArgumentList (,$codexArgs)

    $completed = $job | Wait-Job -Timeout $Timeout

    if ($null -eq $completed) {
        $job | Stop-Job
        $job | Remove-Job -Force
        [Console]::Error.WriteLine("Error: Codex CLI timed out after ${Timeout}s")
        Cleanup
        exit 2
    }

    # Consume job output (discard - we use the -o file)
    $null = Receive-Job -Job $job
    $job | Remove-Job -Force

    # --- Read output ---
    if (Test-Path $outFile) {
        $output = (Get-Content $outFile -Raw -Encoding UTF8).Trim()
        if ($output.Length -gt 0) {
            Write-Output $output
        } else {
            [Console]::Error.WriteLine("Codex CLI returned empty output.")
            Cleanup
            exit 1
        }
    } else {
        [Console]::Error.WriteLine("Codex CLI produced no output file.")
        Cleanup
        exit 1
    }
} catch {
    [Console]::Error.WriteLine("Error: $_")
    Cleanup
    exit 1
}

Cleanup
exit 0
