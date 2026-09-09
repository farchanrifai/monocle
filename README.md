# monocle

A personal expense tracker for iPhone, with a native Mac app planned later.

**Current source stage: M3 budget slice (latest delivered artifact: 0.1.3, build 13).** Runs with an isolated, persistent sample book. It is not ready for daily financial records yet.

- [Prototype review and device checklist](docs/prototype/README.md)
- [Product and architecture planning](docs/planning/overview.md)
- [Milestones, goals, and continuation roadmap](docs/planning/roadmap.md)
- [Implementation sequence](docs/planning/implementation-plan.md)

## Run locally

Open `Monocle.xcodeproj`, select the **Monocle** scheme and an available iPhone simulator, and Run. Minimum deployment target: iOS 26.0. Development verified with Xcode 26.6 / iOS 26.5 SDK.

The Xcode project is committed so opening it requires no project-generation tool. After changing `project.yml`, regenerate it with `xcodegen generate` (validated with XcodeGen 2.46.0). No third-party runtime packages are used.

## Test and package

```sh
xcrun simctl list devices available
scripts/test.sh <simulator-UDID>
scripts/build-ipa.sh
```

The IPA script builds an **unsigned arm64 device app**, packaged for SideStore to re-sign. It is not an App Store export or an already signed installation. Generated builds, IPA files, signing material, and test results are excluded from Git.

## Wireless SideStore updates

`scripts/build-ipa.sh "Release notes"` builds the IPA, preserves a copy in iCloud Drive, publishes it to the public `farchanrifai/monocle-releases` repository, and updates its SideStore source. The public repository contains only release artifacts and metadata; this source repository can remain private. Set `SKIP_SIDESTORE_PUBLISH=1` for an intentionally local-only package.

Add the printed `sidestore://source?...` link to SideStore once. Later builds appear as updates automatically; keep the bundle identifier unchanged and increment the build number before each IPA build.

## Repository

Local branch: `main`. The planning baseline is committed separately from implementation. Remote repository: https://github.com/farchanrifai/monocle.

## Development continuity

Keep `docs/planning` and `docs/prototype/README.md` current. Preserve the sample store during updates. Before introducing a real-data book, complete phone backup/restore and update checks, app lock and the remaining daily-use gates. Backup format and recovery semantics are documented in docs/planning/backup-format.md. Do not infer working scheduling, lock security, import, or sync from their planned/settings UI.
