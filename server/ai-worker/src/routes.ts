import { MAX_TOKENS } from "./config";
import {
  type ChatMessage,
  buildBriefMessages,
  buildChatMessages,
  buildCleanupMessages,
  buildEditMessages,
  buildWriteMessages,
} from "./prompts";
import { type Validated, validateBrief, validateChat, validateCleanup, validateEdit, validateWrite } from "./validate";

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
