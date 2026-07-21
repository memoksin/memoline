#!/usr/bin/env zsh
#
# install_statusline.sh — deploy a custom, color-coded, two-line Claude Code
# status line at the USER level (~/.claude/), so it works in every project on
# every machine where you run this script.
#
# What it does:
#   1. Verifies that `jq` is available.
#   2. Overwrite protection: if a status line is already configured, prompts
#      "Configuration already exists. Do you want to overwrite it? (y/n)".
#   3. Writes ~/.claude/statusline.sh  (the renderer; reads session JSON on stdin).
#   4. Merges a `statusLine` entry into ~/.claude/settings.json (without clobbering
#      any other settings).
#   5. If run inside a git repo, adds .env and .claude/settings.local.json to
#      .gitignore (defensive hygiene).
#
# IMPORTANT — no API keys are used or needed.
#   Claude Code pipes every metric this status line shows (model, context tokens,
#   effort, repo name, 5-hour & weekly rate-limit usage) directly to the script on
#   stdin. There is NO public API/endpoint for these numbers, so there is nothing
#   to authenticate against and no secret to store. See:
#   https://docs.claude.com/en/docs/claude-code/statusline
#
set -euo pipefail

# ----------------------------------------------------------------------------
# 1. Resolve user-level Claude config directory (portable, device-agnostic)
# ----------------------------------------------------------------------------
CLAUDE_DIR="$HOME/.claude"
STATUS_SCRIPT="$CLAUDE_DIR/statusline.sh"
SETTINGS="$CLAUDE_DIR/settings.json"

print "▶ Installing custom status line (user-scoped)"
print "    into : $CLAUDE_DIR"

# ----------------------------------------------------------------------------
# 2. Dependency check — jq is used by both this installer and the renderer
# ----------------------------------------------------------------------------
mkdir -p "$CLAUDE_DIR"

if ! command -v jq >/dev/null 2>&1; then
  print -u2 "✗ Error: 'jq' is required but not installed."
  print -u2 "    macOS : brew install jq"
  print -u2 "    Debian: sudo apt-get install -y jq"
  exit 1
fi

# ----------------------------------------------------------------------------
# 3. Overwrite protection
# ----------------------------------------------------------------------------
config_exists=0
[[ -f "$STATUS_SCRIPT" ]] && config_exists=1
if [[ -f "$SETTINGS" ]] && jq -e '.statusLine' "$SETTINGS" >/dev/null 2>&1; then
  config_exists=1
fi

if (( config_exists )); then
  printf 'Configuration already exists. Do you want to overwrite it? (y/n) '
  read -r reply
  case "$reply" in
    y|Y|yes|YES) print "  → overwriting existing configuration…" ;;
    *)           print "✗ Aborted. No changes were made."; exit 0 ;;
  esac
fi

# ----------------------------------------------------------------------------
# 4. Write the status line renderer
#    The heredoc delimiter is single-quoted ('RENDERER_EOF') so NOTHING inside
#    is expanded at install time — the $variables and `command`s below are
#    written verbatim and only evaluated when Claude Code runs the script.
# ----------------------------------------------------------------------------
cat > "$STATUS_SCRIPT" <<'RENDERER_EOF'
#!/usr/bin/env bash
#
# Claude Code custom two-line status line.
# Reads the session JSON on stdin and prints a color-coded status.
# Field reference: https://docs.claude.com/en/docs/claude-code/statusline
#
# Line 1: Model | Used/Remaining tokens | Used%(color) used UsedTok | Remaining%(color) remain RemTok
# Line 2: effort: Effort | repo: Repo
# Line 3: Current Usage Limit: Used%/Remaining%(color) | Weekly Usage Limit: ...
#
# Color coding:
#   "used"      semantics (higher = worse):  green < 50%, yellow 50–80%, red ≥ 80%
#   "remaining" semantics (higher = better): green > 50%, yellow 20–50%, red ≤ 20%
#
set -uo pipefail

input=$(cat)

# --- Optional debug: dump the raw stdin payload for inspection ---
# Enable with:  touch ~/.claude/.statusline-debug
# Then read:    cat ~/.claude/.statusline-payload.json
if [[ -f "$HOME/.claude/.statusline-debug" ]]; then
  printf '%s' "$input" > "$HOME/.claude/.statusline-payload.json"
fi

# --- ANSI palette ---
RESET=$'\033[0m'; BOLD=$'\033[1m'
GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'
CYAN=$'\033[36m'; MAGENTA=$'\033[35m'; GREY=$'\033[90m'

# --- jq is required ---
if ! command -v jq >/dev/null 2>&1; then
  printf '%s\n' "statusline: jq not found — install jq and re-run install_statusline.sh"
  exit 0
fi

# --- Extract fields, separated by Unit Separator (0x1F) ---
# NOTE: we deliberately do NOT use a tab here. Tab is an IFS *whitespace* char,
# so `read` would collapse consecutive tabs and drop empty fields (e.g. a blank
# repo name), shifting every later field. 0x1F is non-whitespace, so empty
# fields are preserved and the field-to-variable mapping stays aligned.
US=$'\x1f'
IFS="$US" read -r model used_tokens ctx_size used_pct rem_pct effort repo cwd five_used seven_used <<JSON
$(printf '%s' "$input" | jq -j '
  [
    (.model.display_name                       // "Unknown"),
    (.context_window.total_input_tokens        // 0),
    (.context_window.context_window_size       // 200000),
    (.context_window.used_percentage           // null),
    (.context_window.remaining_percentage      // null),
    (.effort.level                             // "n/a"),
    (.workspace.repo.name                      // ""),
    (.workspace.current_dir                    // .cwd // ""),
    (.rate_limits.five_hour.used_percentage    // null),
    (.rate_limits.seven_day.used_percentage    // null)
  ] | map(if . == null then "null" else tostring end) | join("")
')
JSON

# --- Repo name fallback (no origin remote / outside a repo) ---
if [[ -z "$repo" || "$repo" == "null" ]]; then
  if [[ -n "$cwd" && "$cwd" != "null" ]]; then repo=$(basename "$cwd"); else repo="(no repo)"; fi
fi

# --- Derive context percentages if Claude Code didn't pre-compute them yet ---
if [[ "$used_pct" == "null" ]]; then
  used_pct=$(awk -v u="$used_tokens" -v s="$ctx_size" 'BEGIN{ if (s+0>0) printf "%.2f",(u/s)*100; else printf "0" }')
fi
if [[ "$rem_pct" == "null" ]]; then
  rem_pct=$(awk -v p="$used_pct" 'BEGIN{ printf "%.2f", 100-p }')
fi
rem_tokens=$(( ctx_size - used_tokens ))

# --- Helpers ---
hum() { awk -v n="$1" 'BEGIN{
  if (n+0>=1000000) printf "%.1fM", n/1000000;
  else if (n+0>=1000) printf "%.1fk", n/1000;
  else printf "%d", n;
}'; }

color_used() {  # higher percentage = worse
  awk -v p="$1" -v g="$GREEN" -v y="$YELLOW" -v r="$RED" 'BEGIN{
    if (p+0>=80) printf "%s",r; else if (p+0>=50) printf "%s",y; else printf "%s",g }'
}
color_rem() {   # higher percentage = better
  awk -v p="$1" -v g="$GREEN" -v y="$YELLOW" -v r="$RED" 'BEGIN{
    if (p+0<=20) printf "%s",r; else if (p+0<=50) printf "%s",y; else printf "%s",g }'
}

SEP="${GREY} | ${RESET}"

# --- Line 1 ---
cu=$(color_used "$used_pct")
cr=$(color_rem  "$rem_pct")
line1="${BOLD}${CYAN}${model}${RESET}"
line1+="${SEP}$(hum "$used_tokens") / $(hum "$ctx_size")"
line1+="${SEP}${cu}${used_pct}%${RESET} ${GREY}used${RESET} $(hum "$used_tokens")"
line1+="${SEP}${cr}${rem_pct}%${RESET} ${GREY}remain${RESET} $(hum "$rem_tokens")"

# --- Line 2: effort, repo ---
line2="${GREY}effort:${RESET} ${MAGENTA}${effort}${RESET}"
line2+="${SEP}${GREY}repo:${RESET} ${repo}"

# --- Line 3: rate limits ---
fmt_limit() {  # $1 = label, $2 = used_percentage (or "null" when absent)
  local label="$1" u="$2"
  if [[ "$u" == "null" ]]; then
    printf '%s: %sn/a%s' "$label" "$GREY" "$RESET"
    return
  fi
  local cu
  cu=$(color_used "$u")
  printf '%s: %s%s%%%s / %s100%%%s' "$label" "$cu" "$u" "$RESET" "$GREEN" "$RESET"
}

line3="$(fmt_limit "Current Usage Limit" "$five_used")"
line3+="${SEP}$(fmt_limit "Weekly Usage Limit" "$seven_used")"

printf '%s\n%s\n%s\n' "$line1" "$line2" "$line3"
RENDERER_EOF

chmod +x "$STATUS_SCRIPT"
print "  ✓ wrote $STATUS_SCRIPT"

# ----------------------------------------------------------------------------
# 5. Merge statusLine into .claude/settings.json (preserve any other settings)
# ----------------------------------------------------------------------------
tmp=$(mktemp)
if [[ -f "$SETTINGS" ]]; then
  jq --arg cmd "$STATUS_SCRIPT" \
     '.statusLine = {type:"command", command:$cmd, padding:0}' \
     "$SETTINGS" > "$tmp"
else
  jq -n --arg cmd "$STATUS_SCRIPT" \
     '{statusLine:{type:"command", command:$cmd, padding:0}}' > "$tmp"
fi
mv "$tmp" "$SETTINGS"
print "  ✓ wired statusLine → $SETTINGS"

# ----------------------------------------------------------------------------
# 6. .gitignore hygiene (only when run inside a git repo)
# ----------------------------------------------------------------------------
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  GITIGNORE="$(git rev-parse --show-toplevel)/.gitignore"
  ensure_ignore() {
    local pattern="$1"
    [[ -f "$GITIGNORE" ]] || : > "$GITIGNORE"
    grep -qxF -- "$pattern" "$GITIGNORE" 2>/dev/null || print -- "$pattern" >> "$GITIGNORE"
  }
  ensure_ignore ".env"
  ensure_ignore ".claude/settings.local.json"
  print "  ✓ ensured .env and .claude/settings.local.json are in .gitignore"
fi

print ""
print "✓ Done. Restart Claude Code to see the status line in every project."
print "  Preview now: echo '<session-json>' | \"$STATUS_SCRIPT\""
