#!/bin/bash
# Publishes a Featherview release. Only the release notes and the semver bump come from Claude.
# Usage: scripts/release.sh            (or make release)
#        DRY=1 scripts/release.sh      notes and version only, nothing written
#        VERSION=1.0.0 scripts/release.sh
#        BRIEF="no pixel formats, keep JPEG XR vague" scripts/release.sh   (the maintainer's wishes for the notes)
set -euo pipefail
cd "$(dirname "$0")/.."
SITE=~/Web/mx/featherview.github.io
REPO=featherview/featherview
WORK=$(mktemp -d)
step() { STAGE=$*; echo "· $*"; }
die() { echo "✗ Release aborted – $*" >&2; exit 1; }
STAGE=start; LEFT=""
trap 'rc=$?; [ $rc -eq 0 ] || echo "✗ Release aborted – failed at: $STAGE${LEFT:+ (left to do by hand: $LEFT)}" >&2' EXIT

step Preflight
[ "$(git rev-parse --abbrev-ref HEAD)" = main ] || die "not on main"
git fetch -q --tags origin
[ -z "$(git status --porcelain)" ] || die "the working tree has changes"
case "$(git remote get-url origin)" in
  *github.com*/featherview/featherview* | *github.com*/mynetx/featherview*) ;;
  *) die "origin isn't $REPO" ;;
esac
[ "$(gh repo view $REPO --json visibility -q .visibility)" = PUBLIC ] || die "the repo isn't public"
[ -z "$(git -C "$SITE" status --porcelain)" ] || die "the website repo has changes"
git -C "$SITE" pull -q --ff-only

step "Commits since the last release"
# shortcut: no first-release path (0.9.0 shipped long ago), add one if the repo is ever restarted
PREV_TAG=$(git tag --list 'v*' --sort=-v:refname | head -1)
PREV=${PREV_TAG#v}
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Resources/Info.plist)
LOG=$(git log "$PREV_TAG"..HEAD --no-merges --format='- %s%n%b')
[ -n "$LOG" ] || die "no commits since $PREV_TAG, nothing to release"
NOW=$(awk '/^## Now/ { f = 1; next } /^Next:/ { f = 0 } f' ROADMAP.md)
SPONSORS=$(sed -E 's/<[^>]+>//g' "$SITE/index.html" | grep -o 'So far [0-9]* of 99' || echo "So far 0 of 99")

step "Release notes"
BRIEF_TEXT=""
[ -z "${BRIEF:-}" ] || BRIEF_TEXT="The maintainer's brief for these notes and the title. It overrides the rules above: $BRIEF
"
cat >"$WORK/prompt.md" <<EOF
Write release notes for Featherview, a macOS image viewer, from the commit log below.
Fields: bump; why (one sentence); title (one line, the release's highlight); notes (Markdown
bullets, one per line); roadmap (the roadmap's "Now" text, updated for this release).

Bump: MAJOR when something people rely on goes away or works differently (removed feature, settings
that don't carry over, higher minimum macOS); MINOR for any feat:; PATCH for only fixes and polish.

Notes rules: the reader uses Featherview and has never seen its code. English, Markdown bullets.
At most 8 bullets, most important first, one sentence each, under ~20 words: what people can do now
or what works better. Effect, not cause. No type, file or function names, no numbers from development.
Keys and menu items are fine (⇧⌘S, File › Save As…). Small fixes go in one line ("Plus smaller fixes,
among them …"). test:, docs:, chore: and refactors stay out unless a user notices them. Never name
any other image viewer. The last bullet asks for help with the notarization fee; the website says
"$SPONSORS" (dollars covered of the \$99 Apple charges a year). Word it like: "Still not notarized:
Apple charges \$99 a year for that, and nobody has chipped in so far. Even \$5 once helps:
github.com/sponsors/mynetx. Then the first-open step and the Photos question after each update go away."

Roadmap: below is the "Now" text of ROADMAP.md, written for people who use the app. Return it
updated for this release in the same voice, Markdown, lines wrapped at 100 columns. A patch release
adds or replaces one short sentence like "0.13.1 shows …". A minor or major release rewrites the
"New in X.Y" part around its highlights and drops the older patch sentences.

$NOW

$BRIEF_TEXT
Commit log since $PREV:
$LOG
EOF
SCHEMA='{"type":"object","additionalProperties":false,"required":["bump","why","title","notes","roadmap"],"properties":{"bump":{"enum":["MAJOR","MINOR","PATCH"]},"why":{"type":"string"},"title":{"type":"string","minLength":1},"notes":{"type":"string","minLength":1},"roadmap":{"type":"string","minLength":1}}}'
claude -p --model sonnet --tools "" --output-format json --json-schema "$SCHEMA" <"$WORK/prompt.md" >"$WORK/out.json"
jq -e .structured_output.title "$WORK/out.json" >/dev/null || die "Claude returned no release notes: $(jq -r .result "$WORK/out.json")"
field() { jq -r ".structured_output.$1" "$WORK/out.json"; }
BUMP=$(field bump) WHY=$(field why) TITLE=$(field title) NOTES=$(field notes) ROADMAP=$(field roadmap)
IFS=. read -r MA MI PA <<<"$PREV"
case $BUMP in
  MAJOR) NEW=$((MA + 1)).0.0 ;;
  MINOR) NEW=$MA.$((MI + 1)).0 ;;
  PATCH) NEW=$MA.$MI.$((PA + 1)) ;;
esac
[ -z "${VERSION:-}" ] || { NEW=$VERSION; WHY="set by hand"; }
[[ $NEW =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "bad version $NEW"
NEWBUILD=$((BUILD + 1))
DMG=build/Featherview-$NEW.dmg
printf '%s -> %s (%s): %s\n%s\n\n%s\n\nROADMAP.md, Now:\n%s\n' "$PREV" "$NEW" "$BUMP" "$WHY" "$TITLE" "$NOTES" "$ROADMAP"
printf '%s\n' "$NOTES" >"$WORK/notes.md"
[ -z "${DRY:-}" ] || { echo "· Dry run done, nothing written"; exit 0; }

step Version
trap 'git checkout -- Resources/Info.plist CHANGELOG.md ROADMAP.md' ERR
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NEW" -c "Set :CFBundleVersion $NEWBUILD" Resources/Info.plist
{ echo "# Changelog"; echo; echo "## $NEW – $(date +%F)"; echo; cat "$WORK/notes.md"; tail -n +2 CHANGELOG.md; } >"$WORK/cl.md"
mv "$WORK/cl.md" CHANGELOG.md
printf '%s\n' "$ROADMAP" >"$WORK/now.md"
awk -v f="$WORK/now.md" '/^## Now/ { print; print ""; while ((getline l < f) > 0) print l; print ""; skip = 1; next } /^Next:/ { skip = 0 } !skip' ROADMAP.md >"$WORK/rm.md"
mv "$WORK/rm.md" ROADMAP.md

step "Tests and disk image"
swift test 2>&1 | tail -3
scripts/places.sh 2>&1 | tail -1
scripts/test-dmg.sh
scripts/dmg.sh
ls -l "$DMG"
trap - ERR

step "Commit and tag"
git add Resources/Info.plist CHANGELOG.md ROADMAP.md
git commit -q -m "chore: release $NEW"
GIT_COMMITTER_DATE="$(git log -1 --format=%ci)" git tag -a "v$NEW" -m "$NEW – $TITLE" -m "$(cat "$WORK/notes.md")"
git push -q origin main
git push -q origin "v$NEW"

step "GitHub release"
LEFT="appcast, Download button, Homebrew tap, install"
gh release create "v$NEW" "$DMG" --repo $REPO --title "Featherview $NEW – $TITLE" --notes-file "$WORK/notes.md" --verify-tag

step Website
SIG=$(.build/artifacts/sparkle/Sparkle/bin/sign_update --account featherview "$DMG")
[[ $SIG == *edSignature=* ]] || die "no Sparkle signature (Keychain error -25320: run sign_update once in your own Terminal and click Always Allow)"
# Markdown bullets to the simple HTML Sparkle shows; backticks dropped
HTML=$(sed -E -e 's/`//g' -e '/^- /{s/^- (.*)/<li>\1<\/li>/;b' -e '}' -e 's/^(.+)$/<p>\1<\/p>/' "$WORK/notes.md" | tr -d '\n' | sed -E 's/((<li>[^<]*<\/li>)+)/<ul>\1<\/ul>/g')
MINOS=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' Resources/Info.plist)
cat >"$WORK/item.xml" <<EOF
    <item>
      <title>Featherview $NEW</title>
      <pubDate>$(date -R)</pubDate>
      <sparkle:version>$NEWBUILD</sparkle:version>
      <sparkle:shortVersionString>$NEW</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MINOS</sparkle:minimumSystemVersion>
      <link>https://github.com/$REPO/releases/tag/v$NEW</link>
      <description><![CDATA[$HTML]]></description>
      <enclosure url="https://github.com/$REPO/releases/download/v$NEW/Featherview-$NEW.dmg"
                 $SIG type="application/x-apple-diskimage"/>
    </item>
EOF
awk -v f="$WORK/item.xml" '!done && /<item>/ { while ((getline l < f) > 0) print l; done = 1 } { print }' "$SITE/appcast.xml" >"$WORK/appcast.xml"
xmllint --noout "$WORK/appcast.xml"
mv "$WORK/appcast.xml" "$SITE/appcast.xml"
# the version sits in its own element: the word "Download" is translated, the number is not
sed -i '' -E "s#releases/download/v[0-9.]+/Featherview-[0-9.]+\.dmg#releases/download/v$NEW/Featherview-$NEW.dmg#; s#(<span id=\"dlv\"[^>]*>)[0-9.]+<#\\1$NEW<#" "$SITE/index.html"
grep -q "id=\"dlv\"[^>]*>$NEW<" "$SITE/index.html" || die "the Download button wasn't updated"

LEFT="Homebrew tap, website commit, install"
SHA=$(shasum -a 256 "$DMG" | cut -d' ' -f1)
gh repo clone featherview/homebrew-tap "$WORK/tap" -- -q
CASK=$WORK/tap/Casks/featherview.rb
sed -i '' -E "s/^  version \".*\"/  version \"$NEW\"/; s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$CASK"
grep -q '^  auto_updates true' "$CASK" || die "the cask lacks auto_updates true"
git -C "$WORK/tap" commit -q -am "feat: featherview $NEW"
git -C "$WORK/tap" push -q

LEFT="website commit and push, install"
git -C "$SITE" commit -q -am "feat: Featherview $NEW"
git -C "$SITE" push -q
LEFT=""

step "Feed live"
for _ in $(seq 15); do
  curl -fsS https://featherview.mynetx.net/appcast.xml | grep -q "<sparkle:shortVersionString>$NEW<" && { LIVE=1; break; }
  sleep 20
done
[ -n "${LIVE:-}" ] || echo "· Feed not live yet (check featherview.mynetx.net)"

step Install
install_app() {
  osascript -e 'tell application "Featherview" to quit' 2>/dev/null || true
  for _ in $(seq 10); do pgrep -xq Featherview || break; sleep 1; done
  if pgrep -xq Featherview; then echo "· Install skipped (Featherview still running)"; return; fi
  APP=/Applications/Featherview.app
  MNT=$WORK/mnt
  if [ -d "$APP" ]; then
    ditto "$APP" "$WORK/Featherview-$PREV-backup.app" || return 1
    echo "· backup: $WORK/Featherview-$PREV-backup.app"
  fi
  mkdir "$MNT" && hdiutil attach -quiet -nobrowse -readonly -mountpoint "$MNT" "$DMG" || return 1
  if [ -d "$APP" ]; then rsync -a --delete "$MNT/Featherview.app/" "$APP/"; else ditto "$MNT/Featherview.app" "$APP"; fi || return 1
  hdiutil detach -quiet "$MNT"
  xattr -r -d com.apple.quarantine "$APP" 2>/dev/null
  codesign --verify --deep --strict "$APP" || return 1
  [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")" = "$NEW" ] || return 1
  open "$APP"
  sleep 4
  [ "$(osascript -e 'tell application "System Events" to count windows of process "CoreServicesUIAgent"' 2>/dev/null || echo 0)" = 0 ] || { echo "· Install: macOS shows a Gatekeeper prompt"; return 1; }
}
# The release stands either way; an install failure only reports.
install_app || echo "· Install failed – backup in $WORK"

STAGE=done
echo "✓ Release $PREV -> $NEW ($BUMP) done"
echo "    https://github.com/$REPO/releases/tag/v$NEW"
