#!/bin/sh
#
# Claude Code custom three-line status line — POSIX sh + awk (macOS/Linux/BSD).
# Reads the session JSON on stdin and prints a color-coded status.
# Field reference: https://docs.claude.com/en/docs/claude-code/statusline
#
# Zero dependencies: `sh` and `awk` are POSIX-mandated and present on every
# Unix. No node, no jq, no python, no bashisms.
#
# Line 1: Model | Used/Total | Used%(color) used Tok | Remaining%(color) remain Tok
# Line 2: effort: Effort | repo: Repo
# Line 3: Current Usage Limit: Used%/100%(color) | Weekly Usage Limit: ...
#
# Color coding:
#   "used"      semantics (higher = worse):  green < 50%, yellow 50-80%, red >= 80%
#   "remaining" semantics (higher = better): green > 50%, yellow 20-50%, red <= 20%

# Force C locale: printf "%.2f" emits "0,50" instead of "0.50" under locales
# with a comma decimal separator (tr_TR, de_DE, fr_FR, ...).
LC_ALL=C
export LC_ALL

HOME_DIR="${HOME:-.}"

render() {
  awk '
# ---- JSON helpers -----------------------------------------------------------
# The session schema is shallow and its key names are unique, so isolating a
# flat object by name and reading leaf keys out of it is sufficient. Anything
# missing or malformed falls back to a default rather than erroring.

# Substring of the flat object bound to "key", e.g. {"a":1,"b":2}
function obj(doc, key,   p, s) {
  p = index(doc, "\"" key "\"")
  if (p == 0) return ""
  s = substr(doc, p)
  p = index(s, "{")
  if (p == 0) return ""
  s = substr(s, p)
  p = index(s, "}")
  if (p == 0) return ""
  return substr(s, 1, p)
}

# Value of "key" inside object string o, as text ("" when absent).
function str(o, key, p, s, q, c, out) {
  if (o == "") return ""
  p = index(o, "\"" key "\"")
  if (p == 0) return ""
  s = substr(o, p + length(key) + 2)
  p = index(s, ":")
  if (p == 0) return ""
  s = substr(s, p + 1)
  sub(/^[ \t\r\n]+/, "", s)
  if (substr(s, 1, 1) == "\"") {
    s = substr(s, 2)
    out = ""
    q = 1
    while (q <= length(s)) {
      c = substr(s, q, 1)
      if (c == "\\") { out = out substr(s, q + 1, 1); q += 2; continue }
      if (c == "\"") break
      out = out c
      q++
    }
    return out
  }
  if (match(s, /[,}\]]/)) s = substr(s, 1, RSTART - 1)
  sub(/[ \t\r\n]+$/, "", s)
  return s
}

# Numeric value of "key", or dflt when absent/null.
function num(o, key, dflt,   v) {
  v = str(o, key)
  if (v == "" || v == "null") return dflt
  return v + 0
}

function hum(n) {
  if (n >= 1000000) return sprintf("%.1fM", n / 1000000)
  if (n >= 1000)    return sprintf("%.1fk", n / 1000)
  return sprintf("%d", int(n))
}

function base(p,   n, a) {
  sub(/[\/\\]+$/, "", p)
  n = split(p, a, /[\/\\]/)
  return n > 0 ? a[n] : ""
}

function colorUsed(p) { return p >= 80 ? RED : (p >= 50 ? YELLOW : GREEN) }
function colorRem(p)  { return p <= 20 ? RED : (p <= 50 ? YELLOW : GREEN) }

function fmtLimit(label, used) {
  if (used < 0) return label ": " GREY "n/a" RESET
  return label ": " colorUsed(used) used "%" RESET " / " GREEN "100%" RESET
}

# ---- main -------------------------------------------------------------------
{ doc = doc $0 }

END {
  ESC     = sprintf("%c", 27)
  RESET   = ESC "[0m";  BOLD   = ESC "[1m"
  GREEN   = ESC "[32m"; YELLOW = ESC "[33m"; RED   = ESC "[31m"
  CYAN    = ESC "[36m"; MAGENTA= ESC "[35m"; GREY  = ESC "[90m"

  oModel = obj(doc, "model")
  oCtx   = obj(doc, "context_window")
  oEff   = obj(doc, "effort")
  oWork  = obj(doc, "workspace")
  oRepo  = obj(doc, "repo")
  o5h    = obj(doc, "five_hour")
  o7d    = obj(doc, "seven_day")

  model = str(oModel, "display_name")
  if (model == "" || model == "null") model = "Unknown"

  usedTokens = num(oCtx, "total_input_tokens", 0)
  ctxSize    = num(oCtx, "context_window_size", 200000)
  if (ctxSize <= 0) ctxSize = 200000

  usedPct = num(oCtx, "used_percentage", -1)
  if (usedPct < 0) usedPct = (usedTokens / ctxSize) * 100
  remPct = num(oCtx, "remaining_percentage", -1)
  if (remPct < 0) remPct = 100 - usedPct
  remTokens = ctxSize - usedTokens

  effort = str(oEff, "level")
  if (effort == "" || effort == "null") effort = "n/a"

  repo = str(oRepo, "name")
  if (repo == "" || repo == "null") {
    cwd = str(oWork, "current_dir")
    if (cwd == "" || cwd == "null") cwd = str(doc, "cwd")
    repo = (cwd == "" || cwd == "null") ? "(no repo)" : base(cwd)
    if (repo == "") repo = "(no repo)"
  }

  fiveUsed  = num(o5h, "used_percentage", -1)
  sevenUsed = num(o7d, "used_percentage", -1)

  SEP = GREY " | " RESET
  cu = colorUsed(usedPct)
  cr = colorRem(remPct)

  line1 = BOLD CYAN model RESET
  line1 = line1 SEP hum(usedTokens) " / " hum(ctxSize)
  line1 = line1 SEP cu sprintf("%.2f", usedPct) "%" RESET " " GREY "used" RESET " " hum(usedTokens)
  line1 = line1 SEP cr sprintf("%.2f", remPct)  "%" RESET " " GREY "remain" RESET " " hum(remTokens)

  line2 = GREY "effort:" RESET " " MAGENTA effort RESET SEP GREY "repo:" RESET " " repo

  line3 = fmtLimit("Current Usage Limit", fiveUsed) SEP fmtLimit("Weekly Usage Limit", sevenUsed)

  printf "%s\n%s\n%s\n", line1, line2, line3
}
'
}

# Optional debug: dump the raw stdin payload for inspection.
# Enable with: touch ~/.claude/.statusline-debug
if [ -f "$HOME_DIR/.claude/.statusline-debug" ]; then
  tee "$HOME_DIR/.claude/.statusline-payload.json" 2>/dev/null | render
else
  render
fi
