#!/bin/bash
# Builds one disk image per language: build/Featherview-<version>-<lang>.dmg.
# Usage: scripts/dmg.sh [lang ...]   (default: en)
# A disk image has one background, so each language gets its own; the website links the visitor's.
set -euo pipefail
cd "$(dirname "$0")/.."

LANGS=("$@")
[ ${#LANGS[@]} -eq 0 ] && LANGS=(en)
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
VOLUME="Featherview"

scripts/bundle.sh release
APP="build/Featherview.app"
swift build -c release --product featherview-dmg
DMGTOOL="$(swift build -c release --show-bin-path)/featherview-dmg"

WORK="$(mktemp -d)"
DEVICE=""
cleanup() {
    [ -n "$DEVICE" ] && hdiutil detach "$DEVICE" -quiet || true
    rm -rf "$WORK"
}
trap cleanup EXIT

for LANG_CODE in "${LANGS[@]}"; do
    OUT="build/Featherview-$VERSION-$LANG_CODE.dmg"
    STAGE="$WORK/$LANG_CODE/stage"
    RW="$WORK/$LANG_CODE/rw.dmg"
    mkdir -p "$STAGE/.background"

    "$DMGTOOL" --app "$APP" --lang "$LANG_CODE" --out "$WORK/$LANG_CODE"
    tiffutil -cathidpicheck "$WORK/$LANG_CODE/background.png" "$WORK/$LANG_CODE/background@2x.png" \
        -out "$STAGE/.background/background.tiff"
    cp -R "$APP" "$STAGE/Featherview.app"
    ln -s /Applications "$STAGE/Applications"

    # Room for Finder's .DS_Store on top of the app.
    SIZE_MB=$(( $(du -sm "$STAGE" | cut -f1) + 20 ))
    hdiutil create -quiet -srcfolder "$STAGE" -volname "$VOLUME" -fs HFS+ -format UDRW -size "${SIZE_MB}m" "$RW"
    DEVICE="$(hdiutil attach -readwrite -noverify -noautoopen "$RW" | awk '/Apple_HFS/ {print $1; exit}')"

    # Window: 640 x 400 content, icon view, the icons where DiskImageArt draws the arrow.
    osascript <<EOF
tell application "Finder"
    tell disk "$VOLUME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 840, 520}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 96
        set background picture of viewOptions to file ".background:background.tiff"
        set position of item "Featherview.app" of container window to {160, 170}
        set position of item "Applications" of container window to {480, 170}
        update without registering applications
        delay 1
        close
    end tell
end tell
EOF
    sync
    hdiutil detach "$DEVICE" -quiet
    DEVICE=""

    rm -f "$OUT"
    hdiutil convert -quiet "$RW" -format UDZO -imagekey zlib-level=9 -o "$OUT"
    echo "$OUT"
done
