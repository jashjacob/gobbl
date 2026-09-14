/**
 * Server-side validation of the model's JSON for /v1/extract and /v1/digest.
 * The model is untrusted: unknown refs and types are dropped, strings clamped, lists capped.
 * A parser returns null only when the output is unusable (not JSON / wrong top-level shape),
 * which triggers the one retry on the fallback model.
 */
import type { DigestRequest, ExtractRequest } from "./validate";

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
