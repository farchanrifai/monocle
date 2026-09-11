#!/bin/bash
set -euo pipefail

SIM_ID="C9E19CFE-D34C-401C-B553-41D08810B4A1"
VIDEO_PATH="/Users/farchan/.gemini/antigravity/brain/1a37f5dc-e93b-43b2-af60-070a75a9734b/scratch/card_transition.mp4"
FRAMES_DIR="/Users/farchan/.gemini/antigravity/brain/1a37f5dc-e93b-43b2-af60-070a75a9734b/scratch/frames"

rm -f "$VIDEO_PATH"
rm -rf "$FRAMES_DIR"/*

echo "Starting screen recording on $SIM_ID..."
xcrun simctl io "$SIM_ID" recordVideo --force "$VIDEO_PATH" &
REC_PID=$!
sleep 2

echo "Running UI test to trigger transition..."
xcodebuild test -scheme Monocle -destination "platform=iOS Simulator,id=$SIM_ID" -only-testing:MonocleUITests/MonocleUITests/testAppleWalletCardOpeningAndClosingAnimation

echo "Stopping recording (PID $REC_PID)..."
kill -2 "$REC_PID" 2>/dev/null || true
wait "$REC_PID" 2>/dev/null || true
sleep 3

echo "Extracting frames at 15 fps..."
swift scripts/extract_frames.swift "$VIDEO_PATH" "$FRAMES_DIR" 15

echo "Frames extracted successfully."
ls -lh "$FRAMES_DIR" | head -n 25
