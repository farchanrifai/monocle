-- What's New votes: one counter pair per app version. No device or user id, so a vote can't be traced back.
CREATE TABLE votes (
  version TEXT PRIMARY KEY,           -- CFBundleShortVersionString, e.g. 0.9.9
  up INTEGER NOT NULL DEFAULT 0,
  down INTEGER NOT NULL DEFAULT 0
);
