#!/usr/bin/env node
//
// Claude Code custom three-line status line (cross-platform: macOS/Linux/Windows).
// Reads the session JSON on stdin and prints a color-coded status.
// Field reference: https://docs.claude.com/en/docs/claude-code/statusline
//
// Line 1: Model | Used/Remaining tokens | Used%(color) used UsedTok | Remaining%(color) remain RemTok
// Line 2: effort: Effort | repo: Repo
// Line 3: Current Usage Limit: Used%/Remaining%(color) | Weekly Usage Limit: ...
//
// Color coding:
//   "used"      semantics (higher = worse):  green < 50%, yellow 50-80%, red >= 80%
//   "remaining" semantics (higher = better): green > 50%, yellow 20-50%, red <= 20%
//
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');

const RESET = '\x1b[0m';
const BOLD = '\x1b[1m';
const GREEN = '\x1b[32m';
const YELLOW = '\x1b[33m';
const RED = '\x1b[31m';
const CYAN = '\x1b[36m';
const MAGENTA = '\x1b[35m';
const GREY = '\x1b[90m';

function readStdin() {
  try {
    return fs.readFileSync(0, 'utf8');
  } catch (e) {
    return '';
  }
}

function hum(n) {
  n = Number(n) || 0;
  if (n >= 1000000) return (n / 1000000).toFixed(1) + 'M';
  if (n >= 1000) return (n / 1000).toFixed(1) + 'k';
  return String(Math.trunc(n));
}

function colorUsed(p) {
  if (p >= 80) return RED;
  if (p >= 50) return YELLOW;
  return GREEN;
}

function colorRem(p) {
  if (p <= 20) return RED;
  if (p <= 50) return YELLOW;
  return GREEN;
}

function fmtLimit(label, used) {
  if (used === null || used === undefined) {
    return `${label}: ${GREY}n/a${RESET}`;
  }
  const c = colorUsed(used);
  return `${label}: ${c}${used}%${RESET} / ${GREEN}100%${RESET}`;
}

function main() {
  const raw = readStdin();

  // Optional debug: dump raw stdin payload for inspection.
  // Enable with: touch ~/.claude/.statusline-debug
  const home = os.homedir();
  const debugFlag = path.join(home, '.claude', '.statusline-debug');
  if (fs.existsSync(debugFlag)) {
    try {
      fs.writeFileSync(path.join(home, '.claude', '.statusline-payload.json'), raw);
    } catch (e) {
      // best-effort debug dump; ignore failures
    }
  }

  let data = {};
  try {
    data = JSON.parse(raw || '{}');
  } catch (e) {
    data = {};
  }

  const model = data?.model?.display_name ?? 'Unknown';
  const usedTokens = Number(data?.context_window?.total_input_tokens ?? 0);
  const ctxSize = Number(data?.context_window?.context_window_size ?? 200000);
  let usedPct = data?.context_window?.used_percentage;
  let remPct = data?.context_window?.remaining_percentage;
  const effort = data?.effort?.level ?? 'n/a';
  let repo = data?.workspace?.repo?.name ?? '';
  const cwd = data?.workspace?.current_dir ?? data?.cwd ?? '';
  const fiveUsed = data?.rate_limits?.five_hour?.used_percentage ?? null;
  const sevenUsed = data?.rate_limits?.seven_day?.used_percentage ?? null;

  if (!repo) {
    repo = cwd ? path.basename(cwd) : '(no repo)';
  }

  if (usedPct === null || usedPct === undefined) {
    usedPct = ctxSize > 0 ? (usedTokens / ctxSize) * 100 : 0;
  }
  if (remPct === null || remPct === undefined) {
    remPct = 100 - usedPct;
  }
  const remTokens = ctxSize - usedTokens;

  const usedPctStr = usedPct.toFixed(2);
  const remPctStr = remPct.toFixed(2);

  const SEP = `${GREY} | ${RESET}`;

  const cu = colorUsed(usedPct);
  const cr = colorRem(remPct);

  let line1 = `${BOLD}${CYAN}${model}${RESET}`;
  line1 += `${SEP}${hum(usedTokens)} / ${hum(ctxSize)}`;
  line1 += `${SEP}${cu}${usedPctStr}%${RESET} ${GREY}used${RESET} ${hum(usedTokens)}`;
  line1 += `${SEP}${cr}${remPctStr}%${RESET} ${GREY}remain${RESET} ${hum(remTokens)}`;

  let line2 = `${GREY}effort:${RESET} ${MAGENTA}${effort}${RESET}`;
  line2 += `${SEP}${GREY}repo:${RESET} ${repo}`;

  let line3 = fmtLimit('Current Usage Limit', fiveUsed);
  line3 += `${SEP}${fmtLimit('Weekly Usage Limit', sevenUsed)}`;

  process.stdout.write(`${line1}\n${line2}\n${line3}\n`);
}

main();
