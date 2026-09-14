import { APP_REFERER, APP_TITLE, JSON_CALL_TIMEOUT_MS, OPENROUTER_URL } from "./config";
import type { ChatMessage } from "./prompts";

export interface BodyOptions {
  /** false = one JSON response with `response_format: json_object` (extract, digest). Default true. */
  stream?: boolean;
  temperature?: number;
}

export function buildOpenRouterBody(messages: ChatMessage[], models: string[], maxTokens: number, opts: BodyOptions = {}) {
  const stream = opts.stream ?? true;
  return {
    model: models[0],
    // OpenRouter tries these in order if the primary errors / is unavailable.
    ...(models.length > 1 ? { models } : {}),
    messages,
    stream,
    ...(stream ? {} : { response_format: { type: "json_object" as const } }),
    max_tokens: maxTokens,
    temperature: opts.temperature ?? 0.3,
    usage: { include: true },
    provider: { data_collection: "deny" },
  };
}

export function callOpenRouter(
  apiKey: string,
  body: ReturnType<typeof buildOpenRouterBody>,
  fetchImpl: typeof fetch = fetch,
  signal?: AbortSignal,
): Promise<Response> {
  return fetchImpl(OPENROUTER_URL, {
    method: "POST",
    headers: {
      authorization: `Bearer ${apiKey}`,
      "content-type": "application/json",
      "HTTP-Referer": APP_REFERER,
      "X-OpenRouter-Title": APP_TITLE,
      "X-Title": APP_TITLE, // older header name, still honoured
    },
    body: JSON.stringify(body),
    signal,
  });
}

type Completion = { ok: true; content: string; cost: number | null } | { ok: false; status: number };

/** One non-streaming call. Transport errors, non-2xx and in-body `error` objects all count as failure. */
async function complete(apiKey: string, body: ReturnType<typeof buildOpenRouterBody>, fetchImpl: typeof fetch): Promise<Completion> {
  let res: Response;
  try {
    res = await callOpenRouter(apiKey, body, fetchImpl, AbortSignal.timeout(JSON_CALL_TIMEOUT_MS));
  } catch (err) {
    console.error("openrouter fetch failed", err);
    return { ok: false, status: 0 };
  }
  if (!res.ok) {
    console.error("openrouter status", res.status, await res.text().catch(() => ""));
    return { ok: false, status: res.status };
  }
  let data: any;
  try {
    data = await res.json();
  } catch {
    return { ok: false, status: 502 };
  }
  if (data?.error) {
    console.error("openrouter error body", data.error?.message);
    return { ok: false, status: 502 };
  }
  const content = data?.choices?.[0]?.message?.content;
  const cost = typeof data?.usage?.cost === "number" && Number.isFinite(data.usage.cost) ? data.usage.cost : null;
  return { ok: true, content: typeof content === "string" ? content : "", cost };
}

export type JsonTaskResult<T> =
  /** The first call failed outright: nothing to bill, refund the reservation. */
  | { kind: "upstream"; status: number }
  | { kind: "ok"; value: T; costUsd: number }
  /** Both attempts came back unusable. Still billed: tokens were spent. */
  | { kind: "degraded"; costUsd: number };

/**
 * Non-streaming JSON task. The first attempt goes to the primary model (with OpenRouter's
 * provider fallback list); if its answer does not parse, one retry goes to the fallback model alone.
 * `unknownCostUsd` is billed for an attempt whose response carried no usage cost.
 */
export async function runJsonTask<T>(
  apiKey: string,
  messages: ChatMessage[],
  models: string[],
  maxTokens: number,
  parse: (content: string) => T | null,
  unknownCostUsd: number,
  fetchImpl: typeof fetch = fetch,
): Promise<JsonTaskResult<T>> {
  const opts = { stream: false, temperature: 0.1 };
  const first = await complete(apiKey, buildOpenRouterBody(messages, models, maxTokens, opts), fetchImpl);
  if (!first.ok) return { kind: "upstream", status: first.status };
  let costUsd = first.cost ?? unknownCostUsd;
  const v1 = parse(first.content);
  if (v1 !== null) return { kind: "ok", value: v1, costUsd };

  const retry = await complete(apiKey, buildOpenRouterBody(messages, [models[models.length - 1]], maxTokens, opts), fetchImpl);
  if (!retry.ok) return { kind: "degraded", costUsd };
  costUsd += retry.cost ?? unknownCostUsd;
  const v2 = parse(retry.content);
  return v2 !== null ? { kind: "ok", value: v2, costUsd } : { kind: "degraded", costUsd };
}
