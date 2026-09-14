import { describe, expect, it } from "vitest";
import { estimateCostUsd, limitsFrom, modelsFrom } from "../src/config";
import { remainingInstall, reserveGlobal, reserveInstall, settleGlobal, settleInstall } from "../src/quota";

const T = Date.UTC(2026, 8, 14, 10, 0, 0); // 2026-09-14 10:00Z
const limits = { dailyActions: 3, dailyUsd: 0.01 };

describe("install quota", () => {
  it("reserves until actions exhausted, with resetsAt = next UTC midnight", () => {
    let s = undefined as any;
    for (let i = 0; i < 3; i++) {
      const r = reserveInstall(s, limits, 0.001, T);
      expect(r.ok).toBe(true);
      s = r.state;
    }
    const r = reserveInstall(s, limits, 0.001, T);
    expect(r).toMatchObject({ ok: false, reason: "actions", resetsAt: "2026-09-15T00:00:00.000Z" });
    expect(remainingInstall(s, limits, T).actionsRemaining).toBe(0);
  });

  it("enforces the $ cap including the reservation", () => {
    const a = reserveInstall(undefined, limits, 0.006, T);
    expect(a.ok).toBe(true);
    const b = reserveInstall(a.state, limits, 0.006, T);
    expect(b).toMatchObject({ ok: false, reason: "usd" });
  });

  it("settle replaces the reservation with actual cost", () => {
    const r = reserveInstall(undefined, limits, 0.004, T);
    if (!r.ok) throw new Error();
    const s = settleInstall(r.state, r.day, 0.004, 0.0001, false, T + 1000);
    expect(s.actions).toBe(1);
    expect(s.usd).toBeCloseTo(0.0001, 10);
  });

  it("settle with refund gives the action back and never goes negative", () => {
    const r = reserveInstall(undefined, limits, 0.004, T);
    if (!r.ok) throw new Error();
    const s = settleInstall(r.state, r.day, 0.004, 0, true, T);
    expect(s).toEqual({ day: "2026-09-14", actions: 0, usd: 0 });
  });

  it("resets at UTC midnight and ignores settles for yesterday's reservation", () => {
    const late = Date.UTC(2026, 8, 14, 23, 59, 59);
    let s: any;
    for (let i = 0; i < 3; i++) s = (reserveInstall(s, limits, 0.001, late) as any).state;
    expect(reserveInstall(s, limits, 0.001, late).ok).toBe(false);
    const next = Date.UTC(2026, 8, 15, 0, 0, 1);
    const r = reserveInstall(s, limits, 0.001, next);
    expect(r).toMatchObject({ ok: true, day: "2026-09-15", resetsAt: "2026-09-16T00:00:00.000Z" });
    const settled = settleInstall(r.state, "2026-09-14", 0.001, 0.5, false, next);
    expect(settled).toEqual(r.state);
    expect(remainingInstall(s, limits, next).actionsRemaining).toBe(3);
  });
});

describe("global budget", () => {
  it("pauses when the day's budget would be exceeded and resets next day", () => {
    const a = reserveGlobal(undefined, 1, 0.9, T);
    expect(a.ok).toBe(true);
    const b = reserveGlobal(a.state, 1, 0.2, T);
    expect(b.ok).toBe(false);
    const settled = settleGlobal(a.state, a.ok ? a.day : "", 0.9, 0.1, T);
    expect(settled.usd).toBeCloseTo(0.1, 10);
    expect(reserveGlobal(settled, 1, 0.2, T).ok).toBe(true);
    expect(reserveGlobal(b.state, 1, 0.2, Date.UTC(2026, 8, 15)).ok).toBe(true);
  });
});

describe("config", () => {
  it("parses env limits with defaults", () => {
    expect(limitsFrom({})).toEqual({ dailyActions: 40, dailyUsd: 0.05, globalDailyUsd: 20, registrationsPerPrefixPerDay: 20 });
    expect(limitsFrom({ DAILY_ACTIONS: "5", DAILY_USD_CAP: "bogus" }).dailyActions).toBe(5);
    expect(limitsFrom({ DAILY_USD_CAP: "bogus" }).dailyUsd).toBe(0.05);
  });

  it("forces models through the allowlist", () => {
    expect(modelsFrom({})).toEqual(["google/gemini-2.5-flash-lite", "openai/gpt-4.1-nano"]);
    expect(modelsFrom({ MODEL: "anthropic/claude-opus-4", FALLBACK_MODEL: "x/y" })).toEqual([
      "google/gemini-2.5-flash-lite",
      "openai/gpt-4.1-nano",
    ]);
  });

  it("a full day of typical actions fits the default $ cap; one max-size reservation stays small", () => {
    // Reservations are worst-case and are replaced by the real cost on settle.
    expect(estimateCostUsd(3_000, 800) * 40).toBeLessThan(0.05);
    expect(estimateCostUsd(12_000, 1200)).toBeLessThan(0.002);
  });
});
