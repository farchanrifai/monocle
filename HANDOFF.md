## 1. Immediate Next Step

2026-10-10: Golden-prompt script. `MonocleTests/ChatGoldenPromptTests.swift` runs the 10 CHAT_SPEC §10 prompts through `ChatAgent` + real `ClaudeClient` on a seeded in-memory book (5 expenses, overall + food budget). Checks: proposal amounts (28k, 100rb + yesterday's day, 45k+5k as two cards, add 0 → none, 10 juta → Rp10.000.000 if proposed), questions return no error and no proposal, delete declined with count unchanged. Prints every reply and per-request usage (input / cache write / cache read) for the cache check. Skipped without a key; fixture still runs. Run:
`TEST_RUNNER_ANTHROPIC_API_KEY=sk-ant-... xcodebuild test -project Monocle.xcodeproj -scheme Monocle -destination 'platform=iOS Simulator,id=<UDID>' -only-testing:MonocleTests/ChatGoldenPromptTests CODE_SIGNING_ALLOWED=NO`
iOS 203 unit pass (4 skipped). UI tests not run.

Next: once Anthropic credits are topped up, run the command above and review replies + cache reads. Roadmap doc (docs/planning/roadmap.md, dated 2026-09-09) is stale: CSV, bill skip/reminders and multi-card stacks already exist — refresh it before picking the next milestone.

Other pending: proxy (Cloudflare Worker; user deploys).

## 2. Last Completed Checkpoint

2026-10-10: iOS UI suite green again. Full run had 2 failing tests (chat opt-in already passed). Both were stale tests, not app bugs: `testSettingsAppearanceModeAndAutoSwitch` — appearance picker sits below the fold on iPhone 17 Pro Max and the lazy Form never loaded it; test now swipes up until the picker is hittable. `testTransactionPageLiquidGlassAddButtonAndPlatter` — still compared the tab island to the filter bubble, which moved to the Home header; now aligns with `chatButton`. All 3 previously-failing tests pass in a targeted rerun. Mac UI tests not run.

Committed 49625a3. Then pick from roadmap (M3 bills catch-up/reminders polish, M3b multi-book home, M4 CSV) or golden-prompt script. Live chat still blocked on Anthropic credit top-up.

Other pending: proxy (Cloudflare Worker; user deploys); when billing works: live golden prompts + verify cache reads.
