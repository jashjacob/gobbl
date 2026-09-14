import {
  BRIEF_TODOS_MAX,
  CHAT_MAX_MESSAGES,
  CHAT_MESSAGE_CHARS,
  DIGEST_MAX_SEGMENTS,
  DIGEST_TOTAL_CHARS,
  EXTRACT_KNOWN_MAX,
  EXTRACT_MAX_ITEMS,
  EXTRACT_TEXT_CHARS,
  MAX_INPUT_CHARS,
  MEMORY_MAX_ITEMS,
  MEMORY_TOTAL_CHARS,
  NEARBY_TEXT_CHARS,
  SHORT_FIELD_CHARS,
} from "./config";

export const WRITE_MODES = ["instruction", "rewrite", "draft", "answer"] as const;
export const CLEANUP_STYLES = ["light", "polish"] as const;
export const TONES = ["neutral", "friendly", "formal", "casual", "concise", "confident", "warm", "professional"] as const;
export const BRIEF_KINDS = ["morning", "evening"] as const;
export const CAPTURE_KINDS = ["text", "message", "mail"] as const;
export const DAY_PARTS = ["morning", "afternoon", "evening"] as const;

export interface AppContext {
  app: string;
  windowTitle: string;
  url?: string;
  nearbyText?: string;
}

export interface WriteRequest {
  mode: (typeof WRITE_MODES)[number];
  text: string;
  selection?: string;
  context: AppContext;
  tone?: (typeof TONES)[number];
  locale?: string;
}

export interface EditRequest {
  text: string;
  instruction: string;
  context: AppContext;
  locale?: string;
}

export interface CleanupRequest {
  text: string;
  style: (typeof CLEANUP_STYLES)[number];
  app?: string;
  bundleId?: string;
  locale?: string;
  accent?: string;
}

export interface DayContext {
  now?: string;
  timezone?: string;
  calendar: { title: string; start: string; end: string; location?: string }[];
  reminders: { text: string; due?: string }[];
  agents: { project: string; state: string }[];
  focus?: { running?: boolean; completedToday?: number };
}

/** Recalled snippets the app attaches to chat/brief, e.g. { source: "WhatsApp · Samar · Sat 6 PM", text: "…" }. */
export interface MemoryItem {
  source: string;
  text: string;
}

export interface ChatRequest {
  messages: { role: "user" | "assistant"; content: string }[];
  context: DayContext;
  memory: MemoryItem[];
  locale?: string;
}

export interface BriefRequest {
  kind: (typeof BRIEF_KINDS)[number];
  context: DayContext;
  memory: MemoryItem[];
  todos: { title: string; due?: string }[];
  yesterday?: string;
  locale?: string;
}

export interface CaptureItem {
  ref: string;
  app: string;
  window?: string;
  chat?: string;
  url_domain?: string;
  kind: (typeof CAPTURE_KINDS)[number];
  sender?: string;
  fromMe?: boolean;
  time?: string;
  text: string;
}

export interface ExtractRequest {
  batch: CaptureItem[];
  known: { people: string[]; projects: string[] };
  now: string;
  timezone?: string;
  locale?: string;
}

export interface DigestSegment {
  app: string;
  window?: string;
  chat?: string;
  url_domain?: string;
  minutes: number;
  summary: string;
}

export interface DigestRequest {
  day: string;
  parts: { part: (typeof DAY_PARTS)[number]; segments: DigestSegment[] }[];
  locale?: string;
}

export type Validated<T> = { ok: true; value: T; inputChars: number } | { ok: false; status: 400 | 413; error: string };

const LOCALE_RE = /^[A-Za-z]{2,3}(?:[-_][A-Za-z0-9]{2,8}){0,3}$/;

function isObj(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}
function optStr(v: unknown): v is string | undefined | null {
  return v === undefined || v === null || typeof v === "string";
}
/** Short metadata fields are truncated rather than rejected. */
function short(v: unknown, max = SHORT_FIELD_CHARS): string | undefined {
  return typeof v === "string" && v.trim().length ? v.slice(0, max) : undefined;
}
function locale(v: unknown): string | undefined | false {
  if (v === undefined || v === null || v === "") return undefined;
  return typeof v === "string" && LOCALE_RE.test(v) ? v : false;
}
const bad = (error: string) => ({ ok: false as const, status: 400 as const, error });
const tooLarge = { ok: false as const, status: 413 as const, error: "too_large" };

function appContext(c: unknown, withNearby: boolean): AppContext | false {
  if (c === undefined || c === null) return { app: "unknown", windowTitle: "" };
  if (!isObj(c)) return false;
  if (!optStr(c.app) || !optStr(c.windowTitle) || !optStr(c.url) || !optStr(c.nearbyText)) return false;
  const nearby = withNearby && typeof c.nearbyText === "string" ? c.nearbyText.slice(0, NEARBY_TEXT_CHARS) : "";
  return {
    app: short(c.app) ?? "unknown",
    windowTitle: short(c.windowTitle) ?? "",
    url: short(c.url, 500),
    nearbyText: nearby.trim() ? nearby : undefined,
  };
}

export function validateWrite(body: unknown): Validated<WriteRequest> {
  if (!isObj(body)) return bad("invalid_body");
  const { mode, text, selection, tone } = body;
  if (typeof mode !== "string" || !(WRITE_MODES as readonly string[]).includes(mode)) return bad("invalid_mode");
  if (!optStr(text)) return bad("invalid_text");
  if (!optStr(selection)) return bad("invalid_selection");
  const context = appContext(body.context, true);
  if (!context) return bad("invalid_context");
  if (tone !== undefined && tone !== null && !(TONES as readonly unknown[]).includes(tone)) return bad("invalid_tone");
  const loc = locale(body.locale);
  if (loc === false) return bad("invalid_locale");

  const t = text ?? "";
  const sel = typeof selection === "string" && selection.trim() ? selection : undefined;
  const hasInput =
    mode === "draft" ? !!(t.trim() || sel || context.nearbyText) : mode === "rewrite" ? !!(sel || t.trim()) : !!t.trim();
  if (!hasInput) return bad("empty_input");
  const inputChars = t.length + (sel?.length ?? 0) + (context.nearbyText?.length ?? 0);
  if (inputChars > MAX_INPUT_CHARS) return tooLarge;
  return {
    ok: true,
    value: { mode: mode as WriteRequest["mode"], text: t, selection: sel, context, tone: (tone ?? undefined) as WriteRequest["tone"], locale: loc },
    inputChars,
  };
}

export function validateEdit(body: unknown): Validated<EditRequest> {
  if (!isObj(body)) return bad("invalid_body");
  const { text, instruction } = body;
  if (typeof text !== "string" || !text.trim()) return bad(typeof text === "string" ? "empty_input" : "invalid_text");
  if (typeof instruction !== "string" || !instruction.trim()) return bad("invalid_instruction");
  const context = appContext(body.context, false);
  if (!context) return bad("invalid_context");
  const loc = locale(body.locale);
  if (loc === false) return bad("invalid_locale");
  const inputChars = text.length + instruction.length;
  if (inputChars > MAX_INPUT_CHARS) return tooLarge;
  return { ok: true, value: { text, instruction, context, locale: loc }, inputChars };
}

export function validateCleanup(body: unknown): Validated<CleanupRequest> {
  if (!isObj(body)) return bad("invalid_body");
  const text = body.text ?? body.transcript; // `transcript` accepted for older clients
  if (typeof text !== "string") return bad("invalid_text");
  const style = body.style ?? "polish";
  if (typeof style !== "string" || !(CLEANUP_STYLES as readonly string[]).includes(style)) return bad("invalid_style");
  if (!optStr(body.app) || !optStr(body.bundleId)) return bad("invalid_app");
  const loc = locale(body.locale);
  if (loc === false) return bad("invalid_locale");
  const acc = locale(body.accent);
  if (acc === false) return bad("invalid_accent");
  if (!text.trim()) return bad("empty_input");
  if (text.length > MAX_INPUT_CHARS) return tooLarge;
  return {
    ok: true,
    value: {
      text,
      style: style as CleanupRequest["style"],
      app: short(body.app),
      bundleId: short(body.bundleId, 120),
      locale: loc,
      accent: acc,
    },
    inputChars: text.length,
  };
}

// ---------------------------------------------------------------- chat / brief

const LIST_MAX = 20;
const FIELD = 160;

function list<T>(v: unknown, max: number, map: (o: Record<string, unknown>) => T | undefined): T[] {
  if (!Array.isArray(v)) return [];
  const out: T[] = [];
  for (const item of v) {
    if (out.length >= max) break;
    if (isObj(item)) {
      const m = map(item);
      if (m) out.push(m);
    }
  }
  return out;
}

/** Lenient: malformed parts are dropped, never rejected. Rendering caps the total size. */
export function parseDayContext(v: unknown): DayContext {
  const c = isObj(v) ? v : {};
  const focus = isObj(c.focus)
    ? {
        running: typeof c.focus.running === "boolean" ? c.focus.running : undefined,
        completedToday:
          typeof c.focus.completedToday === "number" && Number.isFinite(c.focus.completedToday)
            ? Math.max(0, Math.floor(c.focus.completedToday))
            : undefined,
      }
    : undefined;
  return {
    now: short(c.now, 40),
    timezone: short(c.timezone, 60),
    calendar: list(c.calendar, LIST_MAX, (o) => {
      const title = short(o.title, FIELD);
      return title ? { title, start: short(o.start, 40) ?? "", end: short(o.end, 40) ?? "", location: short(o.location, FIELD) } : undefined;
    }),
    reminders: list(c.reminders, LIST_MAX, (o) => {
      const text = short(o.text, FIELD);
      return text ? { text, due: short(o.due, 40) } : undefined;
    }),
    agents: list(c.agents, 10, (o) => {
      const project = short(o.project, 80);
      return project ? { project, state: short(o.state, 40) ?? "" } : undefined;
    }),
    focus,
  };
}

export function validateChat(body: unknown): Validated<ChatRequest> {
  if (!isObj(body)) return bad("invalid_body");
  if (!Array.isArray(body.messages) || body.messages.length === 0) return bad("invalid_messages");
  const msgs: ChatRequest["messages"] = [];
  for (const m of body.messages.slice(-CHAT_MAX_MESSAGES)) {
    if (!isObj(m) || (m.role !== "user" && m.role !== "assistant") || typeof m.content !== "string") return bad("invalid_messages");
    msgs.push({ role: m.role, content: m.content.slice(0, CHAT_MESSAGE_CHARS) });
  }
  if (msgs[msgs.length - 1].role !== "user" || !msgs[msgs.length - 1].content.trim()) return bad("invalid_messages");
  // Keep the total within the input cap by dropping the oldest turns.
  let total = msgs.reduce((n, m) => n + m.content.length, 0);
  while (total > MAX_INPUT_CHARS && msgs.length > 1) total -= msgs.shift()!.content.length;
  while (msgs.length && msgs[0].role !== "user") total -= msgs.shift()!.content.length;
  const loc = locale(body.locale);
  if (loc === false) return bad("invalid_locale");
  const ctx = isObj(body.context) ? body.context : {};
  const memory = parseMemory(ctx.memory);
  return {
    ok: true,
    value: { messages: msgs, context: parseDayContext(ctx), memory, locale: loc },
    inputChars: total + memoryChars(memory),
  };
}

export function validateBrief(body: unknown): Validated<BriefRequest> {
  if (!isObj(body)) return bad("invalid_body");
  if (typeof body.kind !== "string" || !(BRIEF_KINDS as readonly string[]).includes(body.kind)) return bad("invalid_kind");
  if (!optStr(body.yesterday)) return bad("invalid_yesterday");
  const loc = locale(body.locale);
  if (loc === false) return bad("invalid_locale");
  const ctx = isObj(body.context) ? body.context : {};
  const yesterday = short(body.yesterday ?? ctx.yesterday, 1000);
  const memory = parseMemory(ctx.memory);
  const todos = list(ctx.todos, BRIEF_TODOS_MAX, (o) => {
    const title = short(o.title, FIELD);
    return title ? { title, due: short(o.due, 40) } : undefined;
  });
  return {
    ok: true,
    value: { kind: body.kind as BriefRequest["kind"], context: parseDayContext(ctx), memory, todos, yesterday, locale: loc },
    inputChars: 2000 + (yesterday?.length ?? 0) + memoryChars(memory) + todos.reduce((n, t) => n + t.title.length + 20, 0),
  };
}

// ---------------------------------------------------------------- memory

const MEMORY_SOURCE_CHARS = 80;
const MEMORY_TEXT_CHARS = 600;
/** A memory cut shorter than this by the total cap is dropped rather than kept as a stub. */
const MEMORY_MIN_TAIL = 40;

export function memoryChars(m: MemoryItem[]): number {
  return m.reduce((n, i) => n + i.source.length + i.text.length, 0);
}

/**
 * Lenient like parseDayContext: malformed entries are dropped, fields truncated, at most
 * MEMORY_MAX_ITEMS kept, and the list is cut once source + text reach MEMORY_TOTAL_CHARS
 * (the item that crosses the line is truncated to fit).
 */
export function parseMemory(v: unknown): MemoryItem[] {
  const items = list(v, MEMORY_MAX_ITEMS, (o) => {
    const text = short(o.text, MEMORY_TEXT_CHARS);
    return text?.trim() ? { source: short(o.source, MEMORY_SOURCE_CHARS)?.trim() || "memory", text: text.trim() } : undefined;
  });
  const out: MemoryItem[] = [];
  let budget = MEMORY_TOTAL_CHARS;
  for (const m of items) {
    const room = budget - m.source.length;
    if (room < Math.min(MEMORY_MIN_TAIL, m.text.length)) break;
    const text = m.text.length > room ? m.text.slice(0, room - 1) + "…" : m.text;
    out.push({ source: m.source, text });
    budget -= m.source.length + text.length;
  }
  return out;
}

// ---------------------------------------------------------------- extract

/** Refs round-trip to the client verbatim, so they are rejected (not truncated) when malformed. */
const REF_RE = /^[^\u0000-\u001f<>]{1,40}$/;

function isoTime(v: unknown): string | undefined {
  const s = short(v, 40);
  return s && !Number.isNaN(Date.parse(s)) ? s : undefined;
}

function names(v: unknown): string[] {
  if (!Array.isArray(v)) return [];
  const out: string[] = [];
  for (const n of v) {
    if (out.length >= EXTRACT_KNOWN_MAX) break;
    const s = short(n, 80)?.trim();
    if (s) out.push(s);
  }
  return out;
}

export function validateExtract(body: unknown): Validated<ExtractRequest> {
  if (!isObj(body)) return bad("invalid_body");
  if (!Array.isArray(body.batch) || body.batch.length === 0) return bad("invalid_batch");
  if (body.batch.length > EXTRACT_MAX_ITEMS) return tooLarge;
  const now = isoTime(body.now);
  if (!now) return bad("invalid_now");
  const loc = locale(body.locale);
  if (loc === false) return bad("invalid_locale");

  const batch: CaptureItem[] = [];
  const refs = new Set<string>();
  let textChars = 0;
  let metaChars = 0;
  for (const it of body.batch) {
    if (!isObj(it)) return bad("invalid_batch");
    const { ref, app, kind, text } = it;
    if (typeof ref !== "string" || !REF_RE.test(ref) || refs.has(ref)) return bad("invalid_ref");
    if (typeof app !== "string" || typeof text !== "string") return bad("invalid_batch");
    if (typeof kind !== "string" || !(CAPTURE_KINDS as readonly string[]).includes(kind)) return bad("invalid_kind");
    if (!optStr(it.window) || !optStr(it.chat) || !optStr(it.url_domain) || !optStr(it.sender) || !optStr(it.time))
      return bad("invalid_batch");
    if (it.fromMe !== undefined && it.fromMe !== null && typeof it.fromMe !== "boolean") return bad("invalid_batch");
    refs.add(ref);
    textChars += text.length;
    if (!text.trim()) continue; // nothing to read; still counted as a known ref
    const item: CaptureItem = {
      ref,
      app: short(app, 80) ?? "unknown",
      window: short(it.window),
      chat: short(it.chat, 120),
      url_domain: short(it.url_domain, 120),
      kind: kind as CaptureItem["kind"],
      sender: short(it.sender, 120),
      fromMe: typeof it.fromMe === "boolean" ? it.fromMe : undefined,
      time: short(it.time, 40),
      text,
    };
    metaChars += item.app.length + (item.window?.length ?? 0) + (item.chat?.length ?? 0) + (item.sender?.length ?? 0) + 60;
    batch.push(item);
  }
  if (textChars > EXTRACT_TEXT_CHARS) return tooLarge;
  if (batch.length === 0) return bad("empty_input");

  const known = isObj(body.known) ? body.known : {};
  const people = names(known.people);
  const projects = names(known.projects);
  const knownChars = [...people, ...projects].reduce((n, s) => n + s.length + 2, 0);
  return {
    ok: true,
    value: { batch, known: { people, projects }, now, timezone: short(body.timezone, 60), locale: loc },
    inputChars: textChars + metaChars + knownChars,
  };
}

// ---------------------------------------------------------------- digest

const DAY_RE = /^\d{4}-\d{2}-\d{2}$/;

export function validateDigest(body: unknown): Validated<DigestRequest> {
  if (!isObj(body)) return bad("invalid_body");
  if (typeof body.day !== "string" || !DAY_RE.test(body.day)) return bad("invalid_day");
  if (!Array.isArray(body.parts) || body.parts.length === 0 || body.parts.length > DAY_PARTS.length) return bad("invalid_parts");
  const loc = locale(body.locale);
  if (loc === false) return bad("invalid_locale");

  const parts: DigestRequest["parts"] = [];
  const seen = new Set<string>();
  let chars = 0;
  for (const p of body.parts) {
    if (!isObj(p) || typeof p.part !== "string" || !(DAY_PARTS as readonly string[]).includes(p.part)) return bad("invalid_parts");
    if (seen.has(p.part)) return bad("invalid_parts");
    seen.add(p.part);
    if (!Array.isArray(p.segments)) return bad("invalid_parts");
    if (p.segments.length > DIGEST_MAX_SEGMENTS) return tooLarge;
    const segments: DigestSegment[] = [];
    for (const g of p.segments) {
      if (!isObj(g) || typeof g.app !== "string" || typeof g.summary !== "string") return bad("invalid_segment");
      if (typeof g.minutes !== "number" || !Number.isFinite(g.minutes) || g.minutes < 0) return bad("invalid_segment");
      if (!optStr(g.window) || !optStr(g.chat) || !optStr(g.url_domain)) return bad("invalid_segment");
      for (const f of [g.app, g.window, g.chat, g.url_domain, g.summary]) if (typeof f === "string") chars += f.length;
      const app = short(g.app, 80);
      if (!app) continue;
      segments.push({
        app,
        window: short(g.window),
        chat: short(g.chat, 120),
        url_domain: short(g.url_domain, 120),
        minutes: Math.min(1440, Math.round(g.minutes)),
        summary: g.summary.slice(0, 300),
      });
    }
    if (segments.length) parts.push({ part: p.part as DigestRequest["parts"][number]["part"], segments });
  }
  if (chars > DIGEST_TOTAL_CHARS) return tooLarge;
  if (parts.length === 0) return bad("empty_input");
  parts.sort((a, b) => DAY_PARTS.indexOf(a.part) - DAY_PARTS.indexOf(b.part));
  return { ok: true, value: { day: body.day, parts, locale: loc }, inputChars: chars };
}
