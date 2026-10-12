## 1. Immediate Next Step

**Merge `main` first (the user has to run it, or say so in the new session).** Background sessions are not allowed to push or merge `main`, so the chat branch is pushed but `main` is still at `319c04b` (0.8.4 (99)). `feat/chat-category-mentions` is a straight extension of `main` (about 25 commits, clean tree, pushed to `origin`, includes the 0.8.5 (100) bump). Run from the main checkout:
`git fetch && git merge --ff-only origin/feat/chat-category-mentions && git push origin main`
Then update `docs/planning/roadmap.md` only if the user wants (stale, 2026-09-09).

**0.8.5 (100) is built and published to SideStore** (feed `farchanrifai/monocle-releases`, tag `v0.8.5-build.100`): `monocle-0.8.5-build-100-unsigned.ipa`, SHA-256 `0199545566f4c1f66110f237a7f10c078251cf484c1a51425ae5b8284edb01b4`, also in iCloud `Monocle-codex/` (earlier IPAs kept). Built from the chat branch, not from `main`, so after the fast-forward `main` and the IPA match. SideStore should offer the update; the user has not installed it yet.

**Then watch on a phone what Claude never saw (Computer Use was down the whole session):**
- WhatsApp-style send on iOS: first bubble in a fresh chat, keyboard up, long multi-line message, Reduce Motion. The Mac was confirmed "ok" by the user; iOS shares the code (`ChatBubble.swift`, wired in `ChatView.swift`) but was never watched.
- Composer chip overlay (caret alignment on long or multi-line drafts, a chip at the very start possibly clipped, chip touching punctuation). If it drifts, replace it with a real `TextEditor(text: AttributedString)` (macOS 26 / iOS 26: Return-to-send via `onKeyPress`, manual placeholder).
- Floating composer blur strength (solid 34 / fade 46 iOS, 36 / 40 Mac were guessed).

**Send style switch (user is trying WhatsApp):** `ChatSession.sendStyle` reads the `chatSendStyle` default (`whatsapp` default, or `imessage`; `defaults write com.farchan.monocle.mac chatSendStyle imessage` on the Mac). WhatsApp: the bubble appears in its slot at 15% scale, holds 0.22s, grows from its tail corner (`whatsappGrow`: cubic-bezier 0.15, 0.6, 0.25, 1 over 0.26s); the rows above ease with it. iMessage: composer shape sweeps and lifts into the slot (`sweepAnimation`, `liftAnimation` spring bounce 0.3, `rowsAnimation`); tag `chat-flight-imessage` (`041a17e`) marks that baseline. Constants live in the `ChatSession` extension in `Monocle/Features/Chat/ChatBubble.swift`; details in `CHAT_SPEC.md` §12 "Send morph" and "Send style switch". Ask which style to keep; if one wins, delete the other and the switch.

**Open items (none blocking):**
- Chat: budget tool only covers the current cycle; Apple on-device probe 9/11 (also failing on `main`); keep the Apple backend for now (user decision); a proxy before sharing the app; chat streaming and localized strings.
- Live checks pending: Quick Chat, charts and the `@`/`#` picker on iOS, Mac Analytics, iOS 0.8.x screens on a device (pushed navigation, Budgets tab, stack pill, new amount/rate layout).
- Release housekeeping: privacy policy / App Store label must mention the Frankfurter (ECB) rate request; Mac Release app in `~/Applications` is old (`MONOCLE_SIGNING_IDENTITY="Clipboard Dev" scripts/build-macos.sh --install`); `docs/planning/roadmap.md` is stale; demo card still named "Sample book".
- Model B gaps: stack cap is current-only (versioning needs `BudgetVersion.stackID` and backup format 9); stack and all-cards totals convert foreign cards at today's rate (marked ≈); saving a "Total until" goal replaces the cycle budget on the same `effectiveDay`; widget deep links `monocle://budgets` / `monocle://analytics` untested on a device.
- Only `main` and the chat branch exist. This worktree (`.claude/worktrees/quickchat-window-fix`) is locked and is on `feat/chat-category-mentions`; the main checkout is on `main`.

**Workflow notes for this repo:**
- Two ways to record an expense: the manual form and AI chat. Text entry is gone; `ExpenseParser` stays only for the Shortcuts "record text" action.
- Golden fixtures (`MonocleTests/Fixtures`) must round-trip byte for byte. `workspace-v8.monoclebackup` is gitignored and regenerated locally: build, delete it, run `GoldenFormatTests` with `test-without-building` (it writes the fixture and fails once), run again.
- After every Mac rebuild, launch the demo: `open -n --env MONOCLE_DEMO=1 build/macos/DebugDerived/Build/Products/Debug/Monocle.app` (`pkill -x Monocle` first). The Mac Debug build is `xcodebuild -project Monocle.xcodeproj -scheme MonocleMac -configuration Debug -derivedDataPath build/macos/DebugDerived build`.
- On-device chat probe: `xcodebuild … -scheme MonocleMac … -only-testing:MonocleMacTests/AppleChatTests/testGoldenPromptsOnDevice test`; the report is `$TMPDIR/apple-golden.txt`.
- Publishing an IPA: bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml` (SideStore only offers an update when the version string changes), `xcodegen generate`, then `scripts/build-ipa.sh` (builds, copies to iCloud `Monocle-codex/`, publishes to `farchanrifai/monocle-releases`; notes come from the matching `## [x.y.z]` section of `CHANGELOG.md`). Report filename + SHA-256. Run `xcodegen generate` whenever a Swift file is added or `project.yml` changes (the Mac target lists its shared Chat files explicitly in `project.yml`).
- iOS simulator for tests: iPhone 17. The first run after a long idle can hang: `xcrun simctl shutdown all`, boot it again, rerun with `test-without-building`.
- Mac UI tests take over the screen: run them only when the user is away. None were run.
- The shell blocks compound git commands and `git -C` in a worktree-isolated session: run plain, separate commands; write multi-line Python edits to `$CLAUDE_JOB_DIR/tmp` and run the file.
- To study a user's screen recording: `ffmpeg` frames at the native rate (`-fps_mode passthrough`) plus pts from `ffprobe`, tile into a contact sheet and read it; that is how the Messages and WhatsApp curves were measured.

## 2. Last Completed Checkpoint

**Chat UI session, committed and pushed on `feat/chat-category-mentions` (head = the 0.8.5 bump), published as SideStore 0.8.5 (100):**
- Composer floats over the transcript on a `ProgressiveBlur` (`Monocle/Features/Chat/ProgressiveBlur.swift`, shared with the Mac target); bottom room is real padding equal to the measured composer height (`contentMargins` hid a first bubble behind the composer).
- Send animation, Mac and iOS: iMessage-style flight (curves measured from the user's 60fps recordings of Messages, Mac and iPhone) and a WhatsApp-style grow-in-place (measured from a WhatsApp-style recording), switchable via `chatSendStyle`; WhatsApp is the default with a 0.22s hold. Mac confirmed OK by the user; iOS not watched.
- Earlier on the branch: `#` category mentions, rounded mention chips, Tab to confirm, follow-up period carry-over, saved-chat fingerprint, chart dates.
- Docs: `CHAT_SPEC.md` §12, `CHANGELOG.md` (`[0.8.5] - 2026-10-12`), this file. Memory note `chat-send-flight-imessage` keeps the iMessage constants.

**Verified:** Mac and iOS builds succeed; the Release device build and IPA succeeded; iOS `ChatAgentTests` 18 pass; Mac unit tests 22 pass (1 skipped) as of the first morph commit (not rerun after the later timing changes). Not verified: Mac UI tests (skipped on purpose), any animation or the floating composer by Claude on screen, any iOS screen on a device, the composer chip and Tab behaviour on screen.

**Shipped before this:** SideStore 0.8.4 (99), `monocle-0.8.4-build-99-unsigned.ipa`, SHA-256 `9c646796698686b51cf8d89932d99768ede93447b657423686b62a9656df9b15`.
