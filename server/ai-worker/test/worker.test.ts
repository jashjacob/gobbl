/**
 * End-to-end through the fetch handler: real signing, real Durable Object classes on
 * in-memory storage, fake D1/KV/rate limiter, mocked OpenRouter.
 */
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { canonicalString } from "../src/auth";
import { GlobalBudget, InstallQuota } from "../src/durable";
import worker from "../src/index";
import { b64encode, sha256hex } from "../src/util";

const INSTALL = "0123456789abcdef0123456789abcdef";

function storage() {
  const m = new Map<string, unknown>();
  return { get: async (k: string) => structuredClone(m.get(k)), put: async (k: string, v: unknown) => void m.set(k, structuredClone(v)) };
}

function namespace<T>(make: () => T) {
  const objs = new Map<string, T>();
  return {
    idFromName: (n: string) => n,
    get: (id: string) => {
      if (!objs.has(id)) objs.set(id, make());
      return objs.get(id)!;
    },
  };
}

async function setup(vars: Record<string, string> = {}) {
  const kp = (await crypto.subtle.generateKey({ name: "Ed25519" }, true, ["sign", "verify"])) as CryptoKeyPair;
  const pub = b64encode((await crypto.subtle.exportKey("raw", kp.publicKey)) as ArrayBuffer);
  const globalNs = namespace(() => new GlobalBudget({ storage: storage() } as any, {} as any));
  const env: any = {
    OPENROUTER_API_KEY: "sk-test",
    DAILY_ACTIONS: "40",
    DAILY_BACKGROUND: "2",
    GLOBAL_DAILY_USD: "1",
    ...vars,
    DB: {
      prepare: (sql: string) => ({
        bind: (..._args: unknown[]) => ({
          first: async () => (sql.startsWith("SELECT public_key") ? { public_key: pub, revoked: 0 } : null),
          run: async () => ({}),
        }),
      }),
    },
    REVOKED: { get: async () => null },
    INSTALL_QUOTA: namespace(() => new InstallQuota({ storage: storage() } as any, {} as any)),
    GLOBAL_BUDGET: globalNs,
    BURST_LIMITER: { limit: async () => ({ success: true }) },
  };
  const pending: Promise<unknown>[] = [];
  const ctx: any = { waitUntil: (p: Promise<unknown>) => pending.push(p), passThroughOnException() {} };

  // Node's Ed25519 is deterministic: identical requests in one second would be replays, so step the timestamp back.
  let skew = 0;
  async function call(method: string, path: string, body?: unknown) {
    const raw = body === undefined ? "" : JSON.stringify(body);
    const ts = String(Math.floor(Date.now() / 1000) - skew++);
    const sig = b64encode(
      await crypto.subtle.sign({ name: "Ed25519" }, kp.privateKey, new TextEncoder().encode(canonicalString(method, path, ts, await sha256hex(raw)))),
    );
    const req = new Request(`https://ai.xeve.io${path}`, {
      method,
      body: body === undefined ? undefined : raw,
      headers: { "x-gobbl-install": INSTALL, "x-gobbl-timestamp": ts, "x-gobbl-signature": sig },
    });
    const res = await worker.fetch(req, env, ctx);
    await Promise.all(pending.splice(0));
    return res;
  }
  return { env, call, global: globalNs.get("global") as unknown as GlobalBudget };
}

const extractBody = { batch: [{ ref: "r1", app: "Chrome", url_domain: "ksrtc.in", kind: "text", text: "Review your booking. Proceed to payment." }], now: new Date().toISOString() };
const chatBody = { messages: [{ role: "user", content: "hi" }] };

const jsonReply = (content: string, cost = 0.0001) => new Response(JSON.stringify({ choices: [{ message: { content } }], usage: { cost } }));
const sseReply = () =>
  new Response(`data: ${JSON.stringify({ choices: [{ delta: { content: "Hi!" } }], usage: { cost: 0.0001 } })}\n\ndata: [DONE]\n\n`);

let fetchMock: ReturnType<typeof vi.fn>;
beforeEach(() => {
  fetchMock = vi.fn(async (_u: string, init: RequestInit) =>
    JSON.parse(init.body as string).stream
      ? sseReply()
      : jsonReply(
          JSON.stringify({
            todos: [{ title: "Complete KSRTC booking", reason: "Booking left at payment", source_ref: "r1", confidence: 0.8, due: null, people: [], done_signal: { type: "page_contains", pattern: "booking confirmed|payment successful" } }],
          }),
        ),
  );
  vi.stubGlobal("fetch", fetchMock);
});
afterEach(() => vi.unstubAllGlobals());

describe("worker: background endpoints", () => {
  it("extract returns clamped JSON and counts against the background quota, not actions", async () => {
    const { call } = await setup();
    const res = await call("POST", "/v1/extract", extractBody);
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toMatch(/application\/json/);
    const body: any = await res.json();
    expect(body).toMatchObject({ degraded: false, entities: [], relations: [], facts: [] });
    expect(body.todos[0]).toMatchObject({ title: "Complete KSRTC booking", source_ref: "r1", done_signal: { type: "page_contains" } });

    const q: any = await (await call("GET", "/v1/quota")).json();
    expect(q).toMatchObject({ actionsRemaining: 40, actionsUsed: 0, backgroundRemaining: 1, backgroundLimit: 2, backgroundUsed: 1 });

    expect((await call("POST", "/v1/extract", extractBody)).status).toBe(200);
    const third = await call("POST", "/v1/extract", extractBody);
    expect(third.status).toBe(429);
    expect(await third.json()).toMatchObject({ error: "quota", reason: "background" });
    // User actions are untouched.
    expect((await call("POST", "/v1/chat", chatBody)).status).toBe(200);
  });

  it("returns an empty degraded result after two malformed answers, and refunds on upstream failure", async () => {
    const { call } = await setup();
    fetchMock.mockImplementation(async () => jsonReply("I cannot do JSON today"));
    const res = await call("POST", "/v1/extract", extractBody);
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ todos: [], entities: [], relations: [], facts: [], degraded: true });
    expect(fetchMock).toHaveBeenCalledTimes(2);

    fetchMock.mockImplementation(async () => new Response("down", { status: 500 }));
    const failed = await call("POST", "/v1/digest", { day: "2026-09-14", parts: [{ part: "morning", segments: [{ app: "Mail", minutes: 5, summary: "Inbox" }] }] });
    expect(failed.status).toBe(502);
    const q: any = await (await call("GET", "/v1/quota")).json();
    expect(q.backgroundUsed).toBe(1); // degraded call billed, failed call refunded
  });

  it("validation errors come back before any quota is reserved", async () => {
    const { call } = await setup();
    const big = { ...extractBody, batch: [{ ...extractBody.batch[0], text: "x".repeat(6001) }] };
    expect((await call("POST", "/v1/extract", big)).status).toBe(413);
    expect(await (await call("POST", "/v1/digest", { day: "today", parts: [] })).json()).toEqual({ error: "invalid_day" });
    expect(((await (await call("GET", "/v1/quota")).json()) as any).backgroundUsed).toBe(0);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("pauses background calls at 80% of the global budget while user calls keep working", async () => {
    const { call, global } = await setup({ GLOBAL_DAILY_USD: "1" });
    const r = await global.reserve(1, 0.8, Date.now()); // global spend now at 80%
    expect(r.ok).toBe(true);
    const bg = await call("POST", "/v1/extract", extractBody);
    expect(bg.status).toBe(503);
    expect(await bg.json()).toEqual({ error: "paused", reason: "background" });
    expect(bg.headers.get("retry-after")).toBe("3600");
    const user = await call("POST", "/v1/chat", chatBody);
    expect(user.status).toBe(200);
    expect(await user.text()).toContain("event: done");

    await global.reserve(1, 0.1999, Date.now()); // 0.8 + 0.0001 (settled chat) + 0.1999 = 100%
    const full = await call("POST", "/v1/chat", chatBody);
    expect(full.status).toBe(503);
    expect(await full.json()).toEqual({ error: "paused" });
  });

  it("does not route prototype keys", async () => {
    const { call } = await setup();
    expect((await call("POST", "/constructor", {})).status).toBe(404);
  });
});
