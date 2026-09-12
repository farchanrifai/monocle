#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
distribution_repo="${SIDESTORE_REPO:-farchanrifai/monocle-releases}"
ipa="${1:-}"
notes="${2:-Monocle update}"
cd "$project_root"

[ -f "$ipa" ] || { printf 'Usage: %s IPA_PATH [release notes]\n' "$0" >&2; exit 1; }

for command in gh jq git; do
  command -v "$command" >/dev/null || { printf 'Missing command: %s\n' "$command" >&2; exit 1; }
done
gh auth status >/dev/null

visibility="$(gh repo view "$distribution_repo" --json visibility --jq .visibility 2>/dev/null || true)"
if [ "$visibility" != "PUBLIC" ]; then
  printf '%s must exist and be public so SideStore can download the source and IPA.\n' "$distribution_repo" >&2
  exit 1
fi

mkdir -p "$project_root/build/packages"
stage="$(mktemp -d "$project_root/build/packages/publish.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
/usr/bin/unzip -q "$ipa" Payload/Monocle.app/Info.plist -d "$stage"
info="$stage/Payload/Monocle.app/Info.plist"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info")"
build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info")"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info")"
[ "$bundle_id" = "com.farchan.monocle" ] || { printf 'Unexpected bundle identifier: %s\n' "$bundle_id" >&2; exit 1; }

asset="$(basename "$ipa")"
tag="v${version}-build.${build_number}"
size="$(stat -f %z "$ipa")"
sha256="$(shasum -a 256 "$ipa" | awk '{print $1}')"
download_url="https://github.com/$distribution_repo/releases/download/$tag/$asset"
source_url="https://raw.githubusercontent.com/$distribution_repo/main/source.json"
icon_url="https://raw.githubusercontent.com/$distribution_repo/main/icon.png"

if gh release view "$tag" --repo "$distribution_repo" >/dev/null 2>&1; then
  printf '%s is already published; increment CURRENT_PROJECT_VERSION before releasing again.\n' "$tag" >&2
  exit 1
fi
release_notes="$(printf '%s\n\nSHA-256: %s' "$notes" "$sha256")"
printf '%s\n' "$release_notes" > "$stage/release-notes.md"
gh release create "$tag" "$ipa" --repo "$distribution_repo" --title "Monocle $version ($build_number)" --notes-file "$stage/release-notes.md"

gh repo clone "$distribution_repo" "$stage/source" -- --depth=1
source_file="$stage/source/source.json"
if [ -f "$source_file" ]; then
  jq --arg version "$version" --arg build "$build_number" --arg date "$(date +%F)" \
    --arg notes "$notes" --arg url "$download_url" --argjson size "$size" \
    '.apps[0].versions = ([{version: $version, buildVersion: $build, date: $date, localizedDescription: $notes, downloadURL: $url, size: $size, minOSVersion: "26.0"}] + [.apps[0].versions[] | select(.version != $version or .buildVersion != $build)])' \
    "$source_file" > "$source_file.tmp"
  mv "$source_file.tmp" "$source_file"
else
  jq -n --arg source "$source_url" --arg icon "$icon_url" --arg version "$version" \
    --arg build "$build_number" --arg date "$(date +%F)" --arg notes "$notes" \
    --arg url "$download_url" --argjson size "$size" \
    '{name: "Monocle", identifier: "com.farchan.monocle.source", sourceURL: $source, apps: [{name: "monocle", bundleIdentifier: "com.farchan.monocle", developerName: "farchanrifai", subtitle: "Fast, local-first expense tracking.", localizedDescription: "A private-by-design personal expense tracker for iPhone.", iconURL: $icon, tintColor: "#FF3B30", versions: [{version: $version, buildVersion: $build, date: $date, localizedDescription: $notes, downloadURL: $url, size: $size, minOSVersion: "26.0"}], permissions: [{type: "faceid", usageDescription: "Optionally locks Monocle using device authentication."}]}], news: []}' \
    > "$source_file"
fi

/usr/bin/ditto Monocle/Resources/Assets.xcassets/AppIcon.appiconset/Icon.png "$stage/source/icon.png"
jq empty "$source_file"
git -C "$stage/source" add source.json icon.png
if ! git -C "$stage/source" diff --cached --quiet; then
  git -C "$stage/source" commit -m "Publish Monocle $version ($build_number)"
  git -C "$stage/source" push origin HEAD:main
fi

printf 'Published %s\nSHA-256: %s\nAdd once in SideStore: sidestore://source?url=%s\n' "$download_url" "$sha256" "$source_url"
