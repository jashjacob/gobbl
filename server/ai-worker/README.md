# gobbl-ai — AI proxy Worker for Gobbl

Gobbl is MIT and open source, so no secret can ship in the app. This Cloudflare Worker holds the OpenRouter key and exposes
only **task-shaped** endpoints (`/v1/write`, `/v1/cleanup`) whose prompts live on the server, behind:

- **Install identity** — each install registers an Ed25519 public key once (Turnstile-gated, throttled per /24 or /64 prefix) and signs every request. Replays are rejected.
- **Per-install quota** — `InstallQuota` Durable Object: 40 actions/day and $0.05/day by default. Cost is reserved (worst case) before calling OpenRouter and settled to the real `usage.cost` afterwards.
- **Burst limit** — Rate Limiting binding, 10 requests / 10 s per install.
- **Global circuit breaker** — `GlobalBudget` Durable Object: $20/day across all installs, then `503 paused` until UTC midnight.
- **Revocation** — any install id present in the `REVOKED` KV namespace gets `403`.
- **Model allowlist** — only models in `src/config.ts` `MODEL_ALLOWLIST` can be called; `provider.data_collection = "deny"`; `max_tokens` capped; inputs over 12k chars rejected.

Client contract (signing, SSE format, errors): **[API.md](API.md)**.

## Layout

```
src/index.ts       router + request pipeline
src/auth.ts        canonical string, Ed25519 verify, timestamp window, replay guard
src/quota.ts       pure quota math (reserve / settle / UTC-midnight reset)
src/durable.ts     InstallQuota + GlobalBudget Durable Objects
src/validate.ts    request validation and caps
src/prompts.ts     server-side system prompts
src/openrouter.ts  upstream request
src/sse.ts         OpenRouter SSE → Gobbl SSE translation
migrations/        D1 schema (installs, usage_daily)
test/              vitest unit tests (plain Node; no Workers runtime needed)
```

## Develop

```sh
npm install
npm test            # unit tests
npm run typecheck
```

Local run: create `.dev.vars` (git-ignored):

```
OPENROUTER_API_KEY=sk-or-...
TURNSTILE_SECRET=1x0000000000000000000000000000000AA   # Cloudflare's always-pass test secret
DEV_SKIP_TURNSTILE=1
```

then `npm run db:migrate:local && npm run dev`.

## Deploy (not done yet)

```sh
npx wrangler login
npx wrangler d1 create gobbl-ai                 # paste database_id into wrangler.toml
npx wrangler kv namespace create REVOKED        # paste id into wrangler.toml
npx wrangler d1 migrations apply gobbl-ai --remote
npx wrangler secret put OPENROUTER_API_KEY
npx wrangler secret put TURNSTILE_SECRET
# set account_id and uncomment the ai.xeve.io route in wrangler.toml
npx wrangler deploy
```

Required secrets:

| Secret | What |
|---|---|
| `OPENROUTER_API_KEY` | OpenRouter key. Give it its own credit limit in the OpenRouter dashboard as a last-line backstop. |
| `TURNSTILE_SECRET` | Secret key of the Turnstile widget used by the verify page. |

Vars (in `wrangler.toml`): `DAILY_ACTIONS` (40), `DAILY_USD_CAP` (0.05), `GLOBAL_DAILY_USD` (20),
`REGISTRATIONS_PER_PREFIX_PER_DAY` (20), `MODEL`, `FALLBACK_MODEL` (both must be in the allowlist, else defaults are used).
Never set `DEV_SKIP_TURNSTILE` in production.

Revoke an install: `npx wrangler kv key put --binding REVOKED <installId> 1 --remote`
(optionally also `UPDATE installs SET revoked = 1 WHERE id = ?` in D1).

## Turnstile page (idea — not built here)

A static page at `https://gobbl.xeve.io/verify` that the app opens in a `WKWebView` during first-run registration:

```html
<div class="cf-turnstile" data-sitekey="<SITE_KEY>" data-action="gobbl-register" data-callback="done"></div>
<script src="https://challenges.cloudflare.com/turnstile/v0/api.js" async defer></script>
<script>
  function done(token) {
    // Preferred: WKScriptMessageHandler named "gobbl"
    if (window.webkit?.messageHandlers?.gobbl) window.webkit.messageHandlers.gobbl.postMessage({ token });
    // Fallback: custom URL scheme handled by the app
    else location.href = "gobbl://turnstile?token=" + encodeURIComponent(token);
  }
</script>
```

The app forwards the token to `POST /v1/register` immediately (tokens expire after 300 s and are single use). Add
`gobbl.xeve.io` to the widget's allowed hostnames. Optionally, verify `action === "gobbl-register"` and `hostname` in
`verifyTurnstile()` once the page exists.

## Notes / limits

- Rate Limiting bindings are per Cloudflare location and eventually consistent — they stop bursts, not determined abuse; the Durable Object quotas are the real limit.
- If the client disconnects mid-stream before the usage chunk, the worst-case reservation is kept as the charge.
- `usage_daily` in D1 is written after each successful call for reporting; the DOs are the source of truth for enforcement.
