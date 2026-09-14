import { nextUtcMidnight, utcDay } from "./util";

/** Per-install daily counters. `usd` includes outstanding reservations. */
export interface InstallState {
  day: string;
  actions: number;
  usd: number;
}

export interface InstallLimits {
  dailyActions: number;
  dailyUsd: number;
}

/** Global (all installs) daily spend. `usd` includes outstanding reservations. */
export interface GlobalState {
  day: string;
  usd: number;
}

export function freshInstall(nowMs: number): InstallState {
  return { day: utcDay(nowMs), actions: 0, usd: 0 };
}

/** Counters reset at UTC midnight. */
export function rollover<T extends { day: string }>(state: T | undefined, nowMs: number, fresh: () => T): T {
  if (!state || state.day !== utcDay(nowMs)) return fresh();
  return state;
}

export type ReserveResult =
  | { ok: true; state: InstallState; day: string; resetsAt: string }
  | { ok: false; state: InstallState; reason: "actions" | "usd"; resetsAt: string };

export function reserveInstall(
  prev: InstallState | undefined,
  limits: InstallLimits,
  estUsd: number,
  nowMs: number,
): ReserveResult {
  const s = rollover(prev, nowMs, () => freshInstall(nowMs));
  const resetsAt = nextUtcMidnight(nowMs);
  if (s.actions >= limits.dailyActions) return { ok: false, state: s, reason: "actions", resetsAt };
  if (s.usd + estUsd > limits.dailyUsd) return { ok: false, state: s, reason: "usd", resetsAt };
  const next = { day: s.day, actions: s.actions + 1, usd: s.usd + estUsd };
  return { ok: true, state: next, day: s.day, resetsAt };
}

/**
 * Replace a reservation with the actual cost. If the day has rolled over since the
 * reservation, the old bucket is gone and nothing is applied.
 * `refundAction` gives the action back (upstream failed before producing output).
 */
export function settleInstall(
  prev: InstallState | undefined,
  reservedDay: string,
  reservedUsd: number,
  actualUsd: number,
  refundAction: boolean,
  nowMs: number,
): InstallState {
  const s = rollover(prev, nowMs, () => freshInstall(nowMs));
  if (s.day !== reservedDay) return s;
  return {
    day: s.day,
    actions: Math.max(0, s.actions - (refundAction ? 1 : 0)),
    usd: Math.max(0, s.usd - reservedUsd + actualUsd),
  };
}

export function remainingInstall(prev: InstallState | undefined, limits: InstallLimits, nowMs: number) {
  const s = rollover(prev, nowMs, () => freshInstall(nowMs));
  const remaining = Math.max(0, limits.dailyActions - s.actions);
  return {
    remaining,
    actionsRemaining: remaining,
    actionsLimit: limits.dailyActions,
    actionsUsed: s.actions,
    usdRemaining: Math.max(0, +(limits.dailyUsd - s.usd).toFixed(6)),
    resetsAt: nextUtcMidnight(nowMs),
  };
}

export function reserveGlobal(prev: GlobalState | undefined, capUsd: number, estUsd: number, nowMs: number) {
  const s = rollover(prev, nowMs, () => ({ day: utcDay(nowMs), usd: 0 }));
  if (s.usd + estUsd > capUsd) return { ok: false as const, state: s };
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
