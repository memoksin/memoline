#
# Claude Code custom three-line status line — Windows PowerShell 5.1+.
# Reads the session JSON on stdin and prints a color-coded status.
# Field reference: https://docs.claude.com/en/docs/claude-code/statusline
#
# Zero dependencies: Windows PowerShell 5.1 ships with Windows 10/11 and has
# ConvertFrom-Json built in. No node, no jq, no python.
#
# Line 1: Model | Used/Total | Used%(color) used Tok | Remaining%(color) remain Tok
# Line 2: effort: Effort | repo: Repo (branch)
# Line 3: Current Usage Limit: Used%/100%(color) (resets in Xh Ym) | Weekly Usage Limit: ...
#
# Color coding:
#   "used"      semantics (higher = worse):  green < 50%, yellow 50-80%, red >= 80%
#   "remaining" semantics (higher = better): green > 50%, yellow 20-50%, red <= 20%

Set-StrictMode -Off
$ErrorActionPreference = 'SilentlyContinue'

$E       = [char]27
$RESET   = "$E[0m"; $BOLD    = "$E[1m"
$GREEN   = "$E[32m"; $YELLOW = "$E[33m"; $RED  = "$E[31m"
$CYAN    = "$E[36m"; $MAGENTA= "$E[35m"; $GREY = "$E[90m"

# Invariant culture: "{0:F2}" renders "0,50" under a comma-decimal locale
# (tr-TR, de-DE, fr-FR, ...), which would corrupt the percentages.
$INV = [System.Globalization.CultureInfo]::InvariantCulture

$raw = [Console]::In.ReadToEnd()
if ($null -eq $raw) { $raw = '' }

# Optional debug: dump the raw stdin payload for inspection.
# Enable with: New-Item ~/.claude/.statusline-debug
$claudeDir = Join-Path $(if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }) '.claude'
if (Test-Path (Join-Path $claudeDir '.statusline-debug')) {
  try {
    [System.IO.File]::WriteAllText((Join-Path $claudeDir '.statusline-payload.json'), $raw)
  } catch { }
}

$data = $null
try { if ($raw.Trim()) { $data = $raw | ConvertFrom-Json } } catch { $data = $null }

# PowerShell 5.1 has no null-conditional operator; walk the path defensively.
function Get-Path($obj, [string[]]$path) {
  foreach ($p in $path) {
    if ($null -eq $obj) { return $null }
    $prop = $obj.PSObject.Properties[$p]
    if ($null -eq $prop) { return $null }
    $obj = $prop.Value
  }
  return $obj
}

function Get-Num($obj, [string[]]$path, $default) {
  $v = Get-Path $obj $path
  if ($null -eq $v -or $v -eq '') { return $default }
  try { return [double]$v } catch { return $default }
}

function Format-Human([double]$n) {
  if ($n -ge 1000000) { return [string]::Format($INV, '{0:F1}M', $n / 1000000) }
  if ($n -ge 1000)    { return [string]::Format($INV, '{0:F1}k', $n / 1000) }
  return [string]::Format($INV, '{0:D}', [int][math]::Truncate($n))
}

function Get-ColorUsed([double]$p) { if ($p -ge 80) { $RED } elseif ($p -ge 50) { $YELLOW } else { $GREEN } }
function Get-ColorRem([double]$p)  { if ($p -le 20) { $RED } elseif ($p -le 50) { $YELLOW } else { $GREEN } }

function Format-Duration([double]$sec) {
  if ($sec -lt 0) { $sec = 0 }
  $d = [math]::Truncate($sec / 86400); $sec -= $d * 86400
  $h = [math]::Truncate($sec / 3600);  $sec -= $h * 3600
  $m = [math]::Truncate($sec / 60)
  if ($d -gt 0) { return "${d}d ${h}h" }
  if ($h -gt 0) { return "${h}h ${m}m" }
  return "${m}m"
}

function Format-Limit([string]$label, $used, $resetsAt) {
  if ($null -eq $used) { return "${label}: ${GREY}n/a${RESET}" }
  $c = Get-ColorUsed $used
  $out = "${label}: ${c}${used}%${RESET} / ${GREEN}100%${RESET}"
  if ($resetsAt) {
    $remaining = [double]$resetsAt - [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $out += " ${GREY}(resets $(Format-Duration $remaining))${RESET}"
  }
  return $out
}

$model = Get-Path $data @('model', 'display_name')
if (-not $model) { $model = 'Unknown' }

$usedTokens = Get-Num $data @('context_window', 'total_input_tokens') 0
$ctxSize    = Get-Num $data @('context_window', 'context_window_size') 200000
if ($ctxSize -le 0) { $ctxSize = 200000 }

$usedPct = Get-Path $data @('context_window', 'used_percentage')
if ($null -eq $usedPct) { $usedPct = ($usedTokens / $ctxSize) * 100 } else { $usedPct = [double]$usedPct }
$remPct = Get-Path $data @('context_window', 'remaining_percentage')
if ($null -eq $remPct) { $remPct = 100 - $usedPct } else { $remPct = [double]$remPct }
$remTokens = $ctxSize - $usedTokens

$effort = Get-Path $data @('effort', 'level')
if (-not $effort) { $effort = 'n/a' }

$cwd = Get-Path $data @('workspace', 'current_dir')
if (-not $cwd) { $cwd = Get-Path $data @('cwd') }

$repo = Get-Path $data @('workspace', 'repo', 'name')
if (-not $repo) {
  if ($cwd) { $repo = Split-Path -Leaf ($cwd.TrimEnd('\', '/')) }
  if (-not $repo) { $repo = '(no repo)' }
}

$branch = ''
if ($cwd) {
  try {
    $branch = & git -C $cwd branch --show-current 2>$null
    if ($LASTEXITCODE -ne 0) { $branch = '' }
  } catch { $branch = '' }
}

$fiveUsed   = Get-Path $data @('rate_limits', 'five_hour', 'used_percentage')
$sevenUsed  = Get-Path $data @('rate_limits', 'seven_day', 'used_percentage')
$fiveReset  = Get-Path $data @('rate_limits', 'five_hour', 'resets_at')
$sevenReset = Get-Path $data @('rate_limits', 'seven_day', 'resets_at')

$SEP = "${GREY} | ${RESET}"
$cu  = Get-ColorUsed $usedPct
$cr  = Get-ColorRem $remPct

$usedPctStr = [string]::Format($INV, '{0:F2}', $usedPct)
$remPctStr  = [string]::Format($INV, '{0:F2}', $remPct)

$line1  = "${BOLD}${CYAN}${model}${RESET}"
$line1 += "${SEP}$(Format-Human $usedTokens) / $(Format-Human $ctxSize)"
$line1 += "${SEP}${cu}${usedPctStr}%${RESET} ${GREY}used${RESET} $(Format-Human $usedTokens)"
$line1 += "${SEP}${cr}${remPctStr}%${RESET} ${GREY}remain${RESET} $(Format-Human $remTokens)"

$line2  = "${GREY}effort:${RESET} ${MAGENTA}${effort}${RESET}${SEP}${GREY}repo:${RESET} ${repo}"
if ($branch) { $line2 += " ${GREY}(${RESET}${CYAN}${branch}${RESET}${GREY})${RESET}" }

$line3  = Format-Limit 'Current Usage Limit' $fiveUsed $fiveReset
$line3 += "${SEP}$(Format-Limit 'Weekly Usage Limit' $sevenUsed $sevenReset)"

# Write-Output would append the host's line ending and can wrap; emit directly.
[Console]::Out.Write("$line1`n$line2`n$line3`n")
