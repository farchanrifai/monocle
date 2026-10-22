#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
if [ "$#" -ne 1 ]; then
  printf 'Usage: scripts/test.sh <available-simulator-UDID>\n'
  xcrun simctl list devices available
  exit 2
fi
mkdir -p build
xcodebuild test -project Anka.xcodeproj -scheme Anka \
  -destination "platform=iOS Simulator,id=$1" -derivedDataPath build/DerivedData \
  -resultBundlePath "build/Tests-$(date +%Y%m%d-%H%M%S).xcresult" CODE_SIGNING_ALLOWED=NO
