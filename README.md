# anka

A personal expense tracker for iPhone, with a native Mac app planned later.

**Current version: 0.7.21, build 84.** Local-first expense tracking with multiple cards, budgets, recurring bills, CSV interchange, widgets, Shortcuts, and full-workspace backup/restore. See the [backend implementation report](docs/audit/2026-10-05-backend-implementation.md) for changes, verification, and remaining device/performance limits.

The [backend audit](docs/audit/2026-10-04-backend.md) and [implementation plan](docs/planning/backend-improvement-plan.md) retain the original findings and acceptance gates. Fixes are implemented on `codex/backend-reliability`; the report records each finding's implementation and follow-up status.

- [Prototype review and device checklist](docs/prototype/README.md)
- [Product and architecture planning](docs/planning/overview.md)
- [Milestones, goals, and continuation roadmap](docs/planning/roadmap.md)
- [Implementation sequence](docs/planning/implementation-plan.md)

## Run locally

Open `Anka.xcodeproj`, select the **Anka** scheme and an available iPhone simulator, and Run. Minimum deployment target: iOS 26.0. Development verified with Xcode 27.0 / iOS 26.5 simulator runtime.

The Xcode project is committed so opening it requires no project-generation tool. After changing `project.yml`, regenerate it with `xcodegen generate` (validated with XcodeGen 2.46.0). No third-party runtime packages are used.

## Test and package

```sh
xcrun simctl list devices available
scripts/test.sh <simulator-UDID>
scripts/build-ipa.sh
```

The IPA script builds an **unsigned arm64 device app**, packaged for SideStore to re-sign. It is not an App Store export or an already signed installation. Generated builds, IPA files, signing material, and test results are excluded from Git.

## Wireless SideStore updates

`scripts/build-ipa.sh "Release notes"` builds the IPA, preserves a copy in `/Users/farchan/Library/Mobile Documents/com~apple~CloudDocs/Monocle-codex/`, publishes it to the public `farchanrifai/monocle-releases` repository, and updates Anka's entry in its shared SideStore source. Prior IPA files and other apps' feed entries are preserved. Set `SKIP_SIDESTORE_PUBLISH=1` for an intentionally local-only package.

Add the printed `sidestore://source?...` link to SideStore once. Later builds appear as updates automatically; keep the bundle identifier unchanged and increment both the version (`MARKETING_VERSION`) and the build number before each IPA build: SideStore only offers an update when the version string changes.

## Repository

The audit branch is `audit/backend-2026-10-04`; implementation is on `codex/backend-reliability`. Source repository: [farchanrifai/monocle](https://github.com/farchanrifai/monocle). Public release artifacts: [farchanrifai/monocle-releases](https://github.com/farchanrifai/monocle-releases).

## Development continuity

Keep `docs/planning` and `docs/prototype/README.md` current. Preserve the sample store during updates. Before introducing a real-data book, complete phone backup/restore and update checks, app lock and the remaining daily-use gates. Backup format and recovery semantics are documented in docs/planning/backup-format.md. Do not infer working scheduling, lock security, import, or sync from their planned/settings UI.
