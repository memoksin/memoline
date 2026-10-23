#
# install.ps1 — deploy the custom Claude Code status line at the USER level
# (~/.claude/), for Windows.
#
# Zero dependencies: Windows PowerShell 5.1 ships with Windows 10/11 and has
# ConvertFrom-Json / ConvertTo-Json built in. No node, no jq, no python, no
# Git Bash. macOS/Linux users run install.sh instead.
#
# What it does:
#   1. Writes ~/.claude/statusline.ps1 (the renderer; reads session JSON on stdin).
#   2. Merges a `statusLine` entry into ~/.claude/settings.json, preserving every
#      other key. Backs the file up first; aborts rather than write invalid JSON.
#   3. Self-tests the wired command through cmd.exe before declaring success.
#   4. If run inside a git repo, adds .env and .claude/settings.local.json to
#      .gitignore (defensive hygiene).
#
# Usage (from the repo folder):
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
#
# IMPORTANT — no API keys are used or needed. Claude Code pipes every metric
# this status line shows directly to the script on stdin. See:
# https://docs.claude.com/en/docs/claude-code/statusline

# StrictMode deliberately left off: it aborts on any unset variable or absent
# property, which turns a cosmetic edge case into a failed install.
Set-StrictMode -Off
$ErrorActionPreference = 'Stop'

function Fail($msg) { Write-Host $msg -ForegroundColor Red; exit 1 }

if ($PSVersionTable.PSVersion.Major -lt 5) {
  Fail "✗ Windows PowerShell 5.1 or newer is required (found $($PSVersionTable.PSVersion))."
}
if ($env:OS -ne 'Windows_NT') {
  Fail "✗ This installer is for Windows. On macOS/Linux run install.sh instead."
}

$srcDir       = Split-Path -Parent $MyInvocation.MyCommand.Path
$home_        = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
$claudeDir    = Join-Path $home_ '.claude'
$statusScript = Join-Path $claudeDir 'statusline.ps1'
$settings     = Join-Path $claudeDir 'settings.json'
$rendererSrc  = Join-Path $srcDir 'statusline.ps1'

# PowerShell 5.1's Out-File/Set-Content default to UTF-16 or add a BOM, either
# of which makes settings.json unreadable to Claude Code. Always write UTF-8
# without a BOM.
function Write-Utf8NoBom([string]$path, [string]$text) {
  [System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding $false))
}

Write-Host '▶ Installing custom status line (user-scoped)'
Write-Host "    into : $claudeDir"

if (-not (Test-Path $rendererSrc)) { Fail "✗ Error: renderer source not found at $rendererSrc" }
if (-not (Test-Path $claudeDir)) { New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null }

# --- Overwrite protection ---
$configExists = Test-Path $statusScript
if (-not $configExists -and (Test-Path $settings)) {
  try {
    $probe = (Get-Content -Raw -Path $settings) | ConvertFrom-Json
    if ($probe -and $probe.PSObject.Properties['statusLine']) { $configExists = $true }
  } catch { }
}

if ($configExists) {
  # Non-interactive stdin (piped, CI, agent invocation) never sends an answer.
  # This installer only runs when explicitly invoked, so treat that as consent
  # rather than blocking forever on a read that will not return.
  if ([Console]::IsInputRedirected) {
    Write-Host 'Configuration already exists. Do you want to overwrite it? (y/n) y (non-interactive stdin, auto-confirmed)'
  } else {
    $answer = Read-Host 'Configuration already exists. Do you want to overwrite it? (y/n)'
    if ($answer -notmatch '^(y|yes)$') { Write-Host '✗ Aborted. No changes were made.'; exit 0 }
  }
  Write-Host '  → overwriting existing configuration…'
}

# --- Write the renderer ---
Copy-Item -Path $rendererSrc -Destination $statusScript -Force
Write-Host "  ✓ wrote $statusScript"

# --- Build the command ---
# The interpreter is named as a bare token so the string parses identically in
# cmd.exe, PowerShell and Git Bash — a leading *quoted* path is a syntax error
# in PowerShell ("C:\x.exe" arg is just a string literal). powershell.exe is
# always on PATH on Windows; -ExecutionPolicy Bypass lets an unsigned .ps1 run
# without needing admin or a machine policy change.
$quoted  = if ($statusScript -match ' ') { '"' + $statusScript + '"' } else { $statusScript }
$command = "powershell -NoProfile -ExecutionPolicy Bypass -File $quoted"

# --- Merge statusLine into settings.json, preserving every other key ---
$entry = [PSCustomObject]@{ type = 'command'; command = $command; padding = 0; refreshInterval = 10 }

$root = $null
if ((Test-Path $settings) -and (Get-Item $settings).Length -gt 0) {
  $rawSettings = Get-Content -Raw -Path $settings
  if ($rawSettings.Trim()) {
    try {
      $root = $rawSettings | ConvertFrom-Json
    } catch {
      Fail "✗ Error: $settings contains invalid JSON. Fix or remove it and re-run.`n  Your file was left untouched."
    }
    if ($root -isnot [PSCustomObject]) { Fail "✗ Error: $settings is not a JSON object. Fix or remove it and re-run." }
  }
  Copy-Item -Path $settings -Destination "$settings.bak" -Force
}
if ($null -eq $root) { $root = [PSCustomObject]@{} }

$root | Add-Member -NotePropertyName 'statusLine' -NotePropertyValue $entry -Force

# -Depth 100: the 5.1 default of 2 silently truncates nested settings (hooks,
# permissions, env) into literal "System.Object[]" strings.
Write-Utf8NoBom $settings (($root | ConvertTo-Json -Depth 100) + "`n")
Write-Host "  ✓ wired statusLine → $settings"

# --- .gitignore hygiene (only when run inside a git repo) ---
try {
  $repoRoot = (& git rev-parse --show-toplevel 2>$null)
  if ($LASTEXITCODE -ne 0) { $repoRoot = $null }
} catch { $repoRoot = $null }

if ($repoRoot) {
  $gitignore = Join-Path $repoRoot '.gitignore'
  $existing  = if (Test-Path $gitignore) { Get-Content -Raw -Path $gitignore } else { '' }
  if ($null -eq $existing) { $existing = '' }
  $lines = $existing -split "`r?`n"
  $toAdd = @('.env', '.claude/settings.local.json') | Where-Object { $lines -notcontains $_ }
  if ($toAdd.Count -gt 0) {
    $sep = if ($existing.Length -gt 0 -and -not $existing.EndsWith("`n")) { "`n" } else { '' }
    Write-Utf8NoBom $gitignore ($existing + $sep + ($toAdd -join "`n") + "`n")
  }
  Write-Host '  ✓ ensured .env and .claude/settings.local.json are in .gitignore'
}

# --- Verify the wired command actually runs ---
# Routed through cmd.exe because that is the shell Claude Code spawns the
# status line with on Windows.
Write-Host ''
Write-Host "  → self-test: $command"
$mock = '{"model":{"display_name":"Test"},"context_window":{"total_input_tokens":1000,"context_window_size":200000},"workspace":{"current_dir":"' +
        ($PWD.Path -replace '\\', '\\') + '"}}'
try {
  $out = @($mock | & cmd.exe /c $command 2>&1)
} catch {
  $out = @()
}
if ($LASTEXITCODE -ne 0 -or $out.Count -ne 3) {
  Write-Host '✗ Self-test FAILED — Claude Code will show a blank status line.' -ForegroundColor Red
  Write-Host "    expected 3 lines, got $($out.Count) (exit $LASTEXITCODE)" -ForegroundColor Red
  ($out | ForEach-Object { Write-Host "    $_" -ForegroundColor Red })
  Write-Host "    Fix the `"statusLine.command`" value in $settings so it runs in your shell." -ForegroundColor Red
  exit 1
}
Write-Host '  ✓ self-test passed:'
$out | ForEach-Object { Write-Host "      $_" }

Write-Host ''
Write-Host '✓ Done. Restart Claude Code to see the status line in every project.'
