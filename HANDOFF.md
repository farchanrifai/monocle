## 1. Immediate Next Step

Backend reliability fixes are implemented and released as **0.7.21/build 84**. The local branch is `codex/backend-reliability`, based on audit `7937472` / main `b7621cc`; implementation commit `6ea3d04`. Source has not been pushed and no PR was created. Read `docs/audit/2026-10-05-backend-implementation.md` for all F01–F27 outcomes and continuation limits.

Resume with **F26 background persistence/streaming and signed-phone verification**. Worker CSV parsing, batched/scoped writes, transaction caches, bounded predicate/date paging, single rendered analytics and committed publication are implemented. Full SQLite/backup materialization remains on the main actor and format 7 still holds whole graph/output Data. Profile copied/synthetic 1k/10k/50k fixtures on the phone before choosing context/index changes. Do not infer physical budgets from simulator timings.

Final verification: Xcode 27.0 (27A5194q), iOS 26.5; **181/181 unit tests passed**, including 10k/50k fixtures, in `build/backend-audit/fixes-unit-final-2.log/.xcresult`. Full UI run covered 42 flows; four failures (three baseline missing-card fixtures and one introduced unfinished split display) were corrected. **18/18 final targeted UI checks passed**, including all four failures and affected workspace flows, in `fixes-ui-final.log/.xcresult`. Final unsigned arm64 app/widget Release package rebuilt successfully in `ipa-build.log`; ZIP, versions/IDs, minimum iOS 26/iPhone-only, V4 model, ActivityKit flag, backup UTI and exclusion of debug fixture code verified.

IPA delivered without overwriting prior files:
`/Users/farchan/Library/Mobile Documents/com~apple~CloudDocs/Monocle-codex/monocle-0.7.21-build-84-unsigned.ipa`
SHA-256: `b83a893235cec36a99bb6f54340795c5c160357c1e139e802897ca37d657b5d2` (2,939,800 bytes). Local/iCloud copies and GitHub asset digest match.

Published release: https://github.com/farchanrifai/monocle-releases/releases/tag/v0.7.21-build.84
SideStore feed: https://raw.githubusercontent.com/farchanrifai/monocle-releases/main/source.json
Release-repo feed commit: `5d8efd7`. Prior Monocle versions and four other apps' complete entries are preserved. Publication was explicitly requested by the user. Mac CI is committed locally but its hosted execution is not yet verified.

Next signed iPhone checks: install over the existing SideStore app with unchanged identity; verify records/drafts/V4 migration, Files backup/export/import, app-lock/authentication, reminder grant/deny/delivery, widget/Shortcut App Group refresh and Live Activity replacement/reconnect. Synthetic testing did not open or mutate the original user database.

Final Debug simulator comparison: 10k writes 188.563 s per-row versus 0.465 s batch; 50k batch improved from 66.532 s to 2.562 s after caching card fetches inside transactions. Page reads ~4–11 ms. These are not Release phone p50/p95 or memory budgets.

## 2. Last Completed Checkpoint

Backend implementation is complete on `codex/backend-reliability` from audit `7937472` / main `b7621cc`. Source is currently uncommitted; final version is 0.7.21/build 84. Read `docs/audit/2026-10-05-backend-implementation.md` for F01–F27 mapping. F26 remains partial: worker CSV parsing, batched scoped persistence/report reuse and measured transaction caches are implemented, but background SQLite/backup streaming and signed-phone profiling remain follow-up.

The user explicitly requested: finish fixes, build the IPA and push it to the release repo. Release target is public `farchanrifai/monocle-releases`; shared source.json contains five apps. Publish only Monocle (`com.farchan.monocle`), preserve all other entries and prior IPAs. IPA delivery folder is `/Users/farchan/Library/Mobile Documents/com~apple~CloudDocs/Monocle-codex/`.

Recorded Xcode 27.0 (27A5194q), iOS 26.5 baseline: 118 unit tests passed; 39/42 UI passed. The three baseline motion failures had missing multi-card fixtures; debug-only isolated three-card fixtures now pass. Initial implementation full UI: 38/42 with those three fixture failures plus a new unfinished split subtotal regression. The split regression is fixed and its targeted UI test now passes.

Verification in progress:
- Final source complete unit run on iPhone 17 Pro Max `3321C59F-B6B1-4CC3-BA0D-27355A488689`: `build/backend-audit/fixes-unit-final-2.log/.xcresult`, exec session 27241. Earlier full run `fixes-unit-9`: 179/179 passed with 10k/50k enabled. Latest adds preference-write rollback and incomplete split regressions.
- Latest 18 targeted UI checks on iPhone 17 Pro `D972CED0-283F-4ACC-A70E-457150023BA2`: `fixes-ui-final.log/.xcresult`, session 56638; all observed checks passed so far.
- IPA packaging final source with publication disabled: `ipa-build.log`, session returned by tool. Prior generic device Release build succeeded; script rebuilds current source.
- Debug timings: 10k per-row ~198 s versus batch 0.488 s; 50k batch 66.5 s before transaction book cache versus 2.625 s after. Simulator comparison, not device budgets.
- YAML/plist/shell syntax and whitespace checks pass. Mac CI added but hosted run unverified.

After tests/build finish, verify ZIP, app/extension versions, V4 model/ActivityKit flag, iCloud hash equality; publish via `scripts/publish-sidestore.sh`, verify remote asset digest and SideStore feed, compare non-Monocle entries to `release-source-before.json`. Record filename/SHA-256/release URL, update report/HANDOFF, and preserve source changes with a local commit. No source push or PR requested. No real user database opened.
