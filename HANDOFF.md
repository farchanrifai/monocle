## 1. Immediate Next Step

App renamed Monocle → Anka on `release/app-store` (store name Anka, subtitle "A card for every purpose"; plain "Monocle" is taken). Targets, dirs, `Anka.xcodeproj`, bundle IDs `com.farchan.anka*`, App Group `group.com.farchan.anka`, StoreKit IDs `com.farchan.anka.pro.*`, Core Data `Anka*`, `anka://`, `ANKA_*` env vars, `.ankabackup` (legacy `.monoclebackup` still imports). SideStore scripts (`build-ipa.sh`, `publish-sidestore.sh`) left stale on purpose. Anka iOS + Mac unit tests pass; UI tests not run.

**Next:** owner enrolls; register `com.farchan.anka`, the App Group and the Pro product IDs; reserve the name "Anka" in App Store Connect; then the earlier list below.

## 2. Last Completed Checkpoint

`release/app-store` has the App Store work that needs no paid account: Luna/Claude removed (Apple Intelligence chat only), currency-aware Shortcuts and chat, `Plan` limits in `ExpenseService`, StoreKit 2 (`ProStore`, `Configuration/Monocle.storekit`), paywall, kept-card picker, onboarding, Pro gates, Settings ▸ Subscription, compliance, `scripts/build-appstore.sh`, privacy policy rewrite. 254 iOS + 21 Mac unit tests pass; UI tests not run. Status and remaining list: `docs/planning/app-store-release.md` ▸ Status.

**Next:** owner enrolls (Individual), Paid Apps Agreement, products in App Store Connect with the same IDs; set `DEVELOPMENT_TEAM`; decide prices and EU trader status; contact + privacy hosting; then `UPLOAD=1 scripts/build-appstore.sh` and TestFlight checks.
