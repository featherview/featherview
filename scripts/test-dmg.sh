#!/bin/bash
# Checks scripts/dmg.sh's attach step without Finder: it must refuse when another volume
# called Featherview is mounted, and attach normally when none is.
set -uo pipefail
source "$(dirname "$0")/dmg.sh"
WORK="$(mktemp -d)"
DECOY=""
DEVICE=""
trap '[ -n "$DEVICE" ] && hdiutil detach "$DEVICE" -quiet; [ -n "$DECOY" ] && hdiutil detach "$DECOY" -quiet; rm -rf "$WORK"' EXIT
mkdir "$WORK/s"
for n in decoy new; do
    hdiutil create -quiet -srcfolder "$WORK/s" -volname "$VOLUME" -fs HFS+ -format UDRW -size 5m "$WORK/$n.dmg"
done
fail=0

if mount | grep -q " on /Volumes/$VOLUME "; then echo "skip: eject /Volumes/$VOLUME first"; exit 1; fi
attach_rw "$WORK/new.dmg" || { echo "FAIL: attach with no other $VOLUME volume"; fail=1; }
[ -n "$DEVICE" ] && hdiutil detach "$DEVICE" -quiet; DEVICE=""

DECOY="$(hdiutil attach -noverify -noautoopen -readonly "$WORK/decoy.dmg" | awk '/Apple_HFS/ {print $1; exit}')"
if attach_rw "$WORK/new.dmg" 2>/dev/null; then echo "FAIL: attached next to another $VOLUME volume"; fail=1; fi
[ -z "$DEVICE" ] || { echo "FAIL: DEVICE left set after refusing"; fail=1; }
hdiutil info | grep -q "$WORK/new.dmg" && { echo "FAIL: refused image left attached"; fail=1; }

[ $fail -eq 0 ] && echo "ok"
exit $fail
