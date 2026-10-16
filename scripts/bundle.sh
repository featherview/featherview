#!/bin/sh
# Builds build/Featherview.app from the SwiftPM executable. Usage: scripts/bundle.sh [debug|release]
set -eu
CONFIG="${1:-release}"
cd "$(dirname "$0")/.."
swift build -c "$CONFIG" --product Featherview
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Featherview"
APP=build/Featherview.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Featherview"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# AppIcon.icns is rendered from AppIcon.svg (rsvg-convert per size, then iconutil).
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp LICENSE "$APP/Contents/Resources/LICENSE"
# Ad-hoc signature: runs on this Mac. Public releases need a Developer ID signature + notarization.
codesign --force --sign - "$APP"
echo "$APP"
