#!/bin/bash
# Builds the disk image: build/Featherview-<version>.dmg, one for every language. Its background has
# room for one language only, so the help text is English (the app itself follows the Mac's language).
# Usage: scripts/dmg.sh
set -euo pipefail
cd "$(dirname "$0")/.."
VOLUME="Featherview"
# Finder's window bounds include the title bar; the content below it must be the 920 x 408 background,
# the size macOS 27's Finder opens a disk image's window at whatever the image stores.
# shortcut: 28 pt is the title bar without a toolbar on macOS 14 and later, measure again if a macOS changes it.
TITLE_BAR=28
WINDOW_BOUNDS="200, 120, 1120, $((120 + 408 + TITLE_BAR))"

# Attaches a read-write image and sets DEVICE. Finder addresses the disk by name, so it stops when
# another volume called $VOLUME is mounted (the new one would land at "/Volumes/$VOLUME 1").
attach_rw() {
    local out mount
    out="$(hdiutil attach -readwrite -noverify -noautoopen "$1")"
    DEVICE="$(awk -F'\t' '/Apple_HFS/ {sub(/ +$/, "", $1); print $1; exit}' <<<"$out")"
    mount="$(awk -F'\t' '/Apple_HFS/ {print $3; exit}' <<<"$out")"
    if [ "$mount" != "/Volumes/$VOLUME" ]; then
        echo "Another volume called $VOLUME is mounted. Eject it and run again." >&2
        hdiutil detach "$DEVICE" -quiet || true
        DEVICE=""
        return 1
    fi
}
[ "${BASH_SOURCE[0]}" != "$0" ] && return 0  # sourced by scripts/test-dmg.sh

LANGS=(en)
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"

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
    OUT="build/Featherview-$VERSION.dmg"
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
    attach_rw "$RW"
    # Finder sees a freshly attached disk only after about a second.
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        [ "$(osascript -e "tell application \"Finder\" to exists disk \"$VOLUME\"")" = true ] && break
        sleep 1
    done
    [ "$(osascript -e "tell application \"Finder\" to exists disk \"$VOLUME\"")" = true ] ||
        { echo "Finder doesn't see the disk $VOLUME." >&2; exit 1; }

    # Window: 920 x 408 content, icon view, the icons where DiskImageArt draws the arrow.
    osascript <<EOF
tell application "Finder"
    tell disk "$VOLUME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {$WINDOW_BOUNDS}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 96
        set background picture of viewOptions to file ".background:background.tiff"
        set position of item "Featherview.app" of container window to {300, 170}
        set position of item "Applications" of container window to {620, 170}
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
