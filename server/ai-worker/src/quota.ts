import { BACKGROUND_GLOBAL_SHARE } from "./config";
import { nextUtcMidnight, utcDay } from "./util";

/**
 * "user" = something the user asked for (write, chat, …), counted in `actions`.
 * "background" = app-initiated work (extract, digest), counted in `background`.
 * "helper" = a small step of a user action (chat's memory plan): only its cost counts.
 */
export type QuotaClass = "user" | "background" | "helper";

/** Per-install daily counters. `usd` includes outstanding reservations and is shared by both classes. */
export interface InstallState {
  day: string;
  actions: number;
  /** Absent in state written before the background class existed; read as 0. */
  background?: number;
  usd: number;
}

export interface InstallLimits {
  dailyActions: number;
  dailyBackground: number;
  dailyUsd: number;
}

/** Global (all installs) daily spend. `usd` includes outstanding reservations. */
export interface GlobalState {
  day: string;
  usd: number;
}

export function freshInstall(nowMs: number): InstallState {
  return { day: utcDay(nowMs), actions: 0, background: 0, usd: 0 };
}

/** Counters reset at UTC midnight. */
export function rollover<T extends { day: string }>(state: T | undefined, nowMs: number, fresh: () => T): T {
  if (!state || state.day !== utcDay(nowMs)) return fresh();
  return state;
}

export type ReserveResult =
  | { ok: true; state: InstallState; day: string; resetsAt: string }
  | { ok: false; state: InstallState; reason: "actions" | "background" | "usd"; resetsAt: string };

export function reserveInstall(
  prev: InstallState | undefined,
  limits: InstallLimits,
  estUsd: number,
  nowMs: number,
  cls: QuotaClass = "user",
): ReserveResult {
  const s = rollover(prev, nowMs, () => freshInstall(nowMs));
  const resetsAt = nextUtcMidnight(nowMs);
  const background = s.background ?? 0;
  if (cls === "user" && s.actions >= limits.dailyActions) return { ok: false, state: s, reason: "actions", resetsAt };
  if (cls === "background" && background >= limits.dailyBackground)
    return { ok: false, state: s, reason: "background", resetsAt };
  if (s.usd + estUsd > limits.dailyUsd) return { ok: false, state: s, reason: "usd", resetsAt };
  const next: InstallState = {
    day: s.day,
    actions: s.actions + (cls === "user" ? 1 : 0),
    background: background + (cls === "background" ? 1 : 0),
    usd: s.usd + estUsd,
  };
  return { ok: true, state: next, day: s.day, resetsAt };
}

/**
 * Replace a reservation with the actual cost. If the day has rolled over since the
 * reservation, the old bucket is gone and nothing is applied.
 * `refundAction` gives the action (or background call) back: upstream failed before producing output.
 */
export function settleInstall(
  prev: InstallState | undefined,
  reservedDay: string,
  reservedUsd: number,
  actualUsd: number,
  refundAction: boolean,
  nowMs: number,
  cls: QuotaClass = "user",
): InstallState {
  const s = rollover(prev, nowMs, () => freshInstall(nowMs));
  if (s.day !== reservedDay) return s;
  const refund = refundAction ? 1 : 0;
  return {
    day: s.day,
    actions: Math.max(0, s.actions - (cls === "user" ? refund : 0)),
    background: Math.max(0, (s.background ?? 0) - (cls === "background" ? refund : 0)),
    usd: Math.max(0, s.usd - reservedUsd + actualUsd),
  };
}

export function remainingInstall(prev: InstallState | undefined, limits: InstallLimits, nowMs: number) {
  const s = rollover(prev, nowMs, () => freshInstall(nowMs));
  const remaining = Math.max(0, limits.dailyActions - s.actions);
  const background = s.background ?? 0;
  return {
    remaining,
    actionsRemaining: remaining,
    actionsLimit: limits.dailyActions,
    actionsUsed: s.actions,
    backgroundRemaining: Math.max(0, limits.dailyBackground - background),
    backgroundLimit: limits.dailyBackground,
    backgroundUsed: background,
    usdRemaining: Math.max(0, +(limits.dailyUsd - s.usd).toFixed(6)),
    resetsAt: nextUtcMidnight(nowMs),
  };
}

/** Background calls see only BACKGROUND_GLOBAL_SHARE of the cap, so they pause first and user calls keep the rest. */
export function reserveGlobal(prev: GlobalState | undefined, capUsd: number, estUsd: number, nowMs: number, cls: QuotaClass = "user") {
  const s = rollover(prev, nowMs, () => ({ day: utcDay(nowMs), usd: 0 }));
  const cap = cls === "background" ? capUsd * BACKGROUND_GLOBAL_SHARE : capUsd;
  if (s.usd + estUsd > cap) return { ok: false as const, state: s };
  return { ok: true as const, state: { day: s.day, usd: s.usd + estUsd }, day: s.day };
}

export function settleGlobal(
  prev: GlobalState | undefined,
  reservedDay: string,
  reservedUsd: number,
  actualUsd: number,
  nowMs: number,
): GlobalState {
  const s = rollover(prev, nowMs, () => ({ day: utcDay(nowMs), usd: 0 }));
  if (s.day !== reservedDay) return s;
  return { day: s.day, usd: Math.max(0, s.usd - reservedUsd + actualUsd) };
}
