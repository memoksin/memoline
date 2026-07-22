#!/bin/sh
#
# install.sh — deploy the custom Claude Code status line at the USER level
# (~/.claude/), for macOS, Linux and BSD.
#
# Zero dependencies: POSIX `sh` + `awk` only. No node, no jq, no python, no
# bashisms. Windows users run install.ps1 instead.
#
# What it does:
#   1. Writes ~/.claude/statusline.sh (the renderer; reads session JSON on stdin).
#   2. Merges a `statusLine` entry into ~/.claude/settings.json, preserving every
#      other key. Backs the file up first; aborts rather than write invalid JSON.
#   3. Self-tests the wired command through a shell before declaring success.
#   4. If run inside a git repo, adds .env and .claude/settings.local.json to
#      .gitignore (defensive hygiene).
#
# IMPORTANT — no API keys are used or needed. Claude Code pipes every metric
# this status line shows directly to the script on stdin. See:
# https://docs.claude.com/en/docs/claude-code/statusline

set -eu

LC_ALL=C
export LC_ALL

SRC_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
CLAUDE_DIR="${HOME:?HOME is not set}/.claude"
STATUS_SCRIPT="$CLAUDE_DIR/statusline.sh"
SETTINGS="$CLAUDE_DIR/settings.json"
RENDERER_SRC="$SRC_DIR/statusline.sh"

die() { printf '%s\n' "$*" >&2; exit 1; }

case "$(uname -s 2>/dev/null || echo unknown)" in
  MINGW*|MSYS*|CYGWIN*)
    die "✗ This is a Windows shell. Claude Code spawns the status line via cmd.exe,
  where /bin/sh does not exist. Run install.ps1 in PowerShell instead."
    ;;
esac

printf '▶ Installing custom status line (user-scoped)\n'
printf '    into : %s\n' "$CLAUDE_DIR"

[ -f "$RENDERER_SRC" ] || die "✗ Error: renderer source not found at $RENDERER_SRC"
mkdir -p "$CLAUDE_DIR"

# --- Overwrite protection ---
config_exists=no
[ -f "$STATUS_SCRIPT" ] && config_exists=yes
if [ -f "$SETTINGS" ] && grep -q '"statusLine"' "$SETTINGS" 2>/dev/null; then
  config_exists=yes
fi

if [ "$config_exists" = yes ]; then
  # Non-interactive stdin (piped, CI, agent invocation) never sends an answer.
  # This installer only runs when explicitly invoked, so treat that as consent
  # rather than blocking forever on a read that will not return.
  if [ -t 0 ]; then
    printf 'Configuration already exists. Do you want to overwrite it? (y/n) '
    read -r answer || answer=n
  else
    answer=y
    printf 'Configuration already exists. Do you want to overwrite it? (y/n) y (non-interactive stdin, auto-confirmed)\n'
  fi
  case "$answer" in
    y|Y|yes|YES) printf '  → overwriting existing configuration…\n' ;;
    *) printf '✗ Aborted. No changes were made.\n'; exit 0 ;;
  esac
fi

# --- Write the renderer ---
cp "$RENDERER_SRC" "$STATUS_SCRIPT"
chmod 755 "$STATUS_SCRIPT" 2>/dev/null || true
printf '  ✓ wrote %s\n' "$STATUS_SCRIPT"

# --- Build the command ---
# /bin/sh is an absolute POSIX-mandated path, so this string is valid whatever
# shell Claude Code spawns (sh, bash, zsh, fish) and needs nothing on PATH.
case "$STATUS_SCRIPT" in
  *\ *) COMMAND="/bin/sh \"$STATUS_SCRIPT\"" ;;
  *)    COMMAND="/bin/sh $STATUS_SCRIPT" ;;
esac

# --- Merge statusLine into settings.json, preserving every other key ---
merge_settings() {
  awk -v cmd="$1" '
    function esc(s,   i, c, o) {
      o = ""
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (c == "\\" || c == "\"") o = o "\\" c
        else o = o c
      }
      return o
    }
    function skipws(s, i,   c) {
      while (i <= length(s)) {
        c = substr(s, i, 1)
        if (c == " " || c == "\t" || c == "\n" || c == "\r") { i++; continue }
        break
      }
      return i
    }
    # Index just past the string literal starting at i (where s[i] is a quote).
    function scanstr(s, i,   n, c) {
      n = length(s); i++
      while (i <= n) {
        c = substr(s, i, 1)
        if (c == "\\") { i += 2; continue }
        if (c == "\"") return i + 1
        i++
      }
      return 0
    }
    # Index just past the JSON value starting at i.
    function scanval(s, i,   n, c, depth) {
      n = length(s)
      i = skipws(s, i)
      if (i > n) return 0
      c = substr(s, i, 1)
      if (c == "\"") return scanstr(s, i)
      if (c == "{" || c == "[") {
        depth = 0
        while (i <= n) {
          c = substr(s, i, 1)
          if (c == "\"") { i = scanstr(s, i); if (i == 0) return 0; continue }
          if (c == "{" || c == "[") depth++
          else if (c == "}" || c == "]") { depth--; if (depth == 0) return i + 1 }
          i++
        }
        return 0
      }
      while (i <= n) {
        c = substr(s, i, 1)
        if (c == "," || c == "}" || c == "]" || c == " " || c == "\t" || c == "\n" || c == "\r") return i
        i++
      }
      return i
    }
    { doc = doc $0 "\n" }
    END {
      n = length(doc)
      i = skipws(doc, 1)
      if (substr(doc, i, 1) != "{") { print "settings.json is not a JSON object" > "/dev/stderr"; exit 1 }
      i++
      depth = 1
      cutstart = 0; cutend = 0
      while (i <= n && depth > 0) {
        c = substr(doc, i, 1)
        if (c == "\"") {
          keystart = i
          j = scanstr(doc, i)
          if (j == 0) { print "unterminated string" > "/dev/stderr"; exit 1 }
          k = skipws(doc, j)
          if (depth == 1 && substr(doc, k, 1) == ":") {
            key = substr(doc, keystart + 1, j - keystart - 2)
            v = scanval(doc, k + 1)
            if (v == 0) { print "malformed value for key " key > "/dev/stderr"; exit 1 }
            if (key == "statusLine") {
              # Absorb the indentation and the newline in front of the key, so
              # removing it does not leave a blank line behind.
              cutstart = keystart
              while (cutstart > 1 && (substr(doc, cutstart - 1, 1) == " " || substr(doc, cutstart - 1, 1) == "\t")) cutstart--
              if (cutstart > 1 && substr(doc, cutstart - 1, 1) == "\n") cutstart--
              if (cutstart > 1 && substr(doc, cutstart - 1, 1) == "\r") cutstart--
              m = skipws(doc, v)
              if (substr(doc, m, 1) == ",") {
                m++
              } else {
                # No comma follows, so statusLine was the last member: the comma
                # that separated it from the previous one must go instead, or
                # the object is left ending in "...,}".
                p = cutstart - 1
                while (p >= 1 && (substr(doc, p, 1) == " " || substr(doc, p, 1) == "\t" || substr(doc, p, 1) == "\n" || substr(doc, p, 1) == "\r")) p--
                if (p >= 1 && substr(doc, p, 1) == ",") cutstart = p
              }
              cutend = m
            }
            i = v
            continue
          }
          i = j
          continue
        }
        if (c == "{" || c == "[") depth++
        else if (c == "}" || c == "]") depth--
        i++
      }
      if (depth != 0) { print "unbalanced braces" > "/dev/stderr"; exit 1 }

      if (cutstart > 0) doc = substr(doc, 1, cutstart - 1) substr(doc, cutend)

      i = skipws(doc, 1)
      rest = substr(doc, i + 1)
      sep = (substr(rest, skipws(rest, 1), 1) == "}") ? "" : ","
      entry = "\n  \"statusLine\": {\n    \"type\": \"command\",\n    \"command\": \"" esc(cmd) "\",\n    \"padding\": 0\n  }" sep
      printf "%s%s%s", substr(doc, 1, i), entry, rest
    }
  '
}

if [ -f "$SETTINGS" ] && [ -s "$SETTINGS" ]; then
  cp "$SETTINGS" "$SETTINGS.bak"
  if ! merge_settings "$COMMAND" < "$SETTINGS" > "$SETTINGS.tmp"; then
    rm -f "$SETTINGS.tmp"
    die "✗ Error: $SETTINGS contains invalid JSON. Fix or remove it and re-run.
  Your file was left untouched (backup at $SETTINGS.bak)."
  fi
  mv "$SETTINGS.tmp" "$SETTINGS"
  printf '  ✓ wired statusLine → %s (backup: %s.bak)\n' "$SETTINGS" "$SETTINGS"
else
  printf '{\n  "statusLine": {\n    "type": "command",\n    "command": "%s",\n    "padding": 0\n  }\n}\n' \
    "$(printf '%s' "$COMMAND" | sed 's/\\/\\\\/g; s/"/\\"/g')" > "$SETTINGS"
  printf '  ✓ wired statusLine → %s\n' "$SETTINGS"
fi

# --- .gitignore hygiene (only when run inside a git repo) ---
if repo_root=$(git rev-parse --show-toplevel 2>/dev/null); then
  gitignore="$repo_root/.gitignore"
  [ -f "$gitignore" ] || : > "$gitignore"
  # Ensure a trailing newline before appending, so entries never merge onto one line.
  if [ -s "$gitignore" ] && [ "$(tail -c 1 "$gitignore" | wc -l | tr -d ' ')" = "0" ]; then
    printf '\n' >> "$gitignore"
  fi
  for entry in '.env' '.claude/settings.local.json'; do
    grep -qxF "$entry" "$gitignore" 2>/dev/null || printf '%s\n' "$entry" >> "$gitignore"
  done
  printf '  ✓ ensured .env and .claude/settings.local.json are in .gitignore\n'
fi

# --- Verify the wired command actually runs ---
printf '\n  → self-test: %s\n' "$COMMAND"
MOCK='{"model":{"display_name":"Test"},"context_window":{"total_input_tokens":1000,"context_window_size":200000},"workspace":{"current_dir":"'"$PWD"'"}}'
if ! out=$(printf '%s' "$MOCK" | eval "$COMMAND" 2>&1); then
  printf '✗ Self-test FAILED — Claude Code will show a blank status line.\n' >&2
  printf '    %s\n' "$out" >&2
  exit 1
fi
lines=$(printf '%s\n' "$out" | wc -l | tr -d ' ')
[ "$lines" = "3" ] || die "✗ Self-test FAILED: expected 3 lines, got $lines
$out"
printf '  ✓ self-test passed:\n'
printf '%s\n' "$out" | sed 's/^/      /'

printf '\n✓ Done. Restart Claude Code to see the status line in every project.\n'
