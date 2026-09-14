import { fileURLToPath } from "node:url";
import { defineConfig } from "vitest/config";

// Plain vitest (Node): Node >= 20 ships WebCrypto Ed25519, fetch, ReadableStream
// and TextDecoderStream, so the same code paths the Worker runs are exercised.
// `cloudflare:workers` is aliased to a tiny stub so the Durable Object classes and
// the fetch handler can be driven end-to-end in test/worker.test.ts with in-memory storage.
export default defineConfig({
  resolve: {
    alias: { "cloudflare:workers": fileURLToPath(new URL("./test/stubs/cloudflare-workers.ts", import.meta.url)) },
  },
  test: {
    include: ["test/**/*.test.ts"],
    environment: "node",
  },
});
