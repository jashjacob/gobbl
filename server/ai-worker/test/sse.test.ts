import { describe, expect, it } from "vitest";
import { OpenRouterSSEParser, type StreamResult, formatEvent, translateStream } from "../src/sse";

const chunk = (content: string, finish: string | null = null) =>
  `data: ${JSON.stringify({ id: "gen-1", choices: [{ index: 0, delta: { content }, finish_reason: finish }] })}\n\n`;
const usageChunk = `data: ${JSON.stringify({ id: "gen-1", choices: [{ index: 0, delta: {}, finish_reason: null }], usage: { prompt_tokens: 50, completion_tokens: 7, total_tokens: 57, cost: 0.0000123 } })}\n\n`;

function streamOf(parts: string[]): ReadableStream<Uint8Array> {
  const enc = new TextEncoder();
  return new ReadableStream({
    start(c) {
      for (const p of parts) c.enqueue(enc.encode(p));
      c.close();
    },
  });
}

async function collect(parts: string[]) {
  let result: StreamResult | undefined;
  const text = await new Response(translateStream(streamOf(parts), (r) => (result = r))).text();
  return { text, result: result! };
}

describe("SSE translation", () => {
  it("formats our events", () => {
    expect(formatEvent({ type: "delta", text: "hi" })).toBe('event: delta\ndata: {"text":"hi"}\n\n');
    expect(formatEvent({ type: "error", message: "x" })).toBe('event: error\ndata: {"message":"x"}\n\n');
  });

  it("passes deltas, skips processing comments, reports usage + cost on done", async () => {
    const { text, result } = await collect([
      ": OPENROUTER PROCESSING\n\n",
      chunk("Hello"),
      ": OPENROUTER PROCESSING\n\n",
      chunk(", world", "stop"),
      usageChunk,
      "data: [DONE]\n\n",
    ]);
    expect(text).toBe(
      'event: delta\ndata: {"text":"Hello"}\n\n' +
        'event: delta\ndata: {"text":", world"}\n\n' +
        "event: done\ndata: {}\n\n",
    );
    expect(result).toEqual({ usage: { prompt_tokens: 50, completion_tokens: 7, total_tokens: 57, cost: 0.0000123 }, errored: false, outputChars: 12 });
  });

  it("handles lines split across network chunks and CRLF", async () => {
    const full = chunk("Grüße").replace(/\n/g, "\r\n");
    const { text } = await collect([full.slice(0, 17), full.slice(17), "data: [DONE]\r\n\r\n"]);
    expect(text).toContain('event: delta\ndata: {"text":"Grüße"}');
    expect(text).toMatch(/event: done/);
  });

  it("treats an in-stream error object as failure and stops", async () => {
    const err = `data: ${JSON.stringify({ id: "gen-1", error: { code: 502, message: "Provider disconnected" }, choices: [{ index: 0, delta: { content: "" }, finish_reason: "error" }] })}\n\n`;
    const { text, result } = await collect([chunk("Par"), err, chunk("ignored"), "data: [DONE]\n\n"]);
    expect(text).toBe('event: delta\ndata: {"text":"Par"}\n\nevent: error\ndata: {"message":"Provider disconnected"}\n\n');
    expect(result.errored).toBe(true);
    expect(text).not.toContain("ignored");
    expect(text).not.toContain("event: done");
  });

  it("treats finish_reason error without error object as failure", () => {
    const p = new OpenRouterSSEParser();
    const ev = p.push(chunk("", "error"));
    expect(ev).toEqual([{ type: "error", message: "upstream_error" }]);
  });

  it("emits done even when upstream closes without [DONE]", async () => {
    const { text, result } = await collect([chunk("ok")]);
    expect(text.endsWith("event: done\ndata: {}\n\n")).toBe(true);
    expect(result.usage).toBeNull();
  });
});
