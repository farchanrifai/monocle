# monocle

A personal expense tracker for iPhone, with a native Mac app planned later.

**Current stage: native interaction prototype (0.1.1, build 3).** Runs with an isolated, persistent sample book. It is not ready for daily financial records yet.

- [Prototype review and device checklist](docs/prototype/README.md)
- [Product and architecture planning](docs/planning/overview.md)
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

## Repository

Local branch: `main`. The planning baseline is committed separately from implementation. Remote repository: https://github.com/farchanrifai/monocle.

## Development continuity

Keep `docs/planning` and `docs/prototype/README.md` current. Preserve the sample store during updates. Before introducing a real-data book, implement and test full backup/restore, explicit migrations, and the daily-use checks. Do not infer working scheduling, lock security, import, or sync from their planned/settings UI.
