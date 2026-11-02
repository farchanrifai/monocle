## 1. Immediate Next Step

Second fix pass from the v1 audit done (2026-11-02 morning, `release/app-store`, commits `a29ffac`..HEAD, not pushed). Status and what's still open: `docs/audit/2026-11-02-v1-launch.md` ▸ "Status after the second fix pass".

Changed: App Lock (timer on background only, app-switcher cover in its own window so sheets and purchases survive, Face ID asks on its own), locked cards show a lock and a banner and Add opens the paywall first, card totals without a cached rate ("≈ rate unavailable"), free-week copy only when eligible, System appearance by default and one Appearance picker, Restore feedback, budget editor cents, privacy-sensitive widget amounts, bill reminder tap opens Bills, CSV credits unticked, Backup mentions iCloud Backup and Settings shows the last export, no compiler warnings, dead code removed, card back Analytics without its stale Pro gate, CSV formula neutralizing, CI on `release/**`. Verified: iOS unit 283/0 failed, iOS UI 46 passed + the 2 known failures, Mac unit 20 passed + 1 OS-beta crash (below).

Next: phone checks (Control Center control, App Lock flows incl. a purchase while locked, paywall from the customizer/stack/CSV sheets, Delete Card, bill reminder tap), then owner decisions U2 (rupiah intro), U7 (Remove budget vs the settings fallback budget), D7 (brand casing), and the App Store Connect items.

Open outside the plan: phone runs the DEMO build; reinstall `build/phone-fast` for real data. On macOS 27.2 beta 26B5091g the Mac Debug build crashes at `Date <=` in `AnalyticsEngine` (so `AppleChatTests.testGoldenPromptsOnDevice` fails); same before this pass, iOS unaffected.

## 2. Last Completed Checkpoint

First fix pass from the v1 audit done (2026-11-02 night, `release/app-store`, commits `95bfec7`..`9211a0c`, not pushed). Owner decisions: Analytics split (Free totals: summary, budget vs actual, categories, Budgets page; Pro: trend cards and Pick dates), fetched rates only for the 30 ECB currencies (`Money.rateCurrencies`), iPhone only (untick Mac and Vision Pro in App Store Connect), Demo config kept (committed `d05f68c`). Changed: Free/Pro gates, customizer opens on Free with Delete Card, Sample card really hides, safety backup only before destructive commands, bills and stack caps in the reporting currency with decimals, Pro refresh on foreground, Face ID no longer re-locks, Control Center control opens ankka://entry, 1.0.0 (114), icon without alpha. Production: privacy page deployed (site repo commit `dda0bb9`, not pushed), D1 roadmap/votes edited, Worker 7b7307b9 (vote rate limit, sandbox cap).
