## 1. Immediate Next Step

A new session starts on the **AI Chat UI and button design**. Read `CHAT_SPEC.md` §1 and §12 first, then look at the Mac chat (`MonocleMac/Features/MacChatView.swift`) and the shared pieces in `Monocle/Features/Chat/` (`ChatTranscript.swift`, `ChatBubble.swift`, `ChatInputBar.swift`, `ChatView.swift`).

**Merge status (decide first):** `main` is at `319c04b` (0.8.4 (99), published). The chat work is on branch **`feat/chat-category-mentions`** (9 commits on top of `main`, the last being this docs commit, **not pushed, not merged**). The user has not said to merge it; they were still looking at the composer chips. Ask, then fast-forward `main` to it and push (it is a straight extension of `main`). A new IPA (0.8.5) has not been built for it.

What is on that branch (all in `CHAT_SPEC.md` §12 and `CHANGELOG.md` "Unreleased"):
- `#` category mentions next to `@`; both in one message; Return or Tab (Mac) confirms the highlighted row.
- Mentions are rounded chips: translucent red (75%) with white text in the composer, white bold on a dark chip in bubbles. The composer draws a coloured copy of the text over an invisible `TextField` (`MentionTextField`); chip reach is 2pt there, bubbles get thin spaces inside the chip.
- Follow-up period carry-over (`ChatAgent.period(in:)`, "Period of your last answer" in `app_context`), saved chats dropped when `ChatAgent.fingerprint` changes, one automatic restart on a stale thinking-block error.
- Chart titles show dates (`ToolExecutor.rangeLabel`).

**Not seen on screen yet:** the composer chip overlay (caret alignment on long or multi-line drafts, a chip at the very start possibly clipped on the left, chip touching punctuation), because the cmux Computer Use screenshot tool was down. Check these first when the new session opens the chat. If the overlay drifts, replace it with a real `TextEditor(text: AttributedString)` (macOS 26 / iOS 26), which needs Return-to-send via `onKeyPress` and a manual placeholder.

**Open items (none blocking):**
- Chat: budget tool only covers the current cycle (asking about last month's budget gets this cycle's chart, now date-labelled); Apple on-device probe 9/11 with two prompts failing (also failing on the previous `main`); keep the Apple backend for now (user decision); a proxy before sharing the app; chat streaming and localized strings.
- Live checks still pending: Quick Chat, charts and the `@`/`#` picker on iOS, Mac Analytics, iOS 0.8.x screens on a device (pushed navigation, Budgets tab, stack pill, new amount/rate layout).
- Release housekeeping: privacy policy / App Store label must mention the Frankfurter (ECB) rate request; Mac Release app in `~/Applications` is old (`MONOCLE_SIGNING_IDENTITY="Clipboard Dev" scripts/build-macos.sh --install`); `docs/planning/roadmap.md` is stale (2026-09-09); demo card still named "Sample book".
- Model B gaps: stack cap is current-only (versioning needs `BudgetVersion.stackID` and backup format 9); stack and all-cards totals convert foreign cards at today's rate (marked ≈); saving a "Total until" goal replaces the cycle budget on the same `effectiveDay`; widget deep links `monocle://budgets` / `monocle://analytics` untested on a device.
- The old local branches and worktrees were deleted; only `main` and the chat branch exist. This worktree (`.claude/worktrees/quickchat-window-fix`) is locked and is on `feat/chat-category-mentions`; the main checkout is on `main`.

**Workflow notes for this repo:**
- Two ways to record an expense: the manual form and AI chat. Text entry is gone; `ExpenseParser` stays only for the Shortcuts "record text" action. Mac amount field turns `28k` / `Rp28.000` into grouped digits when focus leaves the field; the iOS form is keypad only.
- Golden fixtures (`MonocleTests/Fixtures`) must round-trip byte for byte. `workspace-v8.monoclebackup` is gitignored and regenerated locally: build, delete it, run `GoldenFormatTests` with `test-without-building` (it writes the fixture and fails once), run again.
- After every Mac rebuild, launch the demo: `open -n --env MONOCLE_DEMO=1 build/macos/DebugDerived/Build/Products/Debug/Monocle.app` (`pkill -x Monocle` first). The Mac Debug build is `xcodebuild -project Monocle.xcodeproj -scheme MonocleMac -configuration Debug -derivedDataPath build/macos/DebugDerived build`.
- On-device chat probe: `xcodebuild … -scheme MonocleMac … -only-testing:MonocleMacTests/AppleChatTests/testGoldenPromptsOnDevice test`; the report is `$TMPDIR/apple-golden.txt`.
- Publishing an IPA: bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`, `xcodegen generate`, then `scripts/build-ipa.sh "notes"` (builds, copies to iCloud `Monocle-codex/`, publishes to `farchanrifai/monocle-releases`). Report filename + SHA-256. Run `xcodegen generate` whenever a Swift file is added or `project.yml` changes.
- iOS simulator for tests: iPhone 17. The first run after a long idle can hang ("test runner hung before establishing connection"): `xcrun simctl shutdown all`, boot it again, rerun with `test-without-building`.
- Mac UI tests take over the screen: run them only when the user is away. None were run this session.
- The shell blocks compound git commands and `git -C` in a worktree-isolated session: run plain, separate commands; write multi-line Python edits to `$CLAUDE_JOB_DIR/tmp` and run the file.

## 2. Last Completed Checkpoint

**Merged to `main` and shipped as SideStore 0.8.4 (99)**: `monocle-0.8.4-build-99-unsigned.ipa`, SHA-256 `9c646796698686b51cf8d89932d99768ede93447b657423686b62a9656df9b15` (also in iCloud `Monocle-codex/`, earlier IPAs kept). `main` = chat line + model B + Mac filters + iOS navigation (0.8.3) + this work, fast-forwarded in one chain: Quick Chat panel fix; text entry removed on both platforms (dead code `EntryMode`, draft `text`/`mode`, `entryModeRaw`, `EntryFormField.quick` gone; old backups and drafts still load, a stored hidden `quick` field is skipped); Add Expense form shows the reporting-currency equivalent beside the rate (`ExpenseDraft.reportingEquivalent`, needs only amount + rate), Mac thousands separators while typing (`Money.groupedInput`), `28k` converts when leaving the amount field, one-line date.

**Then, on `feat/chat-category-mentions` (unmerged, see §1):** `#` mentions, chip styling, Tab to confirm, follow-up period carry-over, saved-chat fingerprint, chart dates; docs updated (`CHAT_SPEC.md` §12, `CHANGELOG.md`, `APP_SPEC.md` note).

**Verified:** iOS unit tests 234 (4 skipped) on the merged state, `ChatAgentTests` 18 pass on the chat branch; Mac unit tests pass; Mac and iOS builds succeed; IPA built and published. Not verified: Mac UI tests, any iOS screen on a device, the new composer chip and Tab behaviour on screen.
