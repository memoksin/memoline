#!/usr/bin/env node
//
// install_statusline.js — deploy a custom, color-coded, three-line Claude Code
// status line at the USER level (~/.claude/), so it works in every project on
// every machine and every OS (macOS, Linux, Windows) where you run this script.
//
// What it does:
//   1. Verifies Node.js is available (it is, since this is running).
//   2. Overwrite protection: if a status line is already configured, prompts
//      "Configuration already exists. Do you want to overwrite it? (y/n)".
//   3. Writes ~/.claude/statusline.js (the renderer; reads session JSON on stdin).
//   4. Merges a `statusLine` entry into ~/.claude/settings.json (without clobbering
//      any other settings).
//   5. If run inside a git repo, adds .env and .claude/settings.local.json to
//      .gitignore (defensive hygiene).
//
// IMPORTANT — no API keys are used or needed.
//   Claude Code pipes every metric this status line shows (model, context tokens,
//   effort, repo name, 5-hour & weekly rate-limit usage) directly to the script on
//   stdin. There is NO public API/endpoint for these numbers, so there is nothing
//   to authenticate against and no secret to store. See:
//   https://docs.claude.com/en/docs/claude-code/statusline
//
// Cross-platform: pure Node.js + fs, no shell-specific syntax, no external deps
// (no jq required). Works the same on macOS, Linux, and Windows (cmd/PowerShell).
//
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const readline = require('readline');
const { execFileSync } = require('child_process');

const CLAUDE_DIR = path.join(os.homedir(), '.claude');
const STATUS_SCRIPT = path.join(CLAUDE_DIR, 'statusline.js');
const SETTINGS = path.join(CLAUDE_DIR, 'settings.json');
const RENDERER_SRC = path.join(__dirname, 'statusline.js');

function log(msg) {
  process.stdout.write(msg + '\n');
}

function logErr(msg) {
  process.stderr.write(msg + '\n');
}

function askYesNo(question) {
  return new Promise((resolve) => {
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
    rl.question(question, (answer) => {
      rl.close();
      resolve(/^(y|yes)$/i.test(answer.trim()));
    });
  });
}

function nodeCommand(scriptPath) {
  // On Windows, Claude Code's statusLine command runs via shell — quote the
  // path defensively in case it contains spaces (e.g. "C:\Users\Jane Doe\...").
  const quoted = scriptPath.includes(' ') ? `"${scriptPath}"` : scriptPath;
  return `node ${quoted}`;
}

async function main() {
  log('▶ Installing custom status line (user-scoped)');
  log(`    into : ${CLAUDE_DIR}`);

  fs.mkdirSync(CLAUDE_DIR, { recursive: true });

  // --- Overwrite protection ---
  let configExists = fs.existsSync(STATUS_SCRIPT);
  if (fs.existsSync(SETTINGS)) {
    try {
      const settings = JSON.parse(fs.readFileSync(SETTINGS, 'utf8'));
      if (settings && settings.statusLine) configExists = true;
    } catch (e) {
      // malformed settings.json — treat as no existing statusLine config
    }
  }

  if (configExists) {
    const proceed = await askYesNo('Configuration already exists. Do you want to overwrite it? (y/n) ');
    if (!proceed) {
      log('✗ Aborted. No changes were made.');
      process.exit(0);
    }
    log('  → overwriting existing configuration…');
  }

  // --- Write the status line renderer ---
  if (!fs.existsSync(RENDERER_SRC)) {
    logErr(`✗ Error: renderer source not found at ${RENDERER_SRC}`);
    process.exit(1);
  }
  fs.copyFileSync(RENDERER_SRC, STATUS_SCRIPT);
  try {
    fs.chmodSync(STATUS_SCRIPT, 0o755);
  } catch (e) {
    // chmod is a no-op / may fail harmlessly on Windows; execution goes through `node`
  }
  log(`  ✓ wrote ${STATUS_SCRIPT}`);

  // --- Merge statusLine into settings.json (preserve any other settings) ---
  let settings = {};
  if (fs.existsSync(SETTINGS)) {
    try {
      settings = JSON.parse(fs.readFileSync(SETTINGS, 'utf8'));
    } catch (e) {
      logErr(`✗ Error: ${SETTINGS} contains invalid JSON. Fix or remove it and re-run.`);
      process.exit(1);
    }
  }
  settings.statusLine = {
    type: 'command',
    command: nodeCommand(STATUS_SCRIPT),
    padding: 0,
  };
  fs.writeFileSync(SETTINGS, JSON.stringify(settings, null, 2) + '\n');
  log(`  ✓ wired statusLine → ${SETTINGS}`);

  // --- .gitignore hygiene (only when run inside a git repo) ---
  let repoRoot = null;
  try {
    repoRoot = execFileSync('git', ['rev-parse', '--show-toplevel'], { encoding: 'utf8' }).trim();
  } catch (e) {
    repoRoot = null; // not inside a git repo, or git not installed
  }

  if (repoRoot) {
    const gitignorePath = path.join(repoRoot, '.gitignore');
    let existing = '';
    if (fs.existsSync(gitignorePath)) {
      existing = fs.readFileSync(gitignorePath, 'utf8');
    }
    const lines = existing.split(/\r?\n/);
    const toAdd = ['.env', '.claude/settings.local.json'].filter((p) => !lines.includes(p));
    if (toAdd.length > 0) {
      const sep = existing.length > 0 && !existing.endsWith('\n') ? '\n' : '';
      fs.writeFileSync(gitignorePath, existing + sep + toAdd.join('\n') + '\n');
    }
    log('  ✓ ensured .env and .claude/settings.local.json are in .gitignore');
  }

  log('');
  log('✓ Done. Restart Claude Code to see the status line in every project.');
  log(`  Preview now: echo '<session-json>' | node "${STATUS_SCRIPT}"`);
}

main().catch((e) => {
  logErr(`✗ Error: ${e.message}`);
  process.exit(1);
});
