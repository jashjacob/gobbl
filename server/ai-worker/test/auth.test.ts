import { describe, expect, it } from "vitest";
import { MAX_SKEW_S, REPLAY_TTL_S, ReplayGuard, canonicalString, isValidPublicKey, verifySignedRequest } from "../src/auth";
import { b64encode, sha256hex } from "../src/util";

async function keypair() {
  const kp = (await crypto.subtle.generateKey({ name: "Ed25519" }, true, ["sign", "verify"])) as CryptoKeyPair;
  const pub = b64encode((await crypto.subtle.exportKey("raw", kp.publicKey)) as ArrayBuffer);
  return { kp, pub };
}

async function sign(key: CryptoKey, method: string, path: string, ts: string, body: string) {
  const msg = canonicalString(method, path, ts, await sha256hex(body));
  return b64encode(await crypto.subtle.sign({ name: "Ed25519" }, key, new TextEncoder().encode(msg)));
}

const enc = (s: string) => new TextEncoder().encode(s);

describe("signature verification", () => {
  const now = 1_800_000_000;
  const body = JSON.stringify({ transcript: "um hello", style: "light" });

  it("canonical string format", async () => {
    expect(canonicalString("post", "/v1/cleanup", "1800000000", "abc")).toBe("POST\n/v1/cleanup\n1800000000\nabc");
    expect(await sha256hex("")).toBe("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
  });

  it("accepts a valid signature", async () => {
    const { kp, pub } = await keypair();
    expect(isValidPublicKey(pub)).toBe(true);
    const sig = await sign(kp.privateKey, "POST", "/v1/cleanup", String(now), body);
    const r = await verifySignedRequest({
      method: "POST", path: "/v1/cleanup", timestampHeader: String(now), signatureHeader: sig, body: enc(body), publicKey: pub, nowS: now + 5,
    });
    expect(r).toEqual({ ok: true });
  });

  it("rejects wrong key", async () => {
    const a = await keypair();
    const b = await keypair();
    const sig = await sign(a.kp.privateKey, "POST", "/v1/cleanup", String(now), body);
    const r = await verifySignedRequest({
      method: "POST", path: "/v1/cleanup", timestampHeader: String(now), signatureHeader: sig, body: enc(body), publicKey: b.pub, nowS: now,
    });
    expect(r).toEqual({ ok: false, reason: "bad_signature" });
  });

  it("rejects tampered body / path / method", async () => {
    const { kp, pub } = await keypair();
    const sig = await sign(kp.privateKey, "POST", "/v1/cleanup", String(now), body);
    const base = { timestampHeader: String(now), signatureHeader: sig, publicKey: pub, nowS: now };
    expect((await verifySignedRequest({ ...base, method: "POST", path: "/v1/cleanup", body: enc(body + " ") })).ok).toBe(false);
    expect((await verifySignedRequest({ ...base, method: "POST", path: "/v1/write", body: enc(body) })).ok).toBe(false);
    expect((await verifySignedRequest({ ...base, method: "GET", path: "/v1/cleanup", body: enc(body) })).ok).toBe(false);
  });

  it("rejects old and future timestamps, and garbage", async () => {
    const { kp, pub } = await keypair();
    for (const ts of [now - MAX_SKEW_S - 1, now + MAX_SKEW_S + 1]) {
      const sig = await sign(kp.privateKey, "GET", "/v1/quota", String(ts), "");
      const r = await verifySignedRequest({
        method: "GET", path: "/v1/quota", timestampHeader: String(ts), signatureHeader: sig, body: enc(""), publicKey: pub, nowS: now,
      });
      expect(r).toEqual({ ok: false, reason: "stale_timestamp" });
    }
    const r = await verifySignedRequest({
      method: "GET", path: "/v1/quota", timestampHeader: "12.5", signatureHeader: "x", body: enc(""), publicKey: pub, nowS: now,
    });
    expect(r).toEqual({ ok: false, reason: "bad_timestamp" });
    const r2 = await verifySignedRequest({
      method: "GET", path: "/v1/quota", timestampHeader: String(now), signatureHeader: "!!notbase64", body: enc(""), publicKey: pub, nowS: now,
    });
    expect(r2.ok).toBe(false);
  });

  it("isValidPublicKey rejects wrong lengths", () => {
    expect(isValidPublicKey(b64encode(new Uint8Array(31)))).toBe(false);
    expect(isValidPublicKey(b64encode(new Uint8Array(32)))).toBe(true);
    expect(isValidPublicKey(42)).toBe(false);
  });
});

describe("API.md worked example (fixed test key, seed 0x01..0x20)", () => {
  const pub = "ebVWLo/mVPlAeLES6KmLp5AfhTrmlb7X4OORC60ElmQ=";
  const body = '{"transcript":"um so I think we should uh ship it friday","style":"light","app":"Slack","locale":"en-US"}';
  const ts = "1789430400";

  it("matches the documented canonical string and signatures", async () => {
    const h = await sha256hex(body);
    expect(h).toBe("992d23a73ff9f269724343d89c38532f5ff6474d41f2fa8fcba3f4f7d4af6926");
    expect(canonicalString("POST", "/v1/cleanup", ts, h)).toBe(`POST\n/v1/cleanup\n${ts}\n${h}`);
    const sig = "pP5W4jFxbSaI9+hfeQsw3dkxGgoIOI6U7FbdAZmlXO81J2fVz+rYdvZCY0wiGr8n3p5vN+8b/r3kWw2e14qdBQ==";
    expect(await verifySignedRequest({ method: "POST", path: "/v1/cleanup", timestampHeader: ts, signatureHeader: sig, body: enc(body), publicKey: pub, nowS: 1789430400 })).toEqual({ ok: true });
    const sigq = "qyASmwkW2hH9ZhqDmDbLhJ4Grq+cFUijogFskGtSNt6De2C9Xnz2HK22+FtRRftGSiAN85v22H/HmoJ5G4+WAQ==";
    expect(await verifySignedRequest({ method: "GET", path: "/v1/quota", timestampHeader: ts, signatureHeader: sigq, body: enc(""), publicKey: pub, nowS: 1789430400 })).toEqual({ ok: true });
  });
});

describe("replay guard", () => {
  it("rejects a replay within the window and forgets after TTL", () => {
    const g = new ReplayGuard();
    const k = ReplayGuard.key("100", "sig");
    expect(g.seen(k, 100)).toBe(false);
    expect(g.seen(k, 101)).toBe(true);
    expect(g.seen(k, 100 + REPLAY_TTL_S - 1)).toBe(true);
    expect(g.seen(k, 100 + REPLAY_TTL_S)).toBe(false); // expired, pruned, recorded again
    expect(g.seen(ReplayGuard.key("100", "other"), 101)).toBe(false);
  });

  it("TTL outlives the timestamp window so a replay can never slip through", () => {
    expect(REPLAY_TTL_S).toBeGreaterThan(MAX_SKEW_S);
  });
});
