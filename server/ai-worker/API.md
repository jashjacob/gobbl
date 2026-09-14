# Gobbl AI API — client contract (v1)

Base URL: `https://ai.xeve.io`. All request bodies are UTF-8 JSON (`content-type: application/json`).
Errors that happen **before** a stream starts are JSON with an HTTP status. Once a `200 text/event-stream`
response has started, failures arrive as an `error` SSE event.

| Endpoint | Signed | Response | Counts as an action |
|---|---|---|---|
| `POST /v1/register` | no | JSON | – |
| `GET /v1/quota` | yes | JSON | no |
| `POST /v1/write` | yes | SSE | yes |
| `POST /v1/edit` | yes | SSE | yes |
| `POST /v1/cleanup` | yes | SSE | yes |
| `POST /v1/chat` | yes | SSE | yes |
| `POST /v1/brief` | yes | SSE | yes |
| `GET /health` | no | JSON | – |

Every text endpoint returns **only the result text** — no preamble, no surrounding quotes.

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
{ "remaining": 37, "actionsRemaining": 37, "actionsLimit": 40, "actionsUsed": 3, "usdRemaining": 0.0491, "resetsAt": "2026-09-15T00:00:00.000Z" }
```

Does not consume an action. Quotas reset at **00:00 UTC** (05:30 IST).

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
    "focus":     { "running": false, "completedToday": 2 }
  },
  "locale": "en-IN"
}
```

- `messages`: 1 to 12 turns, roles `user` or `assistant` only, and the **last must be `user`**. More than 12 → only the last 12 are kept.
  Each `content` is truncated to 4000 chars. If the total goes over 12 000, the oldest turns are dropped.
- `context`: all fields optional and parsed leniently (malformed entries are dropped). Up to 20 calendar items, 20 reminders and 10 agents are used,
  rendered server-side into about **2000 chars** (the rest is truncated).
- The system prompt is server-side ("You are Gobbl, a friendly and concise Mac notch assistant…"). Replies are short: plain text or simple Markdown
  (bold, bullets), no headings. Max output 500 tokens.

### `POST /v1/brief` → SSE

```json
{ "kind": "morning" | "evening", "context": { …same shape as chat… }, "yesterday": "optional short summary", "locale": "en-IN" }
```

(`yesterday` may also sit inside `context`; it is truncated to 1000 chars.)

- `morning`: 5 to 8 lines covering today's meetings, open reminders and a one-line nudge.
- `evening`: what got done (focus sessions, finished agent tasks), what is still open, and the first thing for tomorrow.

The output is plain text lines, each starting with `"- "`, with no preamble. Max output 400 tokens.

### `GET /health` (unsigned) → `{"ok":true}`

## 4. Streaming format (write / edit / cleanup / chat / brief)

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
| 400 | `{"error":"invalid_mode"\|"invalid_style"\|"invalid_kind"\|"invalid_messages"\|"invalid_instruction"\|"invalid_locale"\|"invalid_context"\|"empty_input"\|"invalid_body"…}` | bad request |
| 401 | `{"error":"unauthorized","reason":…}` | bad or missing signature; see §2 |
| 403 | `{"error":"revoked"}` | install blocked |
| 413 | `{"error":"too_large"}` | input over caps |
| 429 | `{"error":"quota","reason":"actions"\|"usd","resetsAt":"<ISO UTC>"}` | daily quota exhausted |
| 429 | `{"error":"rate_limited"}` + `retry-after` | throttled (burst limit of 10 requests per 10 s per install, or registration throttle) |
| 502 | `{"error":"upstream","status":…}` | model provider failed (action refunded) |
| 503 | `{"error":"paused"}` + `retry-after` | global daily budget reached; AI is paused for everyone until UTC midnight |
| 404 / 500 | `{"error":"not_found"}` / `{"error":"internal"}` | |
