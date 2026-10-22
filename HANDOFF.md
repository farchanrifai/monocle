## 1. Immediate Next Step

Font pass in progress on `release/app-store`. Checkpoint commit: non-amount monospaced text (card-back labels, widget captions, `AnkaStyle.label`, Mac Date column) switched to default design; amounts stay monospaced. Debug build with that change is on the owner's iPhone 18 Pro (free team `P8HX673QTL`, App Group stripped via empty entitlements override, 7-day expiry, install: `xcodebuild -derivedDataPath build/phone ... CODE_SIGN_ENTITLEMENTS=<empty plist>` then `devicectl device install app`). Owner is reviewing it. Next experiment: default system font everywhere except Anka wordmark; revert with `git revert` if the owner dislikes it.

**Pending:** owner enrolls; register `com.farchan.anka`, App Group, Pro product IDs; reserve name "Anka".

## 2. Last Completed Checkpoint

App renamed Monocle → Anka on `release/app-store` (store name Anka, subtitle "A card for every purpose"; plain "Monocle" is taken). Targets, dirs, `Anka.xcodeproj`, bundle IDs `com.farchan.anka*`, App Group `group.com.farchan.anka`, StoreKit IDs `com.farchan.anka.pro.*`, Core Data `Anka*`, `anka://`, `ANKA_*` env vars, `.ankabackup` (legacy `.monoclebackup` still imports). SideStore scripts (`build-ipa.sh`, `publish-sidestore.sh`) left stale on purpose. Anka iOS + Mac unit tests pass; UI tests not run.

**Next:** owner enrolls; register `com.farchan.anka`, the App Group and the Pro product IDs; reserve the name "Anka" in App Store Connect; then the earlier list below.
