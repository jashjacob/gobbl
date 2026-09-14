import type { GlobalBudget, InstallQuota } from "./durable";

/** Minimal shape of the Workers Rate Limiting binding. */
export interface RateLimiter {
  limit(options: { key: string }): Promise<{ success: boolean }>;
}

export interface Env {
  // Secrets
  OPENROUTER_API_KEY: string;
  TURNSTILE_SECRET: string;
  // Vars
  DEV_SKIP_TURNSTILE?: string;
  DAILY_ACTIONS?: string;
  DAILY_BACKGROUND?: string;
  DAILY_USD_CAP?: string;
  GLOBAL_DAILY_USD?: string;
  REGISTRATIONS_PER_PREFIX_PER_DAY?: string;
  MODEL?: string;
  FALLBACK_MODEL?: string;
  // Bindings
  DB: D1Database;
  REVOKED: KVNamespace;
  INSTALL_QUOTA: DurableObjectNamespace<InstallQuota>;
  GLOBAL_BUDGET: DurableObjectNamespace<GlobalBudget>;
  BURST_LIMITER: RateLimiter;
  REGISTER_LIMITER: RateLimiter;
}

export const OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions";
export const TURNSTILE_URL = "https://challenges.cloudflare.com/turnstile/v0/siteverify";
export const APP_REFERER = "https://gobbl.xeve.io";
export const APP_TITLE = "Gobbl";

/** Only these models may ever be called, whatever the env says. */
export const MODEL_ALLOWLIST = [
  "google/gemini-2.5-flash-lite",
  "openai/gpt-4.1-nano",
  "google/gemini-2.0-flash-lite-001",
  "openai/gpt-4o-mini",
] as const;
export const DEFAULT_MODEL = "google/gemini-2.5-flash-lite";
export const DEFAULT_FALLBACK_MODEL = "openai/gpt-4.1-nano";

/** Worst-case $/token among allowlisted models, used for the pre-call reservation. */
export const PRICE_IN_PER_TOKEN = 0.15 / 1_000_000;
export const PRICE_OUT_PER_TOKEN = 0.6 / 1_000_000;

export const MAX_TOKENS = { write: 800, edit: 1200, cleanup: 1200, chat: 500, brief: 400, extract: 900, digest: 600, plan: 200 } as const;
export const CHAT_MAX_MESSAGES = 12;
export const CHAT_MESSAGE_CHARS = 4_000;
export const DAY_CONTEXT_CHARS = 2_000;
export const MAX_INPUT_CHARS = 12_000;
export const MAX_BODY_BYTES = 64 * 1024;
export const NEARBY_TEXT_CHARS = 3_000;
export const SHORT_FIELD_CHARS = 200;
export const MEMORY_MAX_ITEMS = 16;
export const MEMORY_TOTAL_CHARS = 6_000;
export const BRIEF_TODOS_MAX = 10;
export const EXTRACT_MAX_ITEMS = 120;
export const EXTRACT_TEXT_CHARS = 6_000;
export const EXTRACT_KNOWN_MAX = 200;
export const DIGEST_MAX_SEGMENTS = 40;
export const DIGEST_TOTAL_CHARS = 8_000;
/** Background calls (extract, digest) pause once global spend reaches this share of GLOBAL_DAILY_USD. */
export const BACKGROUND_GLOBAL_SHARE = 0.8;
/** Non-streaming upstream calls give up after this long. */
export const JSON_CALL_TIMEOUT_MS = 30_000;

function num(v: string | undefined, dflt: number): number {
  const n = v === undefined ? NaN : Number(v);
  return Number.isFinite(n) && n >= 0 ? n : dflt;
}

export function limitsFrom(env: Partial<Env>) {
  return {
    dailyActions: Math.floor(num(env.DAILY_ACTIONS, 40)),
    dailyBackground: Math.floor(num(env.DAILY_BACKGROUND, 16)),
    dailyUsd: num(env.DAILY_USD_CAP, 0.05),
    globalDailyUsd: num(env.GLOBAL_DAILY_USD, 20),
    registrationsPerPrefixPerDay: Math.floor(num(env.REGISTRATIONS_PER_PREFIX_PER_DAY, 20)),
  };
}

function allowed(m: string | undefined): m is string {
  return !!m && (MODEL_ALLOWLIST as readonly string[]).includes(m);
}

/** Primary + fallback, both forced through the allowlist. */
export function modelsFrom(env: Partial<Env>): string[] {
  const primary = allowed(env.MODEL) ? env.MODEL : DEFAULT_MODEL;
  const fallback = allowed(env.FALLBACK_MODEL) ? env.FALLBACK_MODEL : DEFAULT_FALLBACK_MODEL;
  return primary === fallback ? [primary] : [primary, fallback];
}

/** Conservative cost estimate reserved before the upstream call. */
export function estimateCostUsd(inputChars: number, maxTokens: number): number {
  const promptTokens = Math.ceil(inputChars / 3) + 400; // + system prompt overhead
  return promptTokens * PRICE_IN_PER_TOKEN + maxTokens * PRICE_OUT_PER_TOKEN;
}
