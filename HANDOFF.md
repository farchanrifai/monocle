## 1. Immediate Next Step

2026-10-09: CHAT_SPEC §11 step 3 (+ step 4 save path) committed on `feat/ai-chat`: `ClaudeClient` (URLSession, non-streaming, `claude-haiku-5-5`, effort low, one retry on offline/429/5xx), `ChatAgent` (append-only tool loop, max 6 steps, rollback on failure/refusal/max_tokens/step cap, per-turn `<app_context>`, app notes for Save/Discard, fresh conversation past 80 messages), `APIKeyStore` (Keychain, this device only), `ChatSettingsView` (opt-in toggle `@AppStorage("chatEnabled")` + disclosure + key), Settings → AI Chat link. ChatView: mock seed removed; Save writes via `AppModel.save`. DEBUG UI-test launches reset chat key/opt-in. Tests: unit 197 passed / 1 skipped incl. ChatAgentTests (5) + ChatToolTests (10); chat + filter UI tests pass. Published 0.7.23 (88), SHA-256 f3d62bbe14899fa2f479f9f993ac8357c38b75de323b8ad16dacbfbef145520b.

NOT yet verified against the live API (no key on this Mac): strict tool schemas, effort param, response handling. First real run happens on the user's phone.

Next: user tests on device with own key; fix anything the live API rejects. Then §11 step 6 hardening (golden prompts, injection, accessibility), Edit button on the confirm card, proxy before sharing.

## 2. Last Completed Checkpoint

2026-10-09: CHAT_SPEC §11 step 1 committed on `feat/ai-chat` (chat UI preview approved by user after device test of build 87; scope dropdown moved from title to the "Stack: Daily ⌄" subtitle, a custom principal toolbar item with `chatScopeMenu`). Latest published build: 0.7.22 (87). Every future build: bump MARKETING_VERSION + build number, publish to SideStore.

Step 2 committed on `feat/ai-chat`: `Monocle/Application/Chat/ToolExecutor.swift` — `ToolExecutor(model:scope:now:).run(name, input: Data) -> Outcome{json,isError,proposal,chart}` for propose_expense, query_expenses, get_summary, compare_periods, get_budget_status, list_cards. AppModel: `expenseService` now internal, new `books(in:)` (used by `reportingData`, keeps stack order) and `activeCategories(in:)`. Ambiguous stack/card names need `stack:`/`card:` prefix. `MonocleTests/ChatToolTests.swift` 10 tests pass; full unit suite 190 passed / 1 skipped.

Next: §11 step 3 — `ClaudeClient` (URLSession, non-streaming, Haiku 5.5 `claude-haiku-5-5`, effort low, strict tool schemas), `ChatAgent` loop (max 6 iterations, all tool_results in one user message), Keychain API key (dev setting), Settings toggle + disclosure; wire ChatView to the agent and drop the mock seed.
