-- Gobbl AI proxy: initial schema.

CREATE TABLE IF NOT EXISTS installs (
  id              TEXT PRIMARY KEY,            -- random 128-bit, hex (32 chars)
  public_key      TEXT NOT NULL UNIQUE,        -- base64 raw Ed25519 key (32 bytes)
  created_at      INTEGER NOT NULL,            -- unix seconds (UTC)
  app_version     TEXT,
  ip_prefix_hash  TEXT NOT NULL,               -- sha256 hex of the /24 (v4) or /64 (v6) prefix; never the raw IP
  revoked         INTEGER NOT NULL DEFAULT 0   -- mirror of the REVOKED KV (KV is what the hot path checks)
);

CREATE INDEX IF NOT EXISTS idx_installs_prefix_created ON installs (ip_prefix_hash, created_at);

CREATE TABLE IF NOT EXISTS usage_daily (
  install_id  TEXT NOT NULL,
  day         TEXT NOT NULL,                   -- YYYY-MM-DD (UTC)
  actions     INTEGER NOT NULL DEFAULT 0,
  usd         REAL NOT NULL DEFAULT 0,         -- settled OpenRouter cost
  PRIMARY KEY (install_id, day)
);

CREATE INDEX IF NOT EXISTS idx_usage_daily_day ON usage_daily (day);
