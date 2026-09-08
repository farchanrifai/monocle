## Multi-Session Handoff Protocol

- Maintain a single file at the root named `HANDOFF.md`.
- Do not create separate timestamped files (never create `HANDOFF_v2.md`).
- At the end of every completed major task, or whenever asked to checkpoint:
  1. Move the contents of `## 1. Immediate Next Step` into `## 2. Last Completed Checkpoint`.
  2. Discard anything older than the last completed checkpoint (keep maximum 2 sections).
  3. Fill `## 1. Immediate Next Step` with the fresh, active state.
- When starting a new chat session, read `HANDOFF.md` first to establish context before asking for instructions.

## IPA Delivery

- Put every future SideStore IPA in `/Users/farchan/Library/Mobile Documents/com~apple~CloudDocs/Monocle-codex/`.
- Preserve prior IPA artifacts there. After each build, report the filename and SHA-256; do not overwrite an existing IPA.
