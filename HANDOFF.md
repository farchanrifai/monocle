## 1. Immediate Next Step

`release/app-store` has the App Store work that needs no paid account: Luna/Claude removed (Apple Intelligence chat only), currency-aware Shortcuts and chat, `Plan` limits in `ExpenseService`, StoreKit 2 (`ProStore`, `Configuration/Monocle.storekit`), paywall, kept-card picker, onboarding, Pro gates, Settings ▸ Subscription, compliance, `scripts/build-appstore.sh`, privacy policy rewrite. 254 iOS + 21 Mac unit tests pass; UI tests not run. Status and remaining list: `docs/planning/app-store-release.md` ▸ Status.

**Next:** owner enrolls (Individual), Paid Apps Agreement, products in App Store Connect with the same IDs; set `DEVELOPMENT_TEAM`; decide prices and EU trader status; contact + privacy hosting; then `UPLOAD=1 scripts/build-appstore.sh` and TestFlight checks.

## 2. Last Completed Checkpoint

Branch `release/app-store` (from `main` @ `ba4f078`) prepares the App Store release; `main` stays the SideStore line. Plan, decisions and Free/Pro split: `docs/planning/app-store-release.md`. Never publish this branch to the SideStore feed.

**Next (no paid account needed):** phase 1 strip Luna + Claude; phase 1b worldwide currency fixes; phase 2 StoreKit 2 with a local `.storekit` file, paywall, gates in `ExpenseService`; phase 2b onboarding, Settings → Subscription/About; phase 3 compliance bits; phase 4 privacy policy rewrite. Open: prices, EU trader status. Owner: enroll (Individual), Paid Apps Agreement, Small Business Program.
