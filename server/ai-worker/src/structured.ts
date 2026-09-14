/**
 * Server-side validation of the model's JSON for /v1/extract and /v1/digest.
 * The model is untrusted: unknown refs and types are dropped, strings clamped, lists capped.
 * A parser returns null only when the output is unusable (not JSON / wrong top-level shape),
 * which triggers the one retry on the fallback model.
 */
import type { DigestRequest, ExtractRequest, PlanRequest } from "./validate";

export const TODO_SIGNALS = ["reply_to", "page_contains", "message_sent", "file_sent", "none"] as const;
export const ENTITY_TYPES = ["person", "project", "org", "topic", "tool"] as const;
export const IDENTIFIER_TYPES = ["email", "phone", "handle", "url"] as const;
export const RELATION_KINDS = ["works_at", "member_of", "talks_with", "about"] as const;

export const EXTRACT_CAPS = { todos: 15, entities: 40, relations: 40, facts: 40 } as const;

export interface Todo {
  title: string;
  reason: string;
  source_ref: string;
  confidence: number;
  due: string | null;
  people: string[];
  done_signal: { type: (typeof TODO_SIGNALS)[number]; pattern: string };
}

export interface Entity {
  type: (typeof ENTITY_TYPES)[number];
  name: string;
  aliases: string[];
  identifiers: { type: (typeof IDENTIFIER_TYPES)[number]; value: string }[];
  role: string | null;
  org: string | null;
  evidence_ref: string;
}

export interface Relation {
  a: string;
  b: string;
  kind: (typeof RELATION_KINDS)[number];
  evidence_ref: string;
}

export interface Fact {
  entity: string;
  key: string;
  value: string;
  evidence_ref: string;
  confidence: number;
}

export interface ExtractResult {
  todos: Todo[];
  entities: Entity[];
  relations: Relation[];
  facts: Fact[];
}

export interface DigestResult {
  parts: { part: DigestRequest["parts"][number]["part"]; bullets: string[]; apps: string[] }[];
}

export const EMPTY_EXTRACT: ExtractResult = { todos: [], entities: [], relations: [], facts: [] };
export const EMPTY_DIGEST: DigestResult = { parts: [] };

/** JSON object from model output, tolerating a ```json fence or stray prose around it. */
export function parseModelJson(content: string): Record<string, unknown> | null {
  let s = content.trim();
  const fence = /^```(?:json)?\s*([\s\S]*?)\s*```$/i.exec(s);
  if (fence) s = fence[1];
  const tryParse = (t: string) => {
    try {
      const v = JSON.parse(t);
      return typeof v === "object" && v !== null && !Array.isArray(v) ? (v as Record<string, unknown>) : null;
    } catch {
      return null;
    }
  };
  const direct = tryParse(s);
  if (direct) return direct;
  const a = s.indexOf("{");
  const b = s.lastIndexOf("}");
  return a >= 0 && b > a ? tryParse(s.slice(a, b + 1)) : null;
}

function isObj(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

/** Trimmed, whitespace-collapsed, clamped; undefined if empty or not a string. */
function str(v: unknown, max: number): string | undefined {
  if (typeof v !== "string") return undefined;
  const s = v.replace(/\s+/g, " ").trim();
  if (!s) return undefined;
  return s.length > max ? s.slice(0, max - 1).trimEnd() + "…" : s;
}

function oneOf<T extends string>(v: unknown, allowed: readonly T[]): T | undefined {
  return typeof v === "string" && (allowed as readonly string[]).includes(v) ? (v as T) : undefined;
}

function unit(v: unknown, dflt = 0.5): number {
  const n = typeof v === "string" ? Number(v) : v;
  return typeof n === "number" && Number.isFinite(n) ? Math.min(1, Math.max(0, Math.round(n * 100) / 100)) : dflt;
}

function strList(v: unknown, maxItems: number, maxLen: number): string[] {
  if (!Array.isArray(v)) return [];
  const out: string[] = [];
  const seen = new Set<string>();
  for (const x of v) {
    if (out.length >= maxItems) break;
    const s = str(x, maxLen);
    if (s && !seen.has(s.toLowerCase())) {
      seen.add(s.toLowerCase());
      out.push(s);
    }
  }
  return out;
}

function items<T>(v: unknown, max: number, map: (o: Record<string, unknown>) => T | undefined, key?: (t: T) => string): T[] {
  if (!Array.isArray(v)) return [];
  const out: T[] = [];
  const seen = new Set<string>();
  for (const x of v) {
    if (out.length >= max) break;
    if (!isObj(x)) continue;
    const t = map(x);
    if (!t) continue;
    if (key) {
      const k = key(t);
      if (seen.has(k)) continue;
      seen.add(k);
    }
    out.push(t);
  }
  return out;
}

function isoOrNull(v: unknown): string | null {
  const s = str(v, 40);
  return s && !Number.isNaN(Date.parse(s)) ? s : null;
}

export function clampExtract(raw: Record<string, unknown>, req: Pick<ExtractRequest, "batch">): ExtractResult {
  const refs = new Set(req.batch.map((i) => i.ref));
  const ref = (v: unknown) => (typeof v === "string" && refs.has(v) ? v : undefined);

  const todos = items(
    raw.todos,
    EXTRACT_CAPS.todos,
    (o): Todo | undefined => {
      const title = str(o.title, 80);
      const source_ref = ref(o.source_ref);
      if (!title || !source_ref) return undefined;
      const ds = isObj(o.done_signal) ? o.done_signal : {};
      const type = oneOf(ds.type, TODO_SIGNALS) ?? "none";
      const pattern = type === "none" ? "" : (str(ds.pattern, 120) ?? "");
      return {
        title,
        reason: str(o.reason, 160) ?? "",
        source_ref,
        confidence: unit(o.confidence),
        due: isoOrNull(o.due),
        people: strList(o.people, 10, 80),
        done_signal: pattern || type === "none" ? { type, pattern } : { type: "none", pattern: "" },
      };
    },
    (t) => t.title.toLowerCase(),
  );

  const entities = items(
    raw.entities,
    EXTRACT_CAPS.entities,
    (o): Entity | undefined => {
      const type = oneOf(o.type, ENTITY_TYPES);
      const name = str(o.name, 80);
      const evidence_ref = ref(o.evidence_ref);
      if (!type || !name || !evidence_ref) return undefined;
      return {
        type,
        name,
        aliases: strList(o.aliases, 10, 80).filter((a) => a.toLowerCase() !== name.toLowerCase()),
        identifiers: items(o.identifiers, 10, (i) => {
          const t = oneOf(i.type, IDENTIFIER_TYPES);
          const value = str(i.value, 200);
          return t && value ? { type: t, value } : undefined;
        }, (i) => `${i.type}:${i.value.toLowerCase()}`),
        role: str(o.role, 80) ?? null,
        org: str(o.org, 80) ?? null,
        evidence_ref,
      };
    },
    (e) => `${e.type}:${e.name.toLowerCase()}`,
  );

  const relations = items(
    raw.relations,
    EXTRACT_CAPS.relations,
    (o): Relation | undefined => {
      const a = str(o.a, 80);
      const b = str(o.b, 80);
      const kind = oneOf(o.kind, RELATION_KINDS);
      const evidence_ref = ref(o.evidence_ref);
      return a && b && kind && evidence_ref && a.toLowerCase() !== b.toLowerCase() ? { a, b, kind, evidence_ref } : undefined;
    },
    (r) => `${r.a.toLowerCase()}|${r.kind}|${r.b.toLowerCase()}`,
  );

  const facts = items(
    raw.facts,
    EXTRACT_CAPS.facts,
    (o): Fact | undefined => {
      const entity = str(o.entity, 80);
      const key = str(o.key, 60);
      const value = str(typeof o.value === "number" || typeof o.value === "boolean" ? String(o.value) : o.value, 200);
      const evidence_ref = ref(o.evidence_ref);
      return entity && key && value && evidence_ref ? { entity, key, value, evidence_ref, confidence: unit(o.confidence) } : undefined;
    },
    (f) => `${f.entity.toLowerCase()}|${f.key.toLowerCase()}|${f.value.toLowerCase()}`,
  );

  return { todos, entities, relations, facts };
}

/** Parser for runJsonTask: any JSON object is usable (missing lists read as empty). */
export function extractParser(req: ExtractRequest) {
  return (content: string): ExtractResult | null => {
    const raw = parseModelJson(content);
    return raw ? clampExtract(raw, req) : null;
  };
}

export function clampDigest(raw: Record<string, unknown>, req: DigestRequest): DigestResult {
  const out: DigestResult["parts"] = [];
  const got = Array.isArray(raw.parts) ? raw.parts.filter(isObj) : [];
  for (const input of req.parts) {
    const m = got.find((p) => p.part === input.part);
    if (!m) continue;
    const bullets = strList(m.bullets, 3, 160).map((b) => b.replace(/^[-•*]\s+/, ""));
    // Apps must come from this part's input; canonicalise the spelling.
    const inputApps = new Map(input.segments.map((g) => [g.app.toLowerCase(), g.app]));
    let apps = strList(m.apps, 8, 80)
      .map((a) => inputApps.get(a.toLowerCase()))
      .filter((a): a is string => !!a);
    if (!apps.length) {
      // Model left it out: fall back to the part's apps by time spent.
      const mins = new Map<string, number>();
      for (const g of input.segments) mins.set(g.app, (mins.get(g.app) ?? 0) + g.minutes);
      apps = [...mins.entries()].sort((a, b) => b[1] - a[1]).map(([a]) => a);
    }
    if (bullets.length) out.push({ part: input.part, bullets, apps: [...new Set(apps)].slice(0, 8) });
  }
  return { parts: out };
}

/** Parser for runJsonTask: needs a `parts` array, otherwise the output is treated as malformed. */
export function digestParser(req: DigestRequest) {
  return (content: string): DigestResult | null => {
    const raw = parseModelJson(content);
    return raw && Array.isArray(raw.parts) ? clampDigest(raw, req) : null;
  };
}

export const PLAN_WANTS = ["activity", "time", "contacts", "messages", "sites", "todos", "person", "search", "when"] as const;
export const PLAN_PARTS = ["morning", "afternoon", "evening"] as const;
export const PLAN_ORDERS = ["relevance", "latest", "earliest"] as const;

export interface PlanResult {
  needs_memory: boolean;
  from: string | null;
  to: string | null;
  part: (typeof PLAN_PARTS)[number] | null;
  last_hours: number | null;
  apps: string[];
  sites: string[];
  chats: string[];
  people: string[];
  from_me: boolean | null;
  queries: string[];
  want: (typeof PLAN_WANTS)[number][];
  order: (typeof PLAN_ORDERS)[number];
}

export const EMPTY_PLAN: PlanResult = {
  needs_memory: false,
  from: null,
  to: null,
  part: null,
  last_hours: null,
  apps: [],
  sites: [],
  chats: [],
  people: [],
  from_me: null,
  queries: [],
  want: [],
  order: "relevance",
};

const DAY = /^\d{4}-\d{2}-\d{2}$/;
const dayMs = (d: string) => Date.parse(`${d}T00:00:00Z`);

/** Only names the app sent come back, in the app's spelling. */
function canonical(v: unknown, known: string[], max: number): string[] {
  const map = new Map(known.map((k) => [k.toLowerCase(), k]));
  return strList(v, max * 2, 120)
    .map((x) => map.get(x.toLowerCase()))
    .filter((x): x is string => !!x)
    .slice(0, max);
}

export function clampPlan(raw: Record<string, unknown>, req: PlanRequest): PlanResult {
  // A day range that ends by today and spans at most 31 days.
  let from = typeof raw.from === "string" && DAY.test(raw.from) && raw.from <= req.today ? raw.from : null;
  let to = typeof raw.to === "string" && DAY.test(raw.to) ? (raw.to > req.today ? req.today : raw.to) : null;
  if (from && !to) to = from === req.today ? req.today : from;
  if (to && !from) from = to;
  if (from && to && from > to) [from, to] = [to, from];
  if (from && to && (dayMs(to) - dayMs(from)) / 86_400_000 > 30) from = new Date(dayMs(to) - 30 * 86_400_000).toISOString().slice(0, 10);
  const hours = typeof raw.last_hours === "number" && Number.isFinite(raw.last_hours) ? Math.round(raw.last_hours) : null;
  const want = Array.isArray(raw.want)
    ? [...new Set(raw.want.map((w) => oneOf(w, PLAN_WANTS)).filter((w): w is PlanResult["want"][number] => !!w))]
    : [];
  const plan: PlanResult = {
    needs_memory: true,
    from,
    to,
    part: oneOf(raw.part, PLAN_PARTS) ?? null,
    last_hours: hours && hours >= 1 ? Math.min(24, hours) : null,
    apps: canonical(raw.apps, req.apps, 6),
    sites: canonical(raw.sites, req.sites, 6),
    chats: canonical(raw.chats, req.chats, 6),
    people: strList(raw.people, 4, 60),
    from_me: typeof raw.from_me === "boolean" ? raw.from_me : null,
    queries: strList(raw.queries, 3, 60),
    want,
    order: oneOf(raw.order, PLAN_ORDERS) ?? "relevance",
  };
  const asked = (plan.from ? 1 : 0) + (plan.last_hours ? 1 : 0) + plan.want.length + plan.queries.length + plan.people.length + plan.apps.length + plan.sites.length + plan.chats.length;
  const needs = typeof raw.needs_memory === "boolean" ? raw.needs_memory : asked > 0;
  return needs ? plan : EMPTY_PLAN;
}

/** Parser for runJsonTask: any JSON object is usable. */
export function planParser(req: PlanRequest) {
  return (content: string): PlanResult | null => {
    const raw = parseModelJson(content);
    return raw ? clampPlan(raw, req) : null;
  };
}
