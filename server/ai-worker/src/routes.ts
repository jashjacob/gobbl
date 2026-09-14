import { MAX_TOKENS } from "./config";
import {
  type ChatMessage,
  buildBriefMessages,
  buildChatMessages,
  buildCleanupMessages,
  buildDigestMessages,
  buildEditMessages,
  buildExtractMessages,
  buildPlanMessages,
  buildWriteMessages,
} from "./prompts";
import type { QuotaClass } from "./quota";
import { EMPTY_DIGEST, EMPTY_EXTRACT, EMPTY_PLAN, digestParser, extractParser, planParser } from "./structured";
import {
  type Validated,
  validateBrief,
  validateChat,
  validateCleanup,
  validateDigest,
  validateEdit,
  validateExtract,
  validatePlan,
  validateWrite,
} from "./validate";

export type Prepared =
  | { ok: true; messages: ChatMessage[]; inputChars: number; maxTokens: number }
  | { ok: false; status: 400 | 413; error: string };

function route<T>(validate: (b: unknown) => Validated<T>, build: (v: T) => ChatMessage[], maxTokens: number) {
  return (body: unknown): Prepared => {
    const r = validate(body);
    return r.ok ? { ok: true, messages: build(r.value), inputChars: r.inputChars, maxTokens } : r;
  };
}

/** Every task endpoint: POST, signed, streamed, counts as one action. */
export const TASK_ROUTES: Record<string, (body: unknown) => Prepared> = {
  "/v1/write": route(validateWrite, buildWriteMessages, MAX_TOKENS.write),
  "/v1/edit": route(validateEdit, buildEditMessages, MAX_TOKENS.edit),
  "/v1/cleanup": route(validateCleanup, buildCleanupMessages, MAX_TOKENS.cleanup),
  "/v1/chat": route(validateChat, buildChatMessages, MAX_TOKENS.chat),
  "/v1/brief": route(validateBrief, buildBriefMessages, MAX_TOKENS.brief),
};

export type JsonPrepared =
  | {
      ok: true;
      messages: ChatMessage[];
      inputChars: number;
      maxTokens: number;
      /** Model output → clamped response, or null when unusable (triggers the retry). */
      parse: (content: string) => object | null;
      /** Returned with `degraded: true` when both attempts are unusable. */
      empty: object;
      cls: QuotaClass;
    }
  | { ok: false; status: 400 | 413; error: string };

function jsonRoute<T, R extends object>(
  validate: (b: unknown) => Validated<T>,
  build: (v: T) => ChatMessage[],
  parser: (v: T) => (content: string) => R | null,
  empty: R,
  maxTokens: number,
  cls: QuotaClass = "background",
) {
  return (body: unknown): JsonPrepared => {
    const r = validate(body);
    return r.ok ? { ok: true, messages: build(r.value), inputChars: r.inputChars, maxTokens, parse: parser(r.value), empty, cls } : r;
  };
}

/**
 * JSON endpoints: POST, signed, one JSON response. Extract and digest count in the background
 * quota; plan is part of a chat the user already pays an action for, so only its cost counts.
 */
export const JSON_ROUTES: Record<string, (body: unknown) => JsonPrepared> = {
  "/v1/extract": jsonRoute(validateExtract, buildExtractMessages, extractParser, EMPTY_EXTRACT, MAX_TOKENS.extract),
  "/v1/digest": jsonRoute(validateDigest, buildDigestMessages, digestParser, EMPTY_DIGEST, MAX_TOKENS.digest),
  "/v1/plan": jsonRoute(validatePlan, buildPlanMessages, planParser, EMPTY_PLAN, MAX_TOKENS.plan, "helper"),
};
