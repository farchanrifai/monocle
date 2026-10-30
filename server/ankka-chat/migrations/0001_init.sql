-- Receipts already verified, so each request is one lookup instead of a certificate chain check.
CREATE TABLE receipts (
  hash TEXT PRIMARY KEY,              -- sha256 hex of the transaction JWS
  user TEXT NOT NULL,                 -- originalTransactionId: one per subscription, stable across renewals
  expires_ms INTEGER NOT NULL,
  environment TEXT NOT NULL,          -- Production | Sandbox
  created_at INTEGER NOT NULL
);
-- Counts only, never content.
CREATE TABLE usage (
  month TEXT NOT NULL,                -- UTC YYYY-MM
  user TEXT NOT NULL,
  requests INTEGER NOT NULL DEFAULT 0,
  tokens_in INTEGER NOT NULL DEFAULT 0,   -- all prompt tokens incl. cache
  tokens_out INTEGER NOT NULL DEFAULT 0,
  cost_micro INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (month, user)
);
