# CLAUDE.md

Repo: `memoline` — user-scoped Claude Code status line installer.

## What's here

Two parallel implementations of the same thing, one per OS family. Four files, no build, no tests, no app code.

- `install.sh` / `statusline.sh` — macOS, Linux, BSD. POSIX `sh` + `awk`.
- `install.ps1` / `statusline.ps1` — Windows. Windows PowerShell 5.1.

Installers write the renderer to `~/.claude/`, wire it into `~/.claude/settings.json`, add `.gitignore` hygiene, and self-test. Renderers read session JSON on stdin and print a color-coded 3-line status.

## Rules

- **Zero dependencies is the whole point.** Only `sh`+`awk` (POSIX-mandated) and PowerShell 5.1 (ships with Windows 10/11) may be assumed. No node, no jq, no python, no Git Bash, no bashisms. Claude Code's native Windows installer bundles no user-facing `node` — that's why the Node version was deleted.
- Renderer output must stay identical between the two implementations. Change one, change the other.
- Targets `$HOME` / `$env:USERPROFILE` + `/.claude/`, never project-local. No hardcoded paths.
- `statusLine.command` must parse identically in cmd.exe, PowerShell, bash, zsh and fish. Consequence: **the interpreter is always a bare or unquoted-absolute leading token** — a leading *quoted* path is a syntax error in PowerShell (`"C:\x.exe" arg` is just a string literal). Only the script path argument gets quoted, and only when it contains spaces.
- Never depend on PATH for the interpreter. Unix uses absolute `/bin/sh`; Windows uses `powershell` (always on PATH there) with `-NoProfile -ExecutionPolicy Bypass -File`.
- Settings merge: only touch the `statusLine` key, preserve all others. Back up to `settings.json.bak` first. If existing JSON is malformed, abort before writing — never clobber. `install.sh` does this with a brace-depth, string-aware awk scanner; `install.ps1` uses `ConvertTo-Json -Depth 100` (the 5.1 default of 2 silently truncates nested `hooks`/`permissions`/`env`).
- Removing an existing `statusLine` key must fix up commas on both sides — if it was the last member, the *preceding* comma is the one that has to go, or the file ends `...,}`.
- PowerShell writes must be UTF-8 **without BOM** via `[System.IO.File]::WriteAllText`. `Out-File`/`Set-Content` on 5.1 emit UTF-16 or a BOM, either of which makes `settings.json` unreadable to Claude Code.
- Force invariant/C locale before formatting percentages (`LC_ALL=C` in sh, `InvariantCulture` in PowerShell). A comma-decimal locale like tr-TR otherwise renders `61,73%`.
- No API keys, no network calls, no telemetry. Scripts only read the stdin JSON Claude Code provides. Keep it that way.

## Workflow

- Syntax-check before commit: `sh -n install.sh && sh -n statusline.sh`. For PowerShell, parse-check with `[System.Management.Automation.Language.Parser]::ParseFile(...)`.
- Manual smoke test: `echo '<mock-json>' | sh statusline.sh` — expect exactly 3 lines with ANSI codes. Verify against `{}`, malformed input, and a payload missing `rate_limits`.
- Installer smoke test: run with `HOME` pointed at a scratch dir. Verify other `settings.json` keys survive (put `hooks`, nested objects, and a string containing `}` in the fixture), verify the `statusLine`-is-last-key case still yields valid JSON, verify a malformed file aborts untouched, and verify the overwrite prompt path.
- Commits: conventional format (`feat:`, `fix:`, etc), no AI attribution trailer (disabled globally).
