# memoline

A custom, color-coded, two-line status line for [Claude Code](https://docs.claude.com/en/docs/claude-code/statusline), installed once at the user level so it works in every project on every machine you run it on.

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

## Works on every OS

The installer and renderer are plain Node.js — no `jq`, no shell scripting, no OS-specific branches. Since Claude Code itself requires Node.js, there's nothing extra to install. Tested on macOS, Linux, and Windows.

## Installation

```bash
node install_statusline.js
```

This will:
1. Ask before overwriting an existing status line configuration.
2. Write the renderer to `~/.claude/statusline.js`.
3. Merge a `statusLine` entry into `~/.claude/settings.json` (without touching your other settings).
4. If run inside a git repo, add `.env` and `.claude/settings.local.json` to `.gitignore`.

Restart Claude Code afterward to see it in action.

## Previewing without installing

You can test the renderer directly against a sample payload:

```bash
echo '<session-json>' | node statusline.js
```

On Windows PowerShell:

```powershell
'<session-json>' | node statusline.js
```

## Debugging

To inspect the raw JSON Claude Code sends to the status line:

```bash
touch ~/.claude/.statusline-debug
# next render writes payload to:
cat ~/.claude/.statusline-payload.json
```

## Uninstalling

Remove the `statusLine` key from `~/.claude/settings.json` and delete `~/.claude/statusline.js`.
