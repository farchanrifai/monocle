## 1. Immediate Next Step

0.9.1 (105) is published (`monocle-0.9.1-build-105-unsigned.ipa`, SHA-256 `1fd5ab475e0de21061e74ad772b0c5512f30d5c2109820149c642889dc961f46`, iCloud `Monocle-codex/`) and adds streaming chat replies (`ClaudeClient.stream`, `StreamAssembler`, `ChatAgent.onText`, `ChatSession.streamingText`; CHAT_SPEC §12). It has NOT been seen against the real API or on a phone, only against canned SSE in tests. Shortcuts read-only intents shipped in 0.9.0 (`monocle-0.9.0-build-104-unsigned.ipa`, SHA-256 `167e5e6490ac8b17c517430b73602daf34631a1dcbb43a4101be011a87208090`).

**Next:** on a phone: send a chat message and watch the stream (bubble opens at first words, no flicker, markdown with `**` mid-stream shows raw until closed, a tool question still ends right, airplane mode mid-reply rolls back with the error), then the three Shortcuts, `@name` scope, "last month" then "what categories?". Shortcuts gaps left: Add Expense takes whole rupiah only (changing the `Int` parameter could break users' saved shortcuts), no Remove-last-expense intent, no Indonesian phrases, no payment-method parameter, no Spotlight `IndexedEntity`, Control Center button only opens the app.

**Send style:** decided, WhatsApp style kept. The iMessage flight and the `chatSendStyle` switch are deleted (tag `chat-flight-imessage` keeps the old code). Constants: `ChatSession.growDuration` / `whatsappGrow` / `replyAnimation` in `Monocle/Features/Chat/ChatBubble.swift`; `CHAT_SPEC.md` §12.

**Open items (none blocking):**
- Chat: budget tool only covers the current cycle; Apple on-device probe 9/11 (also failing on `main`); keep the Apple backend for now (user decision); a proxy before sharing the app; chat streaming and localized strings.
- Live checks pending: Quick Chat, charts and the `@`/`#` picker on iOS, Mac Analytics, iOS 0.8.x screens on a device (pushed navigation, Budgets tab, stack pill, new amount/rate layout).
- Release housekeeping: privacy policy drafted in `docs/privacy.md` (needs the owner's contact line, hosting, and a `PrivacyInfo.xcprivacy`, which does not exist yet); Mac Release app in `~/Applications` is old (`MONOCLE_SIGNING_IDENTITY="Clipboard Dev" scripts/build-macos.sh --install`); `docs/planning/roadmap.md` is stale; demo card still named "Sample book".
- Model B gaps: stack cap is current-only (versioning needs `BudgetVersion.stackID` and backup format 9); stack and all-cards totals convert foreign cards at today's rate (marked ≈); saving a "Total until" goal replaces the cycle budget on the same `effectiveDay`; widget deep links `monocle://budgets` / `monocle://analytics` untested on a device.
- `.claude/worktrees/quickchat-window-fix` is still on `feat/chat-category-mentions` (same commit as `main` now); the main checkout is on `main`.

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

Chat UI polish from the user's phone recordings (frames read at 60fps), all merged to `main`:
- Reply grows in place from the thinking bubble: the thinking bubble and the reply's first text row share one identity (`ChatSession.typingID`, one `ChatBubble` call site in `ChatTranscript`), so the bubble resizes and the text crossfades.
- Sent (red) bubble: the old grow sat at 30% until the 800ms flight timer cleared because the `onAppear` state change never took effect. It is now clock-driven (`GrowIn` modifier with `TimelineView`, `ChatSession.growDuration` 0.3s, no hold).
- A hand-typed `@name` sets the chat scope on send (`ChatScopeMenuItems.applyMention`, stacks, then cards, then All Cards); the header follows. `@` scope is sticky for the chat, not per message. New test `testTypedAtMentionSetsTheScopeOnSend`.
- Published 0.8.6 (101), 0.8.7 (102), 0.8.8 (103).

**Verified:** iOS and Mac builds; 242 iOS unit tests pass (4 skipped) at 0.8.7; `ChatAgentTests` 19 pass after the scope fix. The user confirmed on a phone that the AI bubble is OK (0.8.7) and then the red bubble fix (0.8.8). Not verified: Mac UI tests (skipped on purpose), the scope fix on a device, the full suite after the scope fix.
