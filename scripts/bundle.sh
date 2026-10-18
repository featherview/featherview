#!/bin/sh
# Builds build/Featherview.app from the SwiftPM executable. Usage: scripts/bundle.sh [debug|release]
set -eu
CONFIG="${1:-release}"
cd "$(dirname "$0")/.."
# SwiftPM records the deployment target (14.0) as the SDK; macOS then gives the app the pre-macOS 26
# look. The real SDK version turns on Liquid Glass toolbars and controls; 14 and 15 are unaffected.
SDK="$(xcrun --show-sdk-version)"
LINK="-Xlinker -platform_version -Xlinker macos -Xlinker 14.0 -Xlinker $SDK"
swift build -c "$CONFIG" --product Featherview $LINK
BIN="$(swift build -c "$CONFIG" --show-bin-path $LINK)/Featherview"
APP=build/Featherview.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Featherview"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# AppIcon.icns is rendered from AppIcon.svg (rsvg-convert per size, then iconutil).
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/Feather.svg "$APP/Contents/Resources/Feather.svg"
cp LICENSE "$APP/Contents/Resources/LICENSE"
cp Resources/Acknowledgements.txt "$APP/Contents/Resources/Acknowledgements.txt"
# The string catalog compiles into one .lproj per language; en.lproj always, so macOS lists English.
xcrun xcstringstool compile Resources/Localizable.xcstrings --output-directory "$APP/Contents/Resources" \
  --serialization-format binary
mkdir -p "$APP/Contents/Resources/en.lproj"
# Ad-hoc signature: runs on this Mac. Public releases need a Developer ID signature + notarization.
codesign --force --sign - "$APP"
echo "$APP"
