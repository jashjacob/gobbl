import { defineConfig } from "vitest/config";

// Plain vitest (Node): tests cover the pure modules only. Node >= 20 ships
// WebCrypto Ed25519, fetch, ReadableStream and TextDecoderStream, so the same
// code paths the Worker runs are exercised. Durable Object classes (which
// import `cloudflare:workers`) are intentionally not imported by tests.
export default defineConfig({
  test: {
    include: ["test/**/*.test.ts"],
    environment: "node",
  },
});
