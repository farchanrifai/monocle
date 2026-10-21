#!/bin/bash
# App Store build: a team-signed Release archive, exported for App Store Connect.
#   DEVELOPMENT_TEAM=ABCDE12345 scripts/build-appstore.sh          # export to build/AppStore
#   DEVELOPMENT_TEAM=ABCDE12345 UPLOAD=1 scripts/build-appstore.sh # upload to App Store Connect (TestFlight)
# Needs the Apple Developer account signed in to Xcode. Bump MARKETING_VERSION/CURRENT_PROJECT_VERSION first.
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
: "${DEVELOPMENT_TEAM:?Set DEVELOPMENT_TEAM to your Apple Developer team ID}"
mkdir -p build
archive=build/Monocle.xcarchive
rm -rf "$archive" build/AppStore
xcodebuild archive -project Monocle.xcodeproj -scheme Monocle -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$archive" \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates
destination=export
[ "${UPLOAD:-0}" = "1" ] && destination=upload
cat > build/ExportOptions.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>$destination</string>
  <key>teamID</key><string>$DEVELOPMENT_TEAM</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
</dict>
</plist>
PLIST
xcodebuild -exportArchive -archivePath "$archive" -exportOptionsPlist build/ExportOptions.plist \
  -exportPath build/AppStore -allowProvisioningUpdates
[ "$destination" = upload ] && echo "Uploaded. It appears in App Store Connect ▸ TestFlight after processing." || ls build/AppStore
