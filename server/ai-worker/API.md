# Gobbl AI API — client contract (v1)

Base URL: `https://ai.xeve.io`. All request bodies are UTF-8 JSON (`content-type: application/json`).
Errors that happen **before** a stream starts are JSON with an HTTP status. Once a `200 text/event-stream`
response has started, failures arrive as an `error` SSE event.

| Endpoint | Signed | Response | Counts against |
|---|---|---|---|
| `POST /v1/register` | no | JSON | – |
| `GET /v1/quota` | yes | JSON | nothing |
| `POST /v1/write` | yes | SSE | actions |
| `POST /v1/edit` | yes | SSE | actions |
| `POST /v1/cleanup` | yes | SSE | actions |
| `POST /v1/chat` | yes | SSE | actions |
| `POST /v1/brief` | yes | SSE | actions |
| `POST /v1/extract` | yes | JSON | background |
| `POST /v1/digest` | yes | JSON | background |
| `GET /health` | no | JSON | – |

Every text endpoint returns **only the result text** — no preamble, no surrounding quotes. `extract` and `digest` are not streamed:
they return one JSON object (§3), and they never use the user's daily actions (see *Quota classes* below).

## 1. Identity

On first launch the app:

1. Generates an **Ed25519** key pair (CryptoKit `Curve25519.Signing.PrivateKey`) and keeps the private key in the Keychain.
2. Obtains a Turnstile token (see README → *Turnstile page*).
3. Calls `POST /v1/register` and stores the returned `installId`.

### `POST /v1/register` (unsigned)

```json
{ "publicKey": "<base64 of the 32-byte raw public key>", "turnstileToken": "<token>", "appVersion": "0.2.0" }
```

| Status | Body |
|---|---|
| 201 | `{"installId":"<32 lowercase hex chars>"}` (new install) |
| 200 | `{"installId":"..."}` (this public key was already registered — same id returned) |
| 400 | `{"error":"invalid_public_key"}` / `{"error":"invalid_body"}` |
| 403 | `{"error":"turnstile_failed"}` / `{"error":"revoked"}` |
| 429 | `{"error":"rate_limited"}` (per /24 IPv4 or /64 IPv6 prefix; `retry-after` header may be set) |

`publicKey` is standard base64 **with** padding (44 chars). In Swift: `privateKey.publicKey.rawRepresentation.base64EncodedString()`.

## 2. Request signing (every other `/v1/*` request)

Headers:

| Header | Value |
|---|---|
| `X-Gobbl-Install` | the `installId` |
| `X-Gobbl-Timestamp` | current unix time in **seconds**, decimal string. Rejected if more than **120 s** from server time. |
| `X-Gobbl-Signature` | standard base64 (with padding) of the 64-byte Ed25519 signature over the canonical string |

Canonical string (UTF-8, fields joined by a single `\n`, **no trailing newline**):

```
<METHOD>\n<PATH>\n<TIMESTAMP>\n<SHA256_HEX(BODY)>
```

- `METHOD` uppercase (`POST`, `GET`).
- `PATH` is the URL path only, no host, no query string (e.g. `/v1/cleanup`).
- `TIMESTAMP` is exactly the `X-Gobbl-Timestamp` header value.
- `SHA256_HEX(BODY)` is lowercase hex of SHA-256 over the **exact bytes sent** as the body. For `GET` (empty body) that is
  `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`. Sign the same `Data` you send — do not re-encode the JSON after signing.

Each `(timestamp, signature)` pair is accepted **once** (remembered for 150 s). With deterministic (RFC 8032) signers, two identical requests in the
same second produce the same signature and the second gets `401 replay`, so don't retry an identical request within the same second. Apple's
CryptoKit randomises its Ed25519 signatures, so the Gobbl app doesn't hit this, but a replayed captured request still does.

Signature failures return `401 {"error":"unauthorized","reason":"bad_install"|"unknown_install"|"bad_timestamp"|"stale_timestamp"|"missing_signature"|"bad_signature"|"replay"}`.
`stale_timestamp` usually means the Mac clock is wrong. `unknown_install` means re-register. `403 {"error":"revoked"}` means this install is blocked.

### Worked example (test key — never use in production)

Private key seed (32 bytes, hex): `0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20`
Public key (base64): `ebVWLo/mVPlAeLES6KmLp5AfhTrmlb7X4OORC60ElmQ=`
Timestamp: `1789430400` (2026-09-15 00:00 UTC = 05:30 IST)

Body (exact bytes):

```
{"transcript":"um so I think we should uh ship it friday","style":"light","app":"Slack","locale":"en-US"}
```

SHA-256 hex: `992d23a73ff9f269724343d89c38532f5ff6474d41f2fa8fcba3f4f7d4af6926`

Canonical string (shown with real newlines):

```
POST
/v1/cleanup
1789430400
992d23a73ff9f269724343d89c38532f5ff6474d41f2fa8fcba3f4f7d4af6926
```

`X-Gobbl-Signature`: `pP5W4jFxbSaI9+hfeQsw3dkxGgoIOI6U7FbdAZmlXO81J2fVz+rYdvZCY0wiGr8n3p5vN+8b/r3kWw2e14qdBQ==`

For `GET /v1/quota` at the same timestamp, the canonical string is `GET\n/v1/quota\n1789430400\ne3b0c442…b855` and the signature is
`qyASmwkW2hH9ZhqDmDbLhJ4Grq+cFUijogFskGtSNt6De2C9Xnz2HK22+FtRRftGSiAN85v22H/HmoJ5G4+WAQ==`.

(Both vectors are checked in `test/auth.test.ts`. A deterministic RFC 8032 signer reproduces them exactly. Apple's CryptoKit adds randomness,
so the Swift client produces different bytes that still verify: the app's `GobblKeyAndAITests.swift` checks the same public key and canonical
string, and that these vectors verify under that key.
The signing vector body uses the legacy `transcript` field, which `/v1/cleanup` still accepts; signing doesn't care about body content.)

Swift sketch:

```swift
let key = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
let bodyHash = SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined()
let canonical = "\(method)\n\(path)\n\(ts)\n\(bodyHash)"
let sig = try key.signature(for: Data(canonical.utf8)).base64EncodedString()
```

## 3. Endpoints

Common rules: `locale` is optional and BCP-47-ish (`en`, `en-IN`, `pt_BR`); anything else → `400 invalid_locale`.
Short metadata (`app`, `windowTitle`) is truncated to 200 chars; `url` to 500. Bodies over 64 KB → 413.

### `GET /v1/quota` (signed, empty body)

```json
{
  "remaining": 37, "actionsRemaining": 37, "actionsLimit": 40, "actionsUsed": 3,
  "backgroundRemaining": 14, "backgroundLimit": 16, "backgroundUsed": 2,
  "usdRemaining": 0.0491, "resetsAt": "2026-09-15T00:00:00.000Z"
}
```

Does not consume an action. Quotas reset at **00:00 UTC** (05:30 IST).

#### Quota classes

| Class | Endpoints | Daily limit per install | When the global budget runs low |
|---|---|---|---|
| actions | write, edit, cleanup, chat, brief | `DAILY_ACTIONS` (40) | `503 {"error":"paused"}` once global spend reaches **100%** of `GLOBAL_DAILY_USD` |
| background | extract, digest | `DAILY_BACKGROUND` (16) | `503 {"error":"paused","reason":"background"}` once global spend reaches **80%** |

- The two counters are independent: running out of one never blocks the other. Exhausted background quota →
  `429 {"error":"quota","reason":"background","resetsAt":…}`.
- The per-install dollar cap (`DAILY_USD_CAP`, $0.05) is shared by both classes (`429 … "reason":"usd"`).
- A call whose upstream request fails outright is refunded to its own class. A degraded extract/digest (see below) still counts: tokens were spent.
- Background work should be deferrable. On `paused` with `reason: "background"`, retry after the `retry-after` (3600 s) or the next UTC day;
  user features keep working meanwhile.

### `POST /v1/write` → SSE

```json
{
  "mode": "instruction" | "rewrite" | "draft" | "answer",
  "text": "…",
  "selection": "… (optional)",
  "context": { "app": "Mail", "windowTitle": "Re: lunch", "url": "https://… (optional)", "nearbyText": "text around the cursor" },
  "locale": "en-US"
}
```

| mode | input | output |
|---|---|---|
| `instruction` | `text` is an instruction ("email Sam that I'm late"); `selection` optional | the finished text that replaces the instruction |
| `rewrite` | `selection` (or `text` if no selection) | the rewritten selection |
| `draft` | `text` usually empty; `nearbyText` holds the message/thread | a reply drafted from `nearbyText` |
| `answer` | `text` is a question | the answer |

Optional `tone`: `neutral|friendly|formal|casual|concise|confident|warm|professional`. `nearbyText` is truncated to 3000 chars.
`text + selection + nearbyText` over **12 000** chars → 413. Empty input for the mode → `400 empty_input`. Max output 800 tokens.

### `POST /v1/edit` → SSE

```json
{ "text": "Hey team, the build is broke again", "instruction": "make it professional", "context": { "app": "Slack", "windowTitle": "#eng", "url": null }, "locale": "en-US" }
```

Applies `instruction` to `text` and streams **only the revised text** (the full text, not a diff). `text + instruction` over 12 000 chars → 413.
Max output 1200 tokens.

### `POST /v1/cleanup` → SSE

```json
{ "text": "um so yeah lets uh meet at five no six", "app": "Slack", "bundleId": "com.tinyspeck.slackmacgap", "locale": "en-US" }
```

Polishes dictated text for the target app. The server works out the app type (email, chat, code or terminal) from `bundleId`/`app` and matches its conventions.
Keeps the speaker's meaning and their own words, never adds content, and never answers or carries out what was dictated. Optional `style`: `"polish"` (default)
or `"light"` (only fillers and punctuation); optional `accent` (locale-like). `text` over 12 000 chars → 413. Max output 1200 tokens. The legacy field name `transcript` is still accepted in place of `text`.

### `POST /v1/chat` → SSE

```json
{
  "messages": [ { "role": "user", "content": "what's my next meeting?" } ],
  "context": {
    "now": "2026-09-14T09:05:00+05:30",
    "timezone": "Asia/Kolkata",
    "calendar":  [ { "title": "Standup", "start": "2026-09-14T09:30:00+05:30", "end": "2026-09-14T09:45:00+05:30", "location": "Zoom" } ],
    "reminders": [ { "text": "Pay rent", "due": "2026-09-14" } ],
    "agents":    [ { "project": "gobbl", "state": "running" } ],
    "focus":     { "running": false, "completedToday": 2 },
    "memory":    [ { "source": "WhatsApp · Samar · Sat 6 PM", "text": "Dinner at Toit on Friday, 8 PM. I'll book the table." } ]
  },
  "locale": "en-IN"
}
```

- `messages`: 1 to 12 turns, roles `user` or `assistant` only, and the **last must be `user`**. More than 12 → only the last 12 are kept.
  Each `content` is truncated to 4000 chars. If the total goes over 12 000, the oldest turns are dropped.
- `context`: all fields optional and parsed leniently (malformed entries are dropped). Up to 20 calendar items, 20 reminders and 10 agents are used,
  rendered server-side into about **2000 chars** (the rest is truncated).
- `context.memory` (optional): snippets the app recalled locally, `[{ "source": string, "text": string }]`. Parsed leniently: malformed entries
  are dropped, `source` is truncated to 80 chars and `text` to 600, at most **12** items are used, and the list stops at **3000** chars of
  `source + text` in total (the item that crosses the line is shortened to fit, with a trailing `…`). A missing `source` becomes `"memory"`.
  It is sent to the model as a delimited `<memory>` block, one `- [source] text` line per item (line breaks inside `text` become spaces).
  The model answers from memory when relevant and **cites sources inline exactly as given**, e.g. `[WhatsApp · Samar · Sat 6 PM]`.
  Match citations by the literal source string; `[` and `]` inside a source are rewritten to `(` and `)` so a citation can't be spoofed. The model
  is told never to invent memories and to treat memory text as data, not instructions.
- The system prompt is server-side ("You are Gobbl, a friendly and concise Mac notch assistant…"). Replies are short: plain text or simple Markdown
  (bold, bullets), no headings. Max output 500 tokens.

### `POST /v1/brief` → SSE

```json
{ "kind": "morning" | "evening", "context": { …same shape as chat… }, "yesterday": "optional short summary", "locale": "en-IN" }
```

(`yesterday` may also sit inside `context`; it is truncated to 1000 chars.)

`context` may also carry:

- `memory`: same shape and caps as in chat. The brief may mention a clearly relevant item, with its `[source]`.
- `todos`: open to-dos, `[{ "title": string, "due"?: string }]`. At most **10** are used; `title` is truncated to 160 chars and `due` to 40
  (any string, ISO preferred). Entries without a title are dropped. The morning brief lists those due soonest; the evening wrap-up lists the ones still open.

```json
{ "kind": "morning", "context": { "now": "…", "calendar": [], "todos": [ { "title": "Complete KSRTC booking", "due": "2026-09-15T17:00:00+05:30" } ], "memory": [] } }
```

- `morning`: 5 to 8 lines covering today's meetings, open reminders and a one-line nudge.
- `evening`: what got done (focus sessions, finished agent tasks), what is still open, and the first thing for tomorrow.

The output is plain text lines, each starting with `"- "`, with no preamble. Max output 400 tokens.

### `POST /v1/extract` → JSON (background)

The app sends batches of text captured on screen and gets back structured to-dos, entities, relations and facts.

```json
{
  "batch": [
    { "ref": "c1", "app": "WhatsApp", "chat": "Samar", "kind": "message", "sender": "Samar", "fromMe": false,
      "time": "2026-09-14T17:40:00+05:30", "text": "Can you send the deck by Friday?" },
    { "ref": "c2", "app": "Google Chrome", "window": "KSRTC – Review booking", "url_domain": "ksrtc.in", "kind": "text",
      "text": "Review your booking · Bengaluru → Mysuru · Proceed to payment" }
  ],
  "known": { "people": ["Samar Rao"], "projects": ["Gobbl"] },
  "now": "2026-09-14T18:00:00+05:30",
  "timezone": "Asia/Kolkata",
  "locale": "en-IN"
}
```

Request rules:

| Field | Rule |
|---|---|
| `batch` | 1 to **120** items (more → `413`). Empty or not an array → `400 invalid_batch`. |
| `batch[].ref` | Required. 1 to 40 chars with no control characters or `<` `>`, **unique** in the batch. Otherwise → `400 invalid_ref`. Refs are echoed back verbatim. |
| `batch[].app`, `.text` | Required strings (`400 invalid_batch`). `app` is truncated to 80 chars. Items whose `text` is blank are skipped, but their ref still counts as known. |
| `batch[].kind` | `"text"`, `"message"` or `"mail"`. Anything else → `400 invalid_kind`. |
| `window`, `chat`, `url_domain`, `sender`, `time` | Optional strings, truncated (window 200, others 120, time 40). |
| `fromMe` | Optional boolean. `true` = the user wrote it; this matters for commitments. |
| total `text` | Sum over the whole batch at most **6000** chars, otherwise `413 too_large`. All blank → `400 empty_input`. |
| `known.people`, `known.projects` | Optional, lenient: the first 200 strings are used, each truncated to 80 chars, non-strings dropped. |
| `now` | Required ISO-8601 date-time (`400 invalid_now`). Relative deadlines are resolved against it. |
| `timezone`, `locale` | Optional. |

Response `200`:

```json
{
  "todos": [
    { "title": "Send the deck to Samar", "reason": "Samar asked: \"Can you send the deck by Friday?\"", "source_ref": "c1",
      "confidence": 0.85, "due": "2026-09-18T23:59:00+05:30", "people": ["Samar Rao"],
      "done_signal": { "type": "file_sent", "pattern": "deck" } },
    { "title": "Complete KSRTC booking", "reason": "Bengaluru → Mysuru booking left at the payment step", "source_ref": "c2",
      "confidence": 0.8, "due": null, "people": [],
      "done_signal": { "type": "page_contains", "pattern": "booking confirmed|payment successful" } }
  ],
  "entities": [
    { "type": "person", "name": "Samar Rao", "aliases": ["Samar"], "identifiers": [], "role": null, "org": null, "evidence_ref": "c1" }
  ],
  "relations": [],
  "facts": [],
  "degraded": false
}
```

Every key is always present; `due`, `role` and `org` are `null` when unknown. Guarantees, enforced server-side whatever the model returns:

| List (max) | Item | Guarantees |
|---|---|---|
| `todos` (15) | `title` ≤80, `reason` ≤160, `source_ref`, `confidence`, `due`, `people` (≤10 names, each ≤80), `done_signal` | `source_ref` is a ref from the request. `confidence` is 0 to 1 (0.5 if the model omitted it). `due` is a parseable ISO date or `null`. Titles are unique (case-insensitive). |
| `entities` (40) | `type`, `name` ≤80, `aliases` (≤10), `identifiers` (≤10 of `{type, value ≤200}`), `role` ≤80 or null, `org` ≤80 or null, `evidence_ref` | `type` is one of `person`, `project`, `org`, `topic`, `tool`. `identifiers[].type` is one of `email`, `phone`, `handle`, `url`. Unique per `(type, name)`. |
| `relations` (40) | `a`, `b` (≤80), `kind`, `evidence_ref` | `kind` is one of `works_at`, `member_of`, `talks_with`, `about`. `a` ≠ `b`. |
| `facts` (40) | `entity` ≤80, `key` ≤60 (snake_case suggested), `value` ≤200 (always a string), `evidence_ref`, `confidence` 0 to 1 | |

Items with an unknown ref or type are dropped, not repaired. Over-long strings are cut with a trailing `…`.

`done_signal.type` and what the app should check locally. `pattern` is plain text of at most 120 chars, **not a regex**; match it case-insensitively.

| `type` | Done when | `pattern` |
|---|---|---|
| `reply_to` | the user replies in that chat | the chat or person name |
| `page_contains` | a page or window shows one of the phrases | phrases separated by `\|`, e.g. `booking confirmed\|payment successful` |
| `message_sent` | the user sends a message containing one of the phrases | phrases separated by `\|` |
| `file_sent` | the user sends a file whose name contains the pattern | a file name fragment |
| `none` | nothing checkable | `""` (always empty) |

A known type that comes back with an empty pattern is downgraded to `none`.

What the model is told: extract only the **user's** to-dos. These come from commitments the user made (`fromMe`), requests aimed at the user,
unfinished flows (a booking or checkout left before confirmation, an unsent draft), `TODO:` lines, and promises other people made to the user
(phrased as a follow-up). Deadlines attached to any of these are included. It skips news, feeds, ads and other people's tasks, and never invents.
It takes roles and orgs only from explicit evidence (a signature or profile header). Captured text goes into delimited `<item>` blocks and is
treated as data: text that tries to issue instructions is ignored.

**Degraded result.** If the model's output isn't a usable JSON object, the server retries once on the fallback model. If that also fails, the
response is still `200`, with empty lists and `"degraded": true`:

```json
{ "todos": [], "entities": [], "relations": [], "facts": [], "degraded": true }
```

Treat it as "nothing extracted this time". It counts against the background quota. If the first upstream call fails outright, you get the usual
`502`/`503 {"error":"upstream"}` and the call is refunded. Max output 900 tokens.

### `POST /v1/digest` → JSON (background)

```json
{
  "day": "2026-09-14",
  "parts": [
    { "part": "morning", "segments": [
      { "app": "Google Chrome", "url_domain": "wanderlog.com", "minutes": 41, "summary": "Built a 5-day UK trip itinerary: London, Bath, Edinburgh" },
      { "app": "Slack", "chat": "#design", "minutes": 18, "summary": "Discussed onboarding screens with Priya" }
    ] },
    { "part": "evening", "segments": [ { "app": "Instagram", "minutes": 25, "summary": "Browsed reels" } ] }
  ],
  "locale": "en-IN"
}
```

| Field | Rule |
|---|---|
| `day` | `YYYY-MM-DD`, otherwise `400 invalid_day`. |
| `parts` | 1 to 3 entries. `part` is `morning`, `afternoon` or `evening`, each at most once, otherwise `400 invalid_parts`. They are returned in day order whatever the input order. |
| `segments` | At most **40** per part (more → `413`). Each needs `app` (string, truncated to 80), `summary` (string, truncated to 300) and `minutes` (number ≥ 0, rounded). Otherwise → `400 invalid_segment`. `window`, `chat` and `url_domain` are optional. |
| total | All strings (`app`, `window`, `chat`, `url_domain`, `summary`) together at most **8000** chars, otherwise `413`. A request whose parts all have no segments → `400 empty_input`. |

Response `200`:

```json
{
  "parts": [
    { "part": "morning", "bullets": ["Planned the UK trip itinerary on Wanderlog", "Talked through the onboarding screens with Priya"], "apps": ["Google Chrome", "Slack"] },
    { "part": "evening", "bullets": ["Caught up on Instagram"], "apps": ["Instagram"] }
  ],
  "degraded": false
}
```

- The response only includes parts that were in the request and for which the model wrote at least one bullet (so a part can be missing).
- `bullets`: 1 to 3, each ≤160 chars, phrased as outcomes (never "spent 41 min in Chrome"), in a neutral tone with no judgement of social-media time.
- `apps`: up to 8, always spelled **exactly as in that part's input**. Names the model made up are dropped. If none are left, the part's input apps are used, ordered by minutes.
- Degraded: same retry rule as extract. The response is `{"parts": [], "degraded": true}`. Max output 600 tokens.

### `GET /health` (unsigned) → `{"ok":true}`

## 4. Streaming format (write / edit / cleanup / chat / brief — not extract / digest)

`200`, `content-type: text/event-stream`. Events are separated by a blank line; each has one `event:` and one `data:` line with JSON:

```
event: delta
data: {"text":"Sure — "}

event: delta
data: {"text":"Friday works."}

event: done
data: {}

```

- Concatenate every `delta.text` in order; that is the result. Each `data` line is complete JSON.
- Exactly one terminal event: `done` (`data: {}`) **or** `error`:

```
event: error
data: {"message":"Provider disconnected"}

```

On `error`, discard or keep the partial text at the UI's discretion (an error with no deltas does not consume an action).
If the connection closes with no terminal event, treat it as an error.

## 5. Pre-stream errors (JSON)

| Status | Body | Meaning |
|---|---|---|
| 400 | `{"error":"invalid_mode"\|"invalid_style"\|"invalid_kind"\|"invalid_messages"\|"invalid_instruction"\|"invalid_locale"\|"invalid_context"\|"empty_input"\|"invalid_body"\|"invalid_batch"\|"invalid_ref"\|"invalid_now"\|"invalid_day"\|"invalid_parts"\|"invalid_segment"…}` | bad request |
| 401 | `{"error":"unauthorized","reason":…}` | bad or missing signature; see §2 |
| 403 | `{"error":"revoked"}` | install blocked |
| 413 | `{"error":"too_large"}` | input over caps |
| 429 | `{"error":"quota","reason":"actions"\|"background"\|"usd","resetsAt":"<ISO UTC>"}` | daily quota exhausted (`background` = extract/digest counter) |
| 429 | `{"error":"rate_limited"}` + `retry-after` | throttled (burst limit of 10 requests per 10 s per install, or registration throttle) |
| 502 | `{"error":"upstream","status":…}` | model provider failed (action refunded) |
| 503 | `{"error":"paused"}` + `retry-after` | global daily budget reached; AI is paused for everyone until UTC midnight |
| 503 | `{"error":"paused","reason":"background"}` + `retry-after` | extract/digest only: global spend is at 80% or more of the budget; user features still work |
| 404 / 500 | `{"error":"not_found"}` / `{"error":"internal"}` | |
