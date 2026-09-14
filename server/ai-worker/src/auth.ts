import { b64decode, sha256hex } from "./util";

export const MAX_SKEW_S = 120;
export const REPLAY_TTL_S = 150;

/** The exact bytes that get signed (UTF-8). No trailing newline. */
export function canonicalString(method: string, path: string, timestamp: string, bodySha256Hex: string): string {
  return `${method.toUpperCase()}\n${path}\n${timestamp}\n${bodySha256Hex}`;
}

export function isValidPublicKey(b64: unknown): b64 is string {
  if (typeof b64 !== "string" || b64.length > 64) return false;
  try {
    return b64decode(b64).length === 32;
  } catch {
    return false;
  }
}

export async function verifyEd25519(publicKeyB64: string, message: string, signatureB64: string): Promise<boolean> {
  try {
    const pk = b64decode(publicKeyB64);
    const sig = b64decode(signatureB64);
    if (pk.length !== 32 || sig.length !== 64) return false;
    const key = await crypto.subtle.importKey("raw", pk, { name: "Ed25519" }, false, ["verify"]);
    return await crypto.subtle.verify({ name: "Ed25519" }, key, sig, new TextEncoder().encode(message));
  } catch {
    return false;
  }
}

export type TsCheck = { ok: true; ts: number } | { ok: false; reason: string };

export function checkTimestamp(header: string | null, nowS: number): TsCheck {
  if (!header || !/^\d{1,12}$/.test(header)) return { ok: false, reason: "bad_timestamp" };
  const ts = Number(header);
  if (Math.abs(nowS - ts) > MAX_SKEW_S) return { ok: false, reason: "stale_timestamp" };
  return { ok: true, ts };
}

export interface SignedRequestInput {
  method: string;
  path: string;
  timestampHeader: string | null;
  signatureHeader: string | null;
  body: ArrayBuffer | Uint8Array;
  publicKey: string;
  nowS: number;
}

/** Timestamp window + signature. Replay is checked separately (needs per-install state). */
export async function verifySignedRequest(i: SignedRequestInput): Promise<{ ok: true } | { ok: false; reason: string }> {
  const ts = checkTimestamp(i.timestampHeader, i.nowS);
  if (!ts.ok) return ts;
  if (!i.signatureHeader) return { ok: false, reason: "missing_signature" };
  const msg = canonicalString(i.method, i.path, i.timestampHeader!, await sha256hex(i.body));
  const ok = await verifyEd25519(i.publicKey, msg, i.signatureHeader);
  return ok ? { ok: true } : { ok: false, reason: "bad_signature" };
}

/** Remembers (timestamp, signature) pairs for REPLAY_TTL_S. State is a plain object so a DO can persist it. */
export class ReplayGuard {
  constructor(public entries: Record<string, number> = {}) {}

  static key(timestamp: string, signature: string): string {
    return `${timestamp}:${signature}`;
  }

  /** Returns true if this key was already seen (a replay); otherwise records it. */
  seen(key: string, nowS: number): boolean {
    for (const [k, exp] of Object.entries(this.entries)) if (exp <= nowS) delete this.entries[k];
    if (key in this.entries) return true;
    this.entries[key] = nowS + REPLAY_TTL_S;
    return false;
  }
}
