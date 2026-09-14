import { DurableObject } from "cloudflare:workers";
import { ReplayGuard } from "./auth";
import type { Env } from "./config";
import {
  type GlobalState,
  type InstallLimits,
  type InstallState,
  remainingInstall,
  reserveGlobal,
  reserveInstall,
  settleGlobal,
  settleInstall,
} from "./quota";

/**
 * One instance per installId. Holds the replay window and the daily counters.
 * Each method does get → compute → put with no other I/O in between, so the DO
 * input gate makes it atomic with respect to concurrent requests.
 */
export class InstallQuota extends DurableObject<Env> {
  /** true = replay (reject). */
  async checkReplay(key: string, nowS: number): Promise<boolean> {
    const guard = new ReplayGuard((await this.ctx.storage.get<Record<string, number>>("replay")) ?? {});
    const seen = guard.seen(key, nowS);
    if (!seen) await this.ctx.storage.put("replay", guard.entries);
    return seen;
  }

  async reserve(limits: InstallLimits, estUsd: number, nowMs: number) {
    const r = reserveInstall(await this.ctx.storage.get<InstallState>("state"), limits, estUsd, nowMs);
    if (r.ok) await this.ctx.storage.put("state", r.state);
    return r.ok
      ? { ok: true as const, day: r.day, resetsAt: r.resetsAt }
      : { ok: false as const, reason: r.reason, resetsAt: r.resetsAt };
  }

  async settle(day: string, reservedUsd: number, actualUsd: number, refundAction: boolean, nowMs: number) {
    const s = settleInstall(
      await this.ctx.storage.get<InstallState>("state"),
      day,
      reservedUsd,
      actualUsd,
      refundAction,
      nowMs,
    );
    await this.ctx.storage.put("state", s);
  }

  async status(limits: InstallLimits, nowMs: number) {
    return remainingInstall(await this.ctx.storage.get<InstallState>("state"), limits, nowMs);
  }
}

/** Single instance ("global"): daily $ circuit breaker across all installs. */
export class GlobalBudget extends DurableObject<Env> {
  async reserve(capUsd: number, estUsd: number, nowMs: number) {
    const r = reserveGlobal(await this.ctx.storage.get<GlobalState>("state"), capUsd, estUsd, nowMs);
    if (r.ok) await this.ctx.storage.put("state", r.state);
    return r.ok ? { ok: true as const, day: r.day } : { ok: false as const };
  }

  async settle(day: string, reservedUsd: number, actualUsd: number, nowMs: number) {
    const s = settleGlobal(await this.ctx.storage.get<GlobalState>("state"), day, reservedUsd, actualUsd, nowMs);
    await this.ctx.storage.put("state", s);
  }
}
