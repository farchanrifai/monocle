## 1. Immediate Next Step

User verdict 2026-10-10 after trying both in the Mac app: Claude Haiku answers are much better than on-device. Open decision: keep Apple Intelligence as a no-key/offline option or remove it; merge the branch; proxy only once chat is shared beyond the user.

Apple Intelligence chat works as a second backend and now scores 10/10 on the golden prompts on-device (uncommitted). PCC is not an option (user has no access); stay on the local model. Next: try it in the running app (Mac chat, Model = Apple Intelligence) and on iPhone (needs an IPA); add harder prompts (multi-turn follow-ups, English/Indonesian mix, "10 juta", "add 0", list_bills, get_summary chart) to the probe. Do not remove the Claude path.

State:
- `Monocle/Application/Chat/AppleChatAgent.swift`: `LanguageModelSession` (greedy sampling) + one generic `ExecutorTool` (Arguments = `GeneratedContent`) per ChatAgent tool; JSON schemas converted to `DynamicGenerationSchema`. Apple-only adjustments: `amount` is a string the app parses (`rupiah()`: k/rb/ribu/jt/juta/Rp28.000), `note` required on propose_expense, `day` required on propose_bill, a split wins over a stray `category`, `extraInstructions` appended to Claude's prompt. Retries once in a fresh session on failure. `toolLog` records calls for tuning.
- Shared change: `compare_periods` now orders periods earlier → later and adds a plain `summary` ("Spending went up by …"), for Claude too.
- `ChatBackend` protocol (ChatAgent.swift); `ChatSession.agent` is `any ChatBackend`; `UserDefaults "chatBackend"` = claude|apple. Switching starts the other model fresh; Claude history kept. Apple history not persisted.
- Settings ▸ AI Chat ▸ Model picker (iOS + Mac); no API key needed for Apple.
- Probe: `MonocleMacTests/AppleChatTests.testGoldenPromptsOnDevice` scores 10 prompts (✓/✗ + tool log), ~4–7s each on M5, report at `~/Library/Containers/com.farchan.monocle.mac/Data/tmp/apple-golden.txt`.

Since then: overview questions call get_summary and name top categories; empty period falls back to last month; follow-ups keep period (rule); app drops scope/card args that repeat the current one (fixes "Daily" stack/card clash); probe has a 3-turn follow-up conversation (score 10/11: "what categories?" still lists category names from app_context; rewording context didn't help, reverted). Mac "Open Settings…" fixed: `MacAppState.openSettings` captured from SwiftUI `openSettings` (the showSettingsWindow: selector is dead on macOS 26+); fixes command bar Settings too.

Claude (branch feat/apple-intelligence-chat, 3 commits): golden prompts now all pass with real credits. Fixed: strict tools exceeded the API's 24-optional-param cap (every request 400'd); strict grammar on propose_expense/propose_edit kept Haiku from emitting category/split/amount (now non-strict, ToolExecutor validates); note and bill day now required for both models. Run: `TEST_RUNNER_ANTHROPIC_API_KEY=$(cat ~/.monocle-anthropic-key) xcodebuild test ... -only-testing:MonocleTests/ChatGoldenPromptTests` (key file is the user's; boot the simulator first). On-device after these schema changes: 9/11 ("hapus parkir" now asks instead of proposing; wording-sensitive).

Known blemishes: the model still sometimes says "has been updated" before the user confirms (instruction ignored); "what categories?" answered with the category list.

Other open items: live-check Mac Tab order (incl. Date), sidebar collapse/Show More, card/stack menus, photo pick, Quick Record over full-screen apps; Quick Record UI tweaks (user, later); prominent glass buttons blue vs red (ask); Mac category management. Backlog: chat v2 streaming + localized UI strings; F26 background persistence; M4 accessibility audit; stale docs/planning/roadmap.md; golden prompts + cache check need Anthropic credits; proxy (Cloudflare Worker; user deploys).

## 2. Last Completed Checkpoint

2026-10-10: Apple Intelligence chat backend added and tuned from 1/10 → 10/10 on-device golden prompts. Tests: Mac unit 17 pass (incl. live probe), iOS unit 211 pass (4 skipped); Mac UI tests not run. No IPA built.
