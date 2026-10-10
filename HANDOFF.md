## 1. Immediate Next Step

2026-10-10: Chat edit/delete (CHAT_SPEC §4). `query_expenses` rows now carry `id`; new tools `propose_edit` (id + only changed amount/category/note/day; splits allow note/day only) and `propose_delete` (id). Both return `shown_to_user` and an `ExpenseChange` (original + updated, nil = delete) — nothing writes. `ExpenseChangeCard` (in ExpenseProposalCard.swift, shared iOS/Mac): before → after or the expense, Save/Discard or Delete/Keep, then "Updated/Deleted" + Undo. `ChatSession.resolveChange` refuses if the stored expense no longer equals the snapshot; delete goes through `AppModel.delete` (bill links kept for undo via `restore`); edit undo saves the original. App notes tell Claude each choice. System prompt no longer says it can't edit/delete. Golden prompts updated (delete → card for newest; "ubah kopi kemarin jadi 30rb" → 28k→30k edit). Tests: 4 new in ChatToolTests (edit fields/no write, split rules, delete no write, apply/undo/stale refusal). iOS unit + Mac 9 unit pass; Mac builds; card rendered to image and checked. UI tests not run. No IPA built.

Next: build + publish IPA when the user wants it on the phone (bump MARKETING_VERSION + CURRENT_PROJECT_VERSION). Then chat v2 remainder (bill proposals, splits, streaming) or F26 background work. Golden prompts + cache check still need Anthropic credits. Refresh stale docs/planning/roadmap.md.

Other pending: proxy (Cloudflare Worker; user deploys).

## 2. Last Completed Checkpoint

2026-10-10: Golden-prompt script. `MonocleTests/ChatGoldenPromptTests.swift` runs the 10 CHAT_SPEC §10 prompts through `ChatAgent` + real `ClaudeClient` on a seeded in-memory book (5 expenses, overall + food budget). Checks: proposal amounts (28k, 100rb + yesterday's day, 45k+5k as two cards, add 0 → none, 10 juta → Rp10.000.000 if proposed), questions return no error and no proposal, delete declined with count unchanged. Prints every reply and per-request usage (input / cache write / cache read) for the cache check. Skipped without a key; fixture still runs. Run:
`TEST_RUNNER_ANTHROPIC_API_KEY=sk-ant-... xcodebuild test -project Monocle.xcodeproj -scheme Monocle -destination 'platform=iOS Simulator,id=<UDID>' -only-testing:MonocleTests/ChatGoldenPromptTests CODE_SIGNING_ALLOWED=NO`
iOS 203 unit pass (4 skipped). UI tests not run. Committed 8d3424f.

Next: once Anthropic credits are topped up, run the command above and review replies + cache reads. Roadmap doc (docs/planning/roadmap.md, dated 2026-09-09) is stale: CSV, bill skip/reminders and multi-card stacks already exist — refresh it before picking the next milestone.

Other pending: proxy (Cloudflare Worker; user deploys).
