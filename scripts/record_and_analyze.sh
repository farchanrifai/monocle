#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
simulator_id="${1:?Usage: scripts/record_and_analyze.sh SIMULATOR_UDID}"
mkdir -p "$project_root/build/motion"
output_dir="$(mktemp -d "$project_root/build/motion/capture.XXXXXX")"
video_path="$output_dir/card-transition.mp4"
recording_pid=""
stop_recording() {
  if [ -n "$recording_pid" ]; then
    kill -INT "$recording_pid" 2>/dev/null || true
    wait "$recording_pid" 2>/dev/null || true
    recording_pid=""
  fi
}
trap stop_recording EXIT
xcrun simctl io "$simulator_id" recordVideo --codec=h264 "$video_path" &
recording_pid=$!
sleep 2
if ! kill -0 "$recording_pid" 2>/dev/null; then
  wait "$recording_pid" || true
  recording_pid=""
  printf 'Video recorder did not start; no capture or extraction was attempted.
' >&2
  exit 1
fi
xcodebuild test -project Anka.xcodeproj -scheme Anka \
  -destination "platform=iOS Simulator,id=$simulator_id" \
  -derivedDataPath "$project_root/build/DerivedData" \
  -resultBundlePath "$output_dir/Motion.xcresult" \
  -only-testing:AnkaUITests/AnkaUITests/testAppleWalletCardOpeningAndClosingAnimation \
  CODE_SIGNING_ALLOWED=NO
stop_recording
mkdir -p "$output_dir/frames"
swift scripts/extract_frames.swift "$video_path" "$output_dir/frames" 5
printf 'Motion evidence: %s\n' "$output_dir"
