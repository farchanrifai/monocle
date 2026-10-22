#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
# The public SideStore feed must never carry a release build (anyone could install it): keep those local.
case "$(git rev-parse --abbrev-ref HEAD)" in release/*) SKIP_SIDESTORE_PUBLISH=1 ;; esac
mkdir -p build/device build/packages
xcodebuild build -project Anka.xcodeproj -scheme Anka -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath build/device CODE_SIGNING_ALLOWED=NO
package_stage="$(mktemp -d "$project_root/build/packages/stage.XXXXXX")"
trap 'rm -rf "$package_stage"' EXIT
mkdir -p "$package_stage/Payload"
ditto build/device/Build/Products/Release-iphoneos/Anka.app "$package_stage/Payload/Anka.app"
# An unsigned device build for SideStore to re-sign, not an App Store export.
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$package_stage/Payload/Anka.app/Info.plist")
build_number=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$package_stage/Payload/Anka.app/Info.plist")
output_path="$project_root/build/packages/anka-$version-build-$build_number-unsigned.ipa"
package_suffix=0
while [ -e "$output_path" ]; do
  package_suffix=$((package_suffix + 1))
  output_path="$project_root/build/packages/anka-$version-build-$build_number-unsigned-$(date +%Y%m%d-%H%M%S)-$package_suffix.ipa"
done
(cd "$package_stage" && /usr/bin/zip -qr "$output_path" Payload)
/usr/bin/unzip -t "$output_path"
sha256="$(/usr/bin/shasum -a 256 "$output_path" | /usr/bin/awk '{print $1}')"
delivery_dir="${IPA_DELIVERY_DIR:-/Users/farchan/Library/Mobile Documents/com~apple~CloudDocs/Monocle-codex}"
mkdir -p "$delivery_dir"
delivery_path="$delivery_dir/$(basename "$output_path")"
delivery_base="${delivery_path%.ipa}"
delivery_suffix=0
while [ -e "$delivery_path" ]; do
  delivery_suffix=$((delivery_suffix + 1))
  delivery_path="$delivery_base-$(date +%Y%m%d-%H%M%S)-$delivery_suffix.ipa"
done
/usr/bin/ditto "$output_path" "$delivery_path"
printf 'Unsigned IPA: %s\nSHA-256: %s\nDelivery copy: %s\n' "$output_path" "$sha256" "$delivery_path"
changelog_notes=""
if [ -f "$project_root/CHANGELOG.md" ]; then
  changelog_notes=$(awk -v ver="$version" '
    BEGIN { found=0 }
    $0 ~ "^## \\[" ver "\\]" || $0 ~ "^## " ver { found=1; next }
    found && /^## / { exit }
    found { print }
  ' "$project_root/CHANGELOG.md" | sed -e :a -e '/^\n*$/{$d;N;};/\n$/ba')
fi

release_notes="${1:-$changelog_notes}"
if [ -z "$release_notes" ]; then
  release_notes="Anka $version ($build_number)"
fi

if [ "${SKIP_SIDESTORE_PUBLISH:-0}" != "1" ]; then
  "$project_root/scripts/publish-sidestore.sh" "$output_path" "$release_notes"
fi
