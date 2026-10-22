#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA="$ROOT/build/macos/DerivedData"
PACKAGE_DIR="$ROOT/build/macos/packages"
ENTITLEMENTS="$ROOT/AnkaMac/Resources/AnkaMac.entitlements"
IDENTITY="${ANKA_SIGNING_IDENTITY:-}"
INSTALL=0

if [[ $# -gt 1 || (${1:-} != "" && ${1:-} != "--install") ]]; then
  echo "Usage: ANKA_SIGNING_IDENTITY=\"Existing Local Identity\" $0 [--install]" >&2
  exit 64
fi
[[ ${1:-} == "--install" ]] && INSTALL=1
[[ -n "$IDENTITY" ]] || { echo "ANKA_SIGNING_IDENTITY is required." >&2; exit 64; }

MATCHES="$(security find-identity -v -p codesigning | awk -v wanted="$IDENTITY" 'index($0, "\"" wanted "\"") { print }')"
COUNT="$(printf '%s\n' "$MATCHES" | awk 'NF { count++ } END { print count+0 }')"
[[ "$COUNT" -eq 1 ]] || { echo "Expected exactly one existing code-signing identity named '$IDENTITY'; found $COUNT." >&2; exit 65; }

rm -rf "$DERIVED_DATA"
mkdir -p "$PACKAGE_DIR"
xcodebuild \
  -project "$ROOT/Anka.xcodeproj" \
  -scheme AnkaMac \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$DERIVED_DATA" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGNING_ALLOWED=NO \
  build

APP="$DERIVED_DATA/Build/Products/Release/Anka.app"
[[ -d "$APP" ]] || { echo "Release app was not produced at $APP" >&2; exit 66; }

codesign --force --sign "$IDENTITY" --options runtime --timestamp=none --entitlements "$ENTITLEMENTS" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
BASE="$PACKAGE_DIR/Anka-${VERSION}-${BUILD}-macOS"
ARCHIVE="$BASE.zip"
if [[ -e "$ARCHIVE" ]]; then
  ARCHIVE="$BASE-$(date +%Y%m%d-%H%M%S).zip"
  suffix=2
  while [[ -e "$ARCHIVE" ]]; do ARCHIVE="$BASE-$(date +%Y%m%d-%H%M%S)-$suffix.zip"; ((suffix++)); done
fi
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE"
SHA256="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"

if [[ "$INSTALL" -eq 1 ]]; then
  INSTALL_DIR="$HOME/Applications"
  TARGET="$INSTALL_DIR/Anka.app"
  STAGED="$INSTALL_DIR/.Anka.installing.$$"
  OLD="$INSTALL_DIR/.Anka.replaced.$$"
  mkdir -p "$INSTALL_DIR"
  ditto "$APP" "$STAGED"
  pkill -x Anka 2>/dev/null || true
  [[ ! -e "$TARGET" ]] || mv "$TARGET" "$OLD"
  if mv "$STAGED" "$TARGET"; then rm -rf "$OLD"; else [[ ! -e "$OLD" ]] || mv "$OLD" "$TARGET"; exit 67; fi
  open "$TARGET"
fi

printf 'Application: %s\nArchive: %s\nSigning identity: %s\nVersion/build: %s (%s)\nSHA-256: %s\n' \
  "$APP" "$ARCHIVE" "$IDENTITY" "$VERSION" "$BUILD" "$SHA256"
