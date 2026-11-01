-- Settings > Roadmap: what's coming (votable) and what shipped. Edit rows with `wrangler d1 execute`; no app release
-- needed. Counts are anonymous like `votes` and never sent to the app.
CREATE TABLE roadmap (
  id TEXT PRIMARY KEY,                -- short slug, e.g. icloud-sync
  title TEXT NOT NULL,
  detail TEXT NOT NULL DEFAULT '',
  shipped_in TEXT,                    -- app version it shipped in; NULL = coming
  sort INTEGER NOT NULL DEFAULT 0,    -- lower first within its section
  up INTEGER NOT NULL DEFAULT 0,
  down INTEGER NOT NULL DEFAULT 0
);
INSERT INTO roadmap (id, title, detail, shipped_in, sort) VALUES
  ('icloud-sync', 'iCloud sync', 'Your cards and expenses on all your Apple devices.', NULL, 1),
  ('mac-app', 'Ankka for Mac', 'The full app on your Mac, included with Pro.', NULL, 2),
  ('shared-cards', 'Shared cards', 'Track a card together with your partner or housemates.', NULL, 3),
  ('indonesian', 'Bahasa Indonesia', 'The whole app in Indonesian.', NULL, 4),
  ('whats-new', 'What''s new and Roadmap', 'See what changed after each update, and vote on what comes next.', '0.9.9', 1),
  ('monthly-budgets', 'Monthly budgets and Analytics', 'Budgets by calendar month and a new Analytics tab.', '0.9.9', 2),
  ('any-currency', 'Expenses in any currency', 'Add an expense in any currency and see it in yours.', '0.9.9', 3);
