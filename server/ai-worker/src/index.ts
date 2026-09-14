import { ReplayGuard, isValidPublicKey, verifySignedRequest } from "./auth";
import { type Env, MAX_BODY_BYTES, TURNSTILE_URL, estimateCostUsd, limitsFrom, modelsFrom } from "./config";
import { buildOpenRouterBody, callOpenRouter } from "./openrouter";
import { TASK_ROUTES } from "./routes";
import { type StreamResult, translateStream } from "./sse";
import { ipPrefix, json, randomId, sha256hex } from "./util";

export { GlobalBudget, InstallQuota } from "./durable";

const INSTALL_ID_RE = /^[0-9a-f]{32}$/;

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);
    const route = `${request.method} ${url.pathname}`;
    try {
      switch (route) {
        case "GET /health":
          return json({ ok: true });
        case "POST /v1/register":
          return await register(request, env);
        case "GET /v1/quota":
          return await signed(request, env, ctx, url.pathname);
        default:
          if (request.method === "POST" && url.pathname in TASK_ROUTES) return await signed(request, env, ctx, url.pathname);
          return json({ error: "not_found" }, 404);
      }
    } catch (err) {
      console.error("unhandled", route, err);
      return json({ error: "internal" }, 500);
    }
  },
} satisfies ExportedHandler<Env>;

// ---------------------------------------------------------------- register

async function verifyTurnstile(env: Env, token: unknown, ip: string): Promise<boolean> {
  if (env.DEV_SKIP_TURNSTILE === "1") return true;
  if (typeof token !== "string" || !token || token.length > 2048) return false;
  const form = new FormData();
  form.append("secret", env.TURNSTILE_SECRET);
  form.append("response", token);
  if (ip) form.append("remoteip", ip);
  const res = await fetch(TURNSTILE_URL, { method: "POST", body: form });
  if (!res.ok) return false;
  const data = (await res.json()) as { success?: boolean };
  return data.success === true;
}

async function register(request: Request, env: Env): Promise<Response> {
  const raw = await request.arrayBuffer();
  if (raw.byteLength > 8 * 1024) return json({ error: "too_large" }, 413);
  let body: any;
  try {
    body = JSON.parse(new TextDecoder().decode(raw));
  } catch {
    return json({ error: "invalid_body" }, 400);
  }
  if (!isValidPublicKey(body?.publicKey)) return json({ error: "invalid_public_key" }, 400);

  const ip = request.headers.get("cf-connecting-ip") ?? "";
  const prefixHash = await sha256hex(ipPrefix(ip));
  const { success } = await env.REGISTER_LIMITER.limit({ key: prefixHash });
  if (!success) return json({ error: "rate_limited" }, 429, { "retry-after": "60" });

  if (!(await verifyTurnstile(env, body.turnstileToken, ip))) return json({ error: "turnstile_failed" }, 403);

  const existing = await env.DB.prepare("SELECT id, revoked FROM installs WHERE public_key = ?")
    .bind(body.publicKey)
    .first<{ id: string; revoked: number }>();
  if (existing) {
    if (existing.revoked) return json({ error: "revoked" }, 403);
    return json({ installId: existing.id });
  }

  const nowS = Math.floor(Date.now() / 1000);
  const limits = limitsFrom(env);
  const recent = await env.DB.prepare("SELECT COUNT(*) AS n FROM installs WHERE ip_prefix_hash = ? AND created_at > ?")
    .bind(prefixHash, nowS - 86_400)
    .first<{ n: number }>();
  if ((recent?.n ?? 0) >= limits.registrationsPerPrefixPerDay) return json({ error: "rate_limited" }, 429);

  const installId = randomId();
  const appVersion = typeof body.appVersion === "string" ? body.appVersion.slice(0, 32) : null;
  await env.DB.prepare(
    "INSERT INTO installs (id, public_key, created_at, app_version, ip_prefix_hash) VALUES (?, ?, ?, ?, ?)",
  )
    .bind(installId, body.publicKey, nowS, appVersion, prefixHash)
    .run();
  return json({ installId }, 201);
}

// ---------------------------------------------------------------- signed routes

async function signed(request: Request, env: Env, ctx: ExecutionContext, path: string): Promise<Response> {
  const installId = request.headers.get("x-gobbl-install") ?? "";
  const tsHeader = request.headers.get("x-gobbl-timestamp");
  const sigHeader = request.headers.get("x-gobbl-signature");
  if (!INSTALL_ID_RE.test(installId)) return json({ error: "unauthorized", reason: "bad_install" }, 401);

  const len = Number(request.headers.get("content-length") ?? 0);
  if (len > MAX_BODY_BYTES) return json({ error: "too_large" }, 413);
  const raw = await request.arrayBuffer();
  if (raw.byteLength > MAX_BODY_BYTES) return json({ error: "too_large" }, 413);

  if (await env.REVOKED.get(installId)) return json({ error: "revoked" }, 403);
  const install = await env.DB.prepare("SELECT public_key, revoked FROM installs WHERE id = ?")
    .bind(installId)
    .first<{ public_key: string; revoked: number }>();
  if (!install) return json({ error: "unauthorized", reason: "unknown_install" }, 401);
  if (install.revoked) return json({ error: "revoked" }, 403);

  const nowMs = Date.now();
  const nowS = Math.floor(nowMs / 1000);
  const v = await verifySignedRequest({
    method: request.method,
    path,
    timestampHeader: tsHeader,
    signatureHeader: sigHeader,
    body: raw,
    publicKey: install.public_key,
    nowS,
  });
  if (!v.ok) return json({ error: "unauthorized", reason: v.reason }, 401);

  const quota = env.INSTALL_QUOTA.get(env.INSTALL_QUOTA.idFromName(installId));
  if (await quota.checkReplay(ReplayGuard.key(tsHeader!, sigHeader!), nowS))
    return json({ error: "unauthorized", reason: "replay" }, 401);

  const limits = limitsFrom(env);
  if (path === "/v1/quota") return json(await quota.status(limits, nowMs));

  const burst = await env.BURST_LIMITER.limit({ key: installId });
  if (!burst.success) return json({ error: "rate_limited" }, 429, { "retry-after": "10" });

  let body: unknown;
  try {
    body = JSON.parse(new TextDecoder().decode(raw));
  } catch {
    return json({ error: "invalid_body" }, 400);
  }

  const prepared = TASK_ROUTES[path](body);
  if (!prepared.ok) return json({ error: prepared.error }, prepared.status);
  const { messages, inputChars, maxTokens } = prepared;

  const est = estimateCostUsd(inputChars, maxTokens);
  const global = env.GLOBAL_BUDGET.get(env.GLOBAL_BUDGET.idFromName("global"));
  const g = await global.reserve(limits.globalDailyUsd, est, nowMs);
  if (!g.ok) return json({ error: "paused" }, 503, { "retry-after": "3600" });
  const q = await quota.reserve(limits, est, nowMs);
  if (!q.ok) {
    ctx.waitUntil(global.settle(g.day, est, 0, nowMs));
    return json({ error: "quota", reason: q.reason, resetsAt: q.resetsAt }, 429);
  }

  const settle = (actualUsd: number, refundAction: boolean) => {
    const t = Date.now();
    ctx.waitUntil(
      Promise.allSettled([
        quota.settle(q.day, est, actualUsd, refundAction, t),
        global.settle(g.day, est, actualUsd, t),
        refundAction
          ? Promise.resolve()
          : env.DB.prepare(
              `INSERT INTO usage_daily (install_id, day, actions, usd) VALUES (?, ?, 1, ?)
               ON CONFLICT (install_id, day) DO UPDATE SET actions = actions + 1, usd = usd + excluded.usd`,
            )
              .bind(installId, q.day, actualUsd)
              .run(),
      ]).then((rs) => rs.forEach((r) => r.status === "rejected" && console.error("settle failed", r.reason))),
    );
  };

  let upstream: Response;
  try {
    upstream = await callOpenRouter(env.OPENROUTER_API_KEY, buildOpenRouterBody(messages, modelsFrom(env), maxTokens));
  } catch (err) {
    console.error("openrouter fetch failed", err);
    settle(0, true);
    return json({ error: "upstream" }, 502);
  }
  if (!upstream.ok || !upstream.body) {
    console.error("openrouter status", upstream.status, await upstream.text().catch(() => ""));
    settle(0, true);
    return json({ error: "upstream", status: upstream.status }, upstream.status === 429 ? 503 : 502);
  }

  const onFinish = (r: StreamResult) => {
    // Unknown cost (no usage chunk, e.g. client disconnected) → keep the conservative estimate.
    const cost = r.usage?.cost ?? (r.errored && r.outputChars === 0 ? 0 : est);
    settle(cost, r.errored && r.outputChars === 0);
  };

  return new Response(translateStream(upstream.body, onFinish), {
    headers: {
      "content-type": "text/event-stream; charset=utf-8",
      "cache-control": "no-store",
      "x-accel-buffering": "no",
    },
  });
}
