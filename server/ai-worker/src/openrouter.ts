import { APP_REFERER, APP_TITLE, OPENROUTER_URL } from "./config";
import type { ChatMessage } from "./prompts";

export function buildOpenRouterBody(messages: ChatMessage[], models: string[], maxTokens: number) {
  return {
    model: models[0],
    // OpenRouter tries these in order if the primary errors / is unavailable.
    ...(models.length > 1 ? { models } : {}),
    messages,
    stream: true,
    max_tokens: maxTokens,
    temperature: 0.3,
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
