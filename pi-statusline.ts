import path from "node:path";
import type { ExtensionAPI, ExtensionContext } from "@oh-my-pi/pi-coding-agent";
import { claudeComposerStyle, truncateToWidth } from "@oh-my-pi/pi-tui";

// OMP's Claude-shaped composer has an extra built-in status bar. Keep its
// prompt/rules, but let the widget below the editor own all three status rows.
const composer = {
	...claudeComposerStyle,
	id: "memoline",
	statusAttachment: "none" as const,
	bottomBar: "none" as const,
};

const ESC = "\x1b[";
const RESET = `${ESC}0m`;
const BOLD = `${ESC}1m`;
const GREEN = `${ESC}32m`;
const YELLOW = `${ESC}33m`;
const RED = `${ESC}31m`;
const CYAN = `${ESC}36m`;
const MAGENTA = `${ESC}35m`;
const GREY = `${ESC}90m`;
const SEP = `${GREY} | ${RESET}`;

interface UsageLimit {
	window?: { id?: string; durationMs?: number; resetsAt?: number };
	id?: string;
	scope?: { windowId?: string };
	label?: string;
	amount?: { usedFraction?: number; used?: number; limit?: number };
	status?: string;
}
interface UsageReport {
	provider: string;
	limits: UsageLimit[];
}

function human(n: number): string {
	if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`;
	if (n >= 1_000) return `${(n / 1_000).toFixed(1)}k`;
	return `${Math.trunc(n)}`;
}

function usedColor(p: number): string {
	return p >= 80 ? RED : p >= 50 ? YELLOW : GREEN;
}
function remainingColor(p: number): string {
	return p <= 20 ? RED : p <= 50 ? YELLOW : GREEN;
}
function duration(seconds: number): string {
	let sec = Math.max(0, seconds);
	const days = Math.floor(sec / 86400);
	sec -= days * 86400;
	const hours = Math.floor(sec / 3600);
	const minutes = Math.floor((sec - hours * 3600) / 60);
	return days ? `${days}d ${hours}h` : hours ? `${hours}h ${minutes}m` : `${minutes}m`;
}
function limitLine(label: string, limit: UsageLimit | undefined): string {
	const amount = limit?.amount;
	const used = amount?.usedFraction !== undefined
		? amount.usedFraction * 100
		: amount?.limit ? (amount.used ?? 0) / amount.limit * 100 : undefined;
	if (used === undefined || !Number.isFinite(used) || limit?.status === "error") {
		return `${label}: ${GREY}n/a${RESET}`;
	}
	let result = `${label}: ${usedColor(used)}${Number(used.toFixed(2))}%${RESET} / ${GREEN}100%${RESET}`;
	if (limit?.window?.resetsAt) {
		result += ` ${GREY}(resets ${duration((limit.window.resetsAt - Date.now()) / 1000)})${RESET}`;
	}
	return result;
}
function windowKind(limit: UsageLimit): "5h" | "7d" | undefined {
	const id = limit.scope?.windowId ?? limit.window?.id;
	if (id === "5h" || limit.window?.durationMs === 18_000_000) return "5h";
	if (id === "7d" || id === "weekly" || limit.window?.durationMs === 604_800_000) return "7d";
}
function modelGroup(modelId: string): string {
	if (/gemini/i.test(modelId)) return "gemini";
	if (/claude|sonnet|opus|haiku/i.test(modelId)) return "anthropic";
	if (/gpt|codex|o[134]-/i.test(modelId)) return "openai";
	return "";
}
function providerLimits(report: UsageReport | undefined, modelId: string): [UsageLimit | undefined, UsageLimit | undefined] {
	if (!report) return [undefined, undefined];
	const group = report.provider === "google-antigravity" ? modelGroup(modelId) : "";
	// Antigravity's Gemini pool differs from its shared Claude/GPT pool.
	const limits = report.limits.filter(limit => report.provider !== "google-antigravity" ||
		(group === "gemini" ? limit.label === "Gemini" :
			!!group && limit.label === "Claude & GPT (shared)" && limit.id?.includes(`:${group}:`)));
	// Keep one limit per window even when a provider reports several accounts.
	const unique = new Map<string, UsageLimit>();
	for (const limit of limits) {
		const kind = windowKind(limit);
		if (kind && !unique.has(kind)) unique.set(kind, limit);
	}
	return [unique.get("5h"), unique.get("7d")];
}

export default function memoline(pi: ExtensionAPI): void {
	pi.registerComposerShape({ label: "Memoline", description: "Claude composer with a three-line status", style: composer });

	pi.on("session_start", (_event, ctx: ExtensionContext) => {
		if (!ctx.hasUI || ctx.mode !== "tui") return;
		let report: UsageReport | undefined;
		let provider = "";
		let requested = "";
		let lastFetch = 0;
		let fetching = false;
		let branch = "";
		let tui: { requestRender(): void } | undefined;

		const refresh = async () => {
			const selected = ctx.model?.provider ?? "";
			if (selected !== provider) {
				provider = selected;
				report = undefined;
				lastFetch = 0;
				tui?.requestRender();
			}
			if (fetching || !provider || (provider === requested && Date.now() - lastFetch < 60_000)) return;
			fetching = true;
			requested = provider;
			lastFetch = Date.now();
			try {
				const result = await pi.exec("omp", ["usage", "--json", "--provider", requested], { timeout: 10_000 });
				if (result.code === 0 && requested === ctx.model?.provider) {
					const data = JSON.parse(result.stdout) as { reports?: UsageReport[] };
					report = data.reports?.find(item => item.provider === requested);
				}
			} catch { /* No authenticated quota or CLI unavailable: render n/a. */ }
			finally { fetching = false; tui?.requestRender(); }
		};

		ctx.ui.setWidget("memoline", (host) => {
			tui = host;
			return {
				render(width: number): string[] {
					const model = ctx.model;
					const usage = ctx.getContextUsage();
					const used = usage?.tokens ?? 0;
					const size = usage?.contextWindow ?? model?.contextWindow ?? 200_000;
					const usedPct = size > 0 ? usage?.percent ?? used / size * 100 : 0;
					const remPct = 100 - usedPct;
					const name = model?.name || model?.id || "Unknown";
					const repo = path.basename(ctx.cwd.replace(/[/\\]+$/, "")) || "(no repo)";
					const effort = pi.getThinkingLevel() || "n/a";
					const [five, seven] = provider === model?.provider ? providerLimits(report, model?.id ?? "") : [undefined, undefined];
					const lines = [
						`${BOLD}${CYAN}${name}${RESET}${SEP}${human(used)} / ${human(size)}${SEP}${usedColor(usedPct)}${usedPct.toFixed(2)}%${RESET} ${GREY}used${RESET} ${human(used)}${SEP}${remainingColor(remPct)}${remPct.toFixed(2)}%${RESET} ${GREY}remain${RESET} ${human(size - used)}`,
						`${GREY}effort:${RESET} ${MAGENTA}${effort}${RESET}${SEP}${GREY}repo:${RESET} ${repo}${branch ? ` ${GREY}(${RESET}${CYAN}${branch}${RESET}${GREY})${RESET}` : ""}`,
						`${limitLine("Current Usage Limit", five)}${SEP}${limitLine("Weekly Usage Limit", seven)}`,
					];
					return lines.map(line => truncateToWidth(line, width));
				},
				invalidate() {},
			};
		}, { placement: "belowEditor" });

		void pi.exec("git", ["-C", ctx.cwd, "branch", "--show-current"], { timeout: 2000 })
			.then(result => { branch = result.code === 0 ? result.stdout.trim() : ""; tui?.requestRender(); })
			.catch(() => {});
		void refresh();
		ctx.setInterval(() => { void refresh(); tui?.requestRender(); }, 5000);
	});
}
