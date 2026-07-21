# CLAUDE.md

Repo: `memoline` — user-scoped Claude Code status line installer.

## What's here

- `install_statusline.js` — Node.js installer. Writes `statusline.js` to `~/.claude/statusline.js`, wires it into `~/.claude/settings.json`, adds `.gitignore` hygiene.
- `statusline.js` — renderer. Reads session JSON on stdin, prints color-coded 3-line status.
- Pure Node, no deps (no jq, no shell-specific syntax). Cross-platform by design: same script runs on macOS, Linux, Windows.
- No app code, no build, no tests. Two-script repo.

## Rules

- Targets `$HOME/.claude/` (via `os.homedir()`), not project-local. Any edit must keep it portable — no hardcoded paths, no POSIX-only assumptions (no `chmod`-dependent logic, no shell heredocs).
- Windows has no `jq`/bash/zsh guaranteed — that's why this is Node, not shell. Don't reintroduce a shell-only dependency.
- `statusLine.command` in settings.json is literally `node <path>`. Path gets quoted if it contains spaces (Windows `C:\Users\Jane Doe\...` case).
- Settings merge: parse existing `settings.json`, only touch the `statusLine` key, rewrite whole file. If existing JSON is malformed, abort before writing — never clobber user's other settings.
- No API keys, no network calls, no telemetry. Script only reads stdin JSON Claude Code provides. Keep it that way.

## Workflow

- Syntax-check before commit: `node -c install_statusline.js && node -c statusline.js`.
- Manual smoke test: `echo '<mock-json>' | node statusline.js`, check 3-line output + color codes.
- Installer smoke test: run with `HOME` pointed at a scratch dir, verify `settings.json` + `statusline.js` written, verify overwrite-prompt path (y/n).
- Commits: conventional format (`feat:`, `fix:`, etc), no AI attribution trailer (disabled globally).
