import { describe, expect, it, vi } from "vitest";
import { modelsFrom } from "../src/config";
import { buildOpenRouterBody, callOpenRouter } from "../src/openrouter";
import { buildCleanupMessages } from "../src/prompts";
import { translateStream } from "../src/sse";

describe("OpenRouter call (mocked fetch)", () => {
  it("sends the right URL, headers and body, and the stream translates end-to-end", async () => {
    const sse =
      ": OPENROUTER PROCESSING\n\n" +
      `data: ${JSON.stringify({ choices: [{ delta: { content: "Hi there." }, finish_reason: "stop" }] })}\n\n` +
      `data: ${JSON.stringify({ choices: [], usage: { prompt_tokens: 10, completion_tokens: 3, total_tokens: 13, cost: 0.00002 } })}\n\n` +
      "data: [DONE]\n\n";
    const fetchMock = vi.fn(async (_url: string, _init: RequestInit) =>
      new Response(sse, { headers: { "content-type": "text/event-stream" } }),
    );

    const body = buildOpenRouterBody(buildCleanupMessages({ text: "um hi there", style: "light" }), modelsFrom({}), 1200);
    const res = await callOpenRouter("sk-test", body, fetchMock as unknown as typeof fetch);

    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe("https://openrouter.ai/api/v1/chat/completions");
    const h = init.headers as Record<string, string>;
    expect(h.authorization).toBe("Bearer sk-test");
    expect(h["HTTP-Referer"]).toBe("https://gobbl.xeve.io");
    expect(h["X-OpenRouter-Title"]).toBe("Gobbl");
    const sent = JSON.parse(init.body as string);
    expect(sent).toMatchObject({
      model: "google/gemini-2.5-flash-lite",
      models: ["google/gemini-2.5-flash-lite", "openai/gpt-4.1-nano"],
      stream: true,
      max_tokens: 1200,
      provider: { data_collection: "deny" },
      usage: { include: true },
    });
    expect(sent.messages[0].role).toBe("system");

    let cost: number | undefined;
    const out = await new Response(translateStream(res.body!, (r) => (cost = r.usage?.cost))).text();
    expect(out).toBe(
      'event: delta\ndata: {"text":"Hi there."}\n\nevent: done\ndata: {}\n\n',
    );
    expect(cost).toBe(0.00002);
  });
});
