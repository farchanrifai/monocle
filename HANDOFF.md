## 1. Immediate Next Step

**Decide the merge first.** `main` is at `319c04b` (0.8.4 (99), published). All chat work is on **`feat/chat-category-mentions`** (about 22 commits on top of `main`, clean tree, **not pushed, not merged**, no 0.8.5 IPA). It is a straight extension of `main`: ask the user, then fast-forward `main` to it and push, bump the version in `project.yml`, and build the IPA (see workflow notes). Tag `chat-flight-imessage` (`041a17e`) marks the iMessage-style send baseline.

**Then check on screen what was never seen** (Computer Use was down the whole session; the send animation was tuned only against the user's own recordings and their feedback on the Mac):
- iOS: the WhatsApp-style send on a phone or simulator (first bubble in a fresh chat, keyboard up, long multi-line message). The code is shared with the Mac and wired in `ChatView`, but iOS was never watched.
- Mac and iOS: composer chip overlay (caret alignment on long or multi-line drafts, a chip at the very start possibly clipped, chip touching punctuation). If it drifts, replace it with a real `TextEditor(text: AttributedString)` (macOS 26 / iOS 26: Return-to-send via `onKeyPress`, manual placeholder).
- Floating composer blur strength (solid 34 / fade 46 iOS, 36 / 40 Mac were guessed).

**Send style switch (user is trying WhatsApp):** `ChatSession.sendStyle` reads the `chatSendStyle` default (`whatsapp` default, or `imessage`). WhatsApp: bubble appears in its slot at 15% scale, holds `0.22s`, grows from its tail corner (`whatsappGrow`, cubic-bezier 0.15, 0.6, 0.25, 1, 0.26s); the rows above ease with it. iMessage: composer shape sweeps and lifts into the slot (`sweepAnimation`, `liftAnimation` spring bounce 0.3, `rowsAnimation`). All constants live in the `ChatSession` extension in `Monocle/Features/Chat/ChatBubble.swift`; details in `CHAT_SPEC.md` §12 "Send morph" and "Send style switch". Ask which style to keep; if one wins, delete the other and the switch.

**Open items (none blocking):**
- Chat: budget tool only covers the current cycle; Apple on-device probe 9/11 (also failing on `main`); keep the Apple backend for now (user decision); a proxy before sharing the app; chat streaming and localized strings.
- Live checks pending: Quick Chat, charts and the `@`/`#` picker on iOS, Mac Analytics, iOS 0.8.x screens on a device (pushed navigation, Budgets tab, stack pill, new amount/rate layout).
- Release housekeeping: privacy policy / App Store label must mention the Frankfurter (ECB) rate request; Mac Release app in `~/Applications` is old (`MONOCLE_SIGNING_IDENTITY="Clipboard Dev" scripts/build-macos.sh --install`); `docs/planning/roadmap.md` is stale (2026-09-09); demo card still named "Sample book".
- Model B gaps: stack cap is current-only (versioning needs `BudgetVersion.stackID` and backup format 9); stack and all-cards totals convert foreign cards at today's rate (marked ≈); saving a "Total until" goal replaces the cycle budget on the same `effectiveDay`; widget deep links `monocle://budgets` / `monocle://analytics` untested on a device.
- Only `main` and the chat branch exist. This worktree (`.claude/worktrees/quickchat-window-fix`) is locked and is on `feat/chat-category-mentions`; the main checkout is on `main`.

**Workflow notes for this repo:**
- Two ways to record an expense: the manual form and AI chat. Text entry is gone; `ExpenseParser` stays only for the Shortcuts "record text" action.
- Golden fixtures (`MonocleTests/Fixtures`) must round-trip byte for byte. `workspace-v8.monoclebackup` is gitignored and regenerated locally: build, delete it, run `GoldenFormatTests` with `test-without-building` (it writes the fixture and fails once), run again.
- After every Mac rebuild, launch the demo: `open -n --env MONOCLE_DEMO=1 build/macos/DebugDerived/Build/Products/Debug/Monocle.app` (`pkill -x Monocle` first). The Mac Debug build is `xcodebuild -project Monocle.xcodeproj -scheme MonocleMac -configuration Debug -derivedDataPath build/macos/DebugDerived build`.
- On-device chat probe: `xcodebuild … -scheme MonocleMac … -only-testing:MonocleMacTests/AppleChatTests/testGoldenPromptsOnDevice test`; the report is `$TMPDIR/apple-golden.txt`.
- Publishing an IPA: bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`, `xcodegen generate`, then `scripts/build-ipa.sh "notes"` (builds, copies to iCloud `Monocle-codex/`, publishes to `farchanrifai/monocle-releases`). Report filename + SHA-256. Run `xcodegen generate` whenever a Swift file is added or `project.yml` changes (the Mac target lists its shared Chat files explicitly in `project.yml`).
- iOS simulator for tests: iPhone 17. The first run after a long idle can hang: `xcrun simctl shutdown all`, boot it again, rerun with `test-without-building`.
- Mac UI tests take over the screen: run them only when the user is away. None were run.
- The shell blocks compound git commands and `git -C` in a worktree-isolated session: run plain, separate commands; write multi-line Python edits to `$CLAUDE_JOB_DIR/tmp` and run the file.
- To study a user's screen recording: `ffmpeg` frames at the native rate (`-fps_mode passthrough`) plus pts from `ffprobe`, tile into a contact sheet and read it; that is how the Messages and WhatsApp curves were measured.

## 2. Last Completed Checkpoint

**Chat UI session on `feat/chat-category-mentions` (committed, unmerged, head `c8a2835`):**
- Composer floats over the transcript on a `ProgressiveBlur` (moved to `Monocle/Features/Chat/ProgressiveBlur.swift`, shared with the Mac target); bottom room is real padding equal to the measured composer height (`contentMargins` hid a first bubble behind the composer).
- Send animation, Mac and iOS: iMessage-style flight (measured from the user's 60fps recordings of Messages) and a WhatsApp-style grow-in-place, switchable via `chatSendStyle`. Mac was confirmed "ok" by the user for WhatsApp style with the 0.22s hold; iOS not watched.
- Earlier on the branch: `#` mentions, chip styling, Tab to confirm, follow-up period carry-over, saved-chat fingerprint, chart dates.
- Docs updated: `CHAT_SPEC.md` §12, `CHANGELOG.md` "Unreleased", this file. Memory note `chat-send-flight-imessage` holds the iMessage constants.

**Shipped earlier:** SideStore 0.8.4 (99), `monocle-0.8.4-build-99-unsigned.ipa`, SHA-256 `9c646796698686b51cf8d89932d99768ede93447b657423686b62a9656df9b15` (also in iCloud `Monocle-codex/`).

**Verified:** Mac and iOS builds succeed; iOS `ChatAgentTests` 18 pass; Mac unit tests 22 pass (1 skipped) as of the first morph commit. Not verified: Mac UI tests (skipped on purpose), any animation or the floating composer by Claude on screen, any iOS screen on a device, the composer chip and Tab behaviour on screen.
