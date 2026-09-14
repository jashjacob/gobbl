/** Test stand-in for the `cloudflare:workers` module (aliased in vitest.config.ts). */
export class DurableObject<Env = unknown> {
  constructor(
    protected ctx: DurableObjectState,
    protected env: Env,
  ) {}
}
