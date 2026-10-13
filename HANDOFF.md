## 1. Immediate Next Step

0.9.5 (109) is the latest (file and SHA are in the release notes below once published; 0.9.4 was `monocle-0.9.4-build-108-unsigned.ipa`, SHA-256 `06a30ec1801d3b14975ee9405e69bc5dea58e664865db954492b673f72c470f2`). Streaming (0.9.1), pacer/fade (0.9.2) and the `SmoothHeight` wrap glide (0.9.3) are in CHAT_SPEC §12; 0.9.3 not yet confirmed on a phone.

**Composer bug (fix in 0.9.5, unconfirmed on a phone):** the user's recording showed that after Send the field was blank with no placeholder, so the UITextView still held the old text (the overlay mirrors the empty binding); it returned on the next keystroke (keyboard suggestion bar still showed the last word, so likely marked/autocorrect text blocked the programmatic clear). `ChatInputBar` now gives the field a new `.id` on every Send and refocuses it. Simulator tests (`testChatComposerIsReallyEmptyAfterSending`) cannot reproduce marked text, so only the user can confirm. Mac composer not touched. Also in 0.9.5: sending scrolls to the bottom (`ScrollPosition` + a second scroll after layout; `testChatSendFromTheTopScrollsToTheNewMessage`).

**Model B gaps:** (b) fixed in 0.9.4: across-cards budget spending uses each expense's own rate, only the limit is ≈ at today's rate. (c) kept as designed (a goal starts at the cycle start and replaces that monthly version; its fallback is `settings.budget`, category limits are lost); the goal editor now says so. (a) NOT done: stack cap versioning needs `BudgetVersion.stackID`, a store/schema change and backup format 9 with golden fixtures; ask the user to approve that before touching it. Chat polish left: width creep on the first streamed line (a stale-frame wrap problem makes a naive width animation wrong; would need a measured natural width and only for single-line bubbles) and localized strings (the app has no localization at all; Indonesian UI would be a whole-app String Catalog project, not a chat-only change).

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
