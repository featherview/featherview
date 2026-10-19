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
# The copyright year is the build's year (About and Finder's Get Info show it).
plutil -replace NSHumanReadableCopyright -string "© $(date +%Y) Joachim Rütter" "$APP/Contents/Info.plist"
# AppIcon.icns is rendered from AppIcon.svg (rsvg-convert per size, then iconutil).
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/Feather.svg "$APP/Contents/Resources/Feather.svg"
# The accent colour (Info.plist NSAccentColorName): feather coral in dark, a darker brown in light.
xcrun actool Resources/Assets.xcassets --compile "$APP/Contents/Resources" --platform macosx \
  --minimum-deployment-target 14.0 --output-format human-readable-text --notices --warnings \
  --output-partial-info-plist build/assets-info.plist >/dev/null
cp LICENSE "$APP/Contents/Resources/LICENSE"
cp Resources/Acknowledgements.txt "$APP/Contents/Resources/Acknowledgements.txt"
# The string catalog compiles into one .lproj per language; en.lproj always, so macOS lists English.
xcrun xcstringstool compile Resources/Localizable.xcstrings --output-directory "$APP/Contents/Resources" \
  --serialization-format binary
mkdir -p "$APP/Contents/Resources/en.lproj"
# Quick Look extensions (Finder thumbnails and previews): each SwiftPM binary wrapped in an .appex
# with the app's version, sandboxed (Quick Look requires it), signed before the app.
appex() {
  swift build -c "$CONFIG" --product "$1" $LINK
  dir="$APP/Contents/PlugIns/$1.appex/Contents"
  mkdir -p "$dir/MacOS"
  cp "$(swift build -c "$CONFIG" --show-bin-path $LINK)/$1" "$dir/MacOS/$1"
  cp "$2" "$dir/Info.plist"
  for key in CFBundleShortVersionString CFBundleVersion; do
    plutil -replace "$key" -string "$(plutil -extract "$key" raw Resources/Info.plist)" "$dir/Info.plist"
  done
  codesign --force --sign - --entitlements Resources/QuickLook/QuickLook.entitlements "$APP/Contents/PlugIns/$1.appex"
}
appex FeatherviewThumbnail Resources/QuickLook/Thumbnail-Info.plist
# Ad-hoc signature: runs on this Mac. Public releases need a Developer ID signature + notarization.
codesign --force --sign - "$APP"
echo "$APP"
