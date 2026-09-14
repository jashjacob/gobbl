/**
 * Translates OpenRouter's OpenAI-style SSE into Gobbl's simplified SSE:
 *   event: delta\ndata: {"text":"..."}\n\n
 *   event: done\ndata: {"usage":{...}}\n\n
 *   event: error\ndata: {"message":"..."}\n\n
 */

export interface Usage {
  prompt_tokens?: number;
  completion_tokens?: number;
  total_tokens?: number;
  cost?: number;
}

export type OutEvent =
  | { type: "delta"; text: string }
  | { type: "done"; usage: Usage | null }
  | { type: "error"; message: string };

export function formatEvent(e: OutEvent): string {
  const data =
    // `done` carries no data for the client; usage/cost stays server-side for settlement.
    e.type === "delta" ? { text: e.text } : e.type === "done" ? {} : { message: e.message };
  return `event: ${e.type}\ndata: ${JSON.stringify(data)}\n\n`;
}

export interface StreamResult {
  usage: Usage | null;
  errored: boolean;
  outputChars: number;
}

export class OpenRouterSSEParser {
  private buf = "";
  usage: Usage | null = null;
  errored = false;
  finished = false; // done or error emitted
  outputChars = 0;

  /** Feed decoded text; returns events to emit. */
  push(chunk: string): OutEvent[] {
    this.buf += chunk;
    const out: OutEvent[] = [];
    let nl: number;
    while ((nl = this.buf.indexOf("\n")) >= 0) {
      const line = this.buf.slice(0, nl).replace(/\r$/, "");
      this.buf = this.buf.slice(nl + 1);
      this.line(line, out);
    }
    return out;
  }

  /** Upstream closed; flush and guarantee exactly one terminal event. */
  end(): OutEvent[] {
    const out: OutEvent[] = [];
    if (this.buf) this.line(this.buf.replace(/\r$/, ""), out);
    this.buf = "";
    if (!this.finished) {
      this.finished = true;
      out.push({ type: "done", usage: this.usage });
    }
    return out;
  }

  result(): StreamResult {
    return { usage: this.usage, errored: this.errored, outputChars: this.outputChars };
  }

  private fail(message: string, out: OutEvent[]) {
    this.errored = true;
    this.finished = true;
    out.push({ type: "error", message });
  }

  private line(line: string, out: OutEvent[]) {
    if (this.finished) return;
    if (!line || line.startsWith(":")) return; // blank separator or comment (": OPENROUTER PROCESSING")
    if (!line.startsWith("data:")) return; // event:/id:/retry: fields are not used by OpenRouter
    const payload = line.slice(5).trim();
    if (payload === "[DONE]") {
      this.finished = true;
      out.push({ type: "done", usage: this.usage });
      return;
    }
    let obj: any;
    try {
      obj = JSON.parse(payload);
    } catch {
      return; // tolerate a malformed line rather than killing the stream
    }
    if (obj?.usage && typeof obj.usage === "object") this.usage = pickUsage(obj.usage);
    if (obj?.error) {
      const msg = typeof obj.error.message === "string" ? obj.error.message : "upstream_error";
      return this.fail(msg, out);
    }
    const choice = obj?.choices?.[0];
    const text = choice?.delta?.content;
    if (typeof text === "string" && text.length) {
      this.outputChars += text.length;
      out.push({ type: "delta", text });
    }
    if (choice?.finish_reason === "error") this.fail("upstream_error", out);
  }
}

function pickUsage(u: any): Usage {
  const n = (v: unknown) => (typeof v === "number" && Number.isFinite(v) ? v : undefined);
  return { prompt_tokens: n(u.prompt_tokens), completion_tokens: n(u.completion_tokens), total_tokens: n(u.total_tokens), cost: n(u.cost) };
}

/**
 * Pipe an upstream SSE body through the translator. `onFinish` runs once when the
 * upstream ends (normally or with an error). If the client disconnects mid-stream
 * it is called with the partial result as well.
 */
export function translateStream(
  upstream: ReadableStream<Uint8Array>,
  onFinish: (r: StreamResult) => void,
): ReadableStream<Uint8Array> {
  const parser = new OpenRouterSSEParser();
  const enc = new TextEncoder();
  const dec = new TextDecoder();
  const reader = upstream.getReader();
  let called = false;
  const finish = () => {
    if (!called) {
      called = true;
      onFinish(parser.result());
    }
  };
  return new ReadableStream<Uint8Array>({
    async pull(controller) {
      try {
        // Keep reading until we have something to emit: a pull that enqueues nothing
        // (e.g. a chunk holding only ": OPENROUTER PROCESSING") would not be re-invoked.
        for (;;) {
          const { value, done } = await reader.read();
          const events = done ? [...parser.push(dec.decode()), ...parser.end()] : parser.push(dec.decode(value, { stream: true }));
          for (const e of events) controller.enqueue(enc.encode(formatEvent(e)));
          if (done || parser.finished) {
            if (!done) reader.cancel().catch(() => {});
            finish();
            controller.close();
            return;
          }
          if (events.length) return;
        }
      } catch {
        if (!parser.finished) {
          parser.errored = true;
          parser.finished = true;
          controller.enqueue(enc.encode(formatEvent({ type: "error", message: "stream_interrupted" })));
        }
        finish();
        controller.close();
      }
    },
    cancel() {
      reader.cancel().catch(() => {});
      finish();
    },
  });
}
