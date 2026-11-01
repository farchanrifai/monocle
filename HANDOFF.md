## 1. Immediate Next Step

First fix pass from the v1 audit done (2026-11-02 night, `release/app-store`, commits `95bfec7`..HEAD, not pushed). Status and the open list: `docs/audit/2026-11-02-v1-launch.md` ▸ "Status after the first fix pass". Owner decisions: Analytics split (Free totals: summary, budget vs actual, categories, Budgets page; Pro: trend cards and Pick dates), fetched rates only for the 30 ECB currencies (`Money.rateCurrencies`), iPhone only (untick Mac and Vision Pro in App Store Connect), Demo config kept (committed `d05f68c`, owner tests it ~2 days).

Changed: Free/Pro gates (stacks, caps, CSV import on every path, Analytics trends), customizer opens on Free (Look pane locked) with a new Delete Card, Sample card really hides, safety backup only before destructive commands, bills and stack caps in the reporting currency with decimals, Pro refresh on foreground, Face ID no longer re-locks, Control Center control opens ankka://entry, 1.0.0 (114), icon without alpha. Production: privacy page deployed (site repo commit `dda0bb9`, not pushed), D1 roadmap/votes edited, Worker 7b7307b9 (vote rate limit, sandbox cap).

Next: phone checks the simulator can't do (Control Center control, App Lock "Immediately" with Face ID, paywall from the customizer/stack/CSV sheets, Delete Card), then the remaining audit items in the doc's order. iOS unit tests pass (286 incl. the new gate test); UI tests not re-run after the fixes.

Open outside the plan: phone runs the DEMO build; reinstall `build/phone-fast` for real data. macOS 27.2 beta vs Xcode SDK mismatch; Mac verified by build only.

## 2. Last Completed Checkpoint

v1 launch audit done (2026-11-02, `release/app-store` @ `ab3a733`, audit only). Plan: `docs/audit/2026-11-02-v1-launch.md` (Phase 0 blockers B1–B7, Phase 1 bugs F1–F13, Phase 2 guidelines, Phase 3 UX U1–U17, Phase 4 cleanup C1–C10, Phase 5 server S1–S5, owner decisions D1–D9, suggested order). Verified then: iOS unit tests 285/0 failures/5 skipped, iOS UI tests 47 passed + the 2 known failures, iOS and Mac Release builds succeed, server tests and typecheck pass, Haiku 5.5 prices in `usage.ts` correct.
