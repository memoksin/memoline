# memoline

A custom, color-coded, three-line status line for [Claude Code](https://docs.claude.com/en/docs/claude-code/statusline), installed once at the user level so it works in every project on every machine you run it on. No dependencies — not even Node.js.

## What it shows

**Line 1** — Model, tokens used/remaining, and color-coded usage:
```
Sonnet | 50.0k / 200.0k | 25.00% used 50.0k | 75.00% remain 150.0k
```

**Line 2** — Reasoning effort and current repo:
```
effort: high | repo: memoline
```

**Line 3** — 5-hour and weekly rate-limit usage:
```
Current Usage Limit: 30% / 100% | Weekly Usage Limit: 10% / 100%
```

Colors follow simple thresholds:
- **Used %** (higher = worse): green `<50%`, yellow `50–80%`, red `≥80%`
- **Remaining %** (higher = better): green `>50%`, yellow `20–50%`, red `≤20%`

## Why no API key is needed

Claude Code pipes every metric shown here (model, context tokens, effort, repo name, rate-limit usage) directly into the script via stdin. There's no public API for these numbers to call, so there's nothing to authenticate against and nothing to configure.

## Zero dependencies

Nothing to install first — not even Node.js. Every OS already ships a runtime that can do the job, so there are two implementations that use only what's guaranteed present:

| Platform | Renderer | Needs | Ships with the OS |
|---|---|---|---|
| macOS, Linux, BSD | `statusline.sh` | POSIX `sh` + `awk` | Yes, both POSIX-mandated |
| Windows 10/11 | `statusline.ps1` | Windows PowerShell 5.1 | Yes, `ConvertFrom-Json` is built in |

No `jq`, no Node.js, no Python, no Git Bash. This matters because Claude Code's native Windows installer bundles no user-facing `node` — a Node-based status line silently renders blank there.

**Your shell doesn't matter.** bash, zsh, fish, cmd.exe and PowerShell all merely *invoke* the renderer, so there's nothing to pick — the installer detects the OS and wires an absolute interpreter path that parses identically in all of them.

## Installation

**macOS / Linux / BSD:**
```sh
sh install.sh
```

**Windows:**
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

Either one will:
1. Ask before overwriting an existing status line configuration.
2. Write the renderer into `~/.claude/`.
3. Merge a `statusLine` entry into `~/.claude/settings.json`, preserving every other key (a `.bak` is written first, and an unparseable file aborts the install rather than being clobbered).
4. If run inside a git repo, add `.env` and `.claude/settings.local.json` to `.gitignore`.
5. **Self-test the wired command through a shell** and fail loudly if it doesn't render three lines — a broken status line is otherwise completely silent.

Restart Claude Code afterward to see it in action.

## Previewing without installing

```sh
echo '<session-json>' | sh statusline.sh
```

On Windows PowerShell:

```powershell
'<session-json>' | powershell -NoProfile -File .\statusline.ps1
```

## Debugging

To inspect the raw JSON Claude Code sends to the status line:

```sh
touch ~/.claude/.statusline-debug
# next render writes payload to:
cat ~/.claude/.statusline-payload.json
```

On Windows, create the flag with `New-Item ~/.claude/.statusline-debug`.

If the status line is blank, re-run the installer and read its `self-test:` line — it runs the exact command Claude Code will run and prints the real error.

## Uninstalling

Remove the `statusLine` key from `~/.claude/settings.json` and delete `~/.claude/statusline.sh` (or `statusline.ps1`).
