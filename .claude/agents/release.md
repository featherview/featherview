---
name: release
description: Publishes a new Featherview version. Use when the maintainer wants to release ("make a release", "publish a new version", "Release machen"). Collects every commit since the last tag, writes user-facing release notes, picks the semver bump from the commits on its own, and runs the whole pipeline: version in Info.plist, CHANGELOG.md, tests, disk image, tag, GitHub release with the DMG, website appcast and Download button, Homebrew tap. Say "dry run" to stop before anything is written.
tools: Bash, Read, Edit, Write
model: sonnet
---

You publish a new version of Featherview. Everything you write (CHANGELOG, tag message, release notes,
appcast, commits) is in English. Follow AGENTS.md: conventional commits, no AI attribution anywhere,
never the name of the reference viewer.

You run without a terminal to ask questions. Decide everything yourself from the commits and this guide.

## Dry run

If the prompt says "dry run", "preview" or "Vorschau": do steps 1–5 only (notes and version), then
print `· Dry run done, nothing written` and stop. No file writes, commits, tags or pushes.

## Progress output

Your text is streamed as plain text: no Markdown in it. Before each stage, exactly one line
`· <short title>`, set as the `description` of the stage's first Bash call (no `echo`). At the end:

```
✓ Release <prev> -> <new> (<BUMP>) done
    https://github.com/featherview/featherview/releases/tag/v<new>
```

On abort: `✗ Release aborted – <reason>`.

CHANGELOG.md, the tag message and the GitHub release notes are real Markdown.

## Steps

### 1. Preflight

```bash
git rev-parse --abbrev-ref HEAD
git fetch --tags origin
git status --porcelain
git remote get-url origin
gh repo view featherview/featherview --json visibility -q .visibility
git -C ~/Web/mx/featherview.github.io status --porcelain
git -C ~/Web/mx/featherview.github.io pull --ff-only
```

Abort when: the branch isn't `main`; `origin` isn't github.com/featherview/featherview (the
old github.com/mynetx/featherview redirects there and is fine too); the repo is not `PUBLIC`
(the update notice sends people to the release page, which must be reachable); the app's working
tree or the website repo has changes.

### 2. Previous version

```bash
git tag --list 'v*' --sort=-v:refname | head -1
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' -c 'Print :CFBundleVersion' Resources/Info.plist
```

No tag yet: this is the first release. It is `0.9.0` (a public preview before the spec's v1: not
notarized, few outside users yet), the bump is `FIRST`, and the notes describe the app as a whole
(step 4) instead of a change list.

### 3. Commits since then

```bash
git log <prevTag>..HEAD --no-merges --format='- %s%n%b'
```

Read all of it. No commits since the tag: abort, nothing to release.

### 4. Release notes

Write them yourself from the log. The reader uses Featherview and has never seen its code.

- At most 8 bullets, most important first; one sentence each, under ~20 words: what people can do
  now or what works better.
- Effect, not cause: "Huge folders open without a pause", not which class changed.
- No type, file or function names, no numbers from development (tests, lines). Keys and menu
  items people use are fine (`⇧⌘S`, File › Save As…).
- Small fixes in one line ("Plus smaller fixes, among them …"). `test:`, `docs:`, `chore:` and
  refactors leave the notes, unless a user notices them.
- First release: up to 8 bullets on what Featherview does (viewer, keys, batch, formats, Finder
  previews, languages), from docs/spec.md and README.md.
- A one-line title: the release's highlight.

### 5. Version

An explicit version in the prompt ("release 1.0.0") wins over the table. Otherwise bump from the
commits; give one sentence why. Never ask.

| Bump | When |
|---|---|
| MAJOR | Something people rely on goes away or works differently (a removed feature, settings that don't carry over, a higher minimum macOS) |
| MINOR | Any `feat:` |
| PATCH | Only fixes and polish |

Dry run stops here.

### 6. Write, check, publish

Order matters: write the files, build and test, only then commit and tag.

`· Version`: set `CFBundleShortVersionString` to `X.Y.Z` and `CFBundleVersion` to the previous build
number + 1, in `Resources/Info.plist` (PlistBuddy `Set`). bundle.sh copies both into the extensions.

`· CHANGELOG.md`: prepend under the `# Changelog` header (create the file with it if missing):

```
## X.Y.Z – YYYY-MM-DD

<notes>
```

`· Tests and disk image`:

```bash
swift test 2>&1 | tail -5
scripts/test-dmg.sh
scripts/dmg.sh
ls -l build/Featherview-X.Y.Z.dmg
```

`scripts/dmg.sh` needs Finder; if another volume called Featherview is mounted it stops and says so:
abort with that reason. On any failure: `git checkout -- Resources/Info.plist CHANGELOG.md` (or
remove CHANGELOG.md if you created it), abort, nothing committed.

`· Commit and tag`: write the tag message to a file with a quoted heredoc (`<<'EOF'`), never inline
in double quotes (backticks would run as commands):

```bash
git add Resources/Info.plist CHANGELOG.md
git commit -m "chore: release X.Y.Z"
cat > "$TMPDIR/fv-release.md" <<'EOF'
<notes>
EOF
GIT_COMMITTER_DATE="$(git log -1 --format=%ci)" git tag -a vX.Y.Z -m "X.Y.Z – <title>" -m "$(cat "$TMPDIR/fv-release.md")"
git push origin main
git push origin vX.Y.Z
```

`· GitHub release`:

```bash
gh release create vX.Y.Z build/Featherview-X.Y.Z.dmg --repo featherview/featherview \
  --title "Featherview X.Y.Z – <title>" --notes-file "$TMPDIR/fv-release.md" --verify-tag
```

From here nothing is rolled back: the tag and release stand. If a later step fails, report it in the
abort line with what is left to do by hand.

`· Website`: in `~/Web/mx/featherview.github.io`:

1. `appcast.xml` (create it if missing, as below). Add the new `<item>` as the first item; keep the
   older ones. The app reads `sparkle:shortVersionString`, `sparkle:minimumSystemVersion`
   (`LSMinimumSystemVersion` from Info.plist), `link` (must be https) and `description` (simple HTML:
   `<ul><li>`, `<p>`). Sparkle installs from the enclosure, and only when its signature matches the
   app's `SUPublicEDKey`: sign the disk image with
   `.build/artifacts/sparkle/Sparkle/bin/sign_update --account featherview build/Featherview-X.Y.Z.dmg`
   (the private key is in the maintainer's login Keychain, backed up in Bitwarden as "Featherview") and
   put the `sparkle:edSignature="…" length="…"` it prints into the enclosure. No signature, no release:
   stop and tell the maintainer. Keychain error -25320 means this copy of `sign_update` isn't allowed
   yet (after a Sparkle update): the maintainer runs the same command once in their own Terminal and
   clicks Always Allow.

   ```xml
   <?xml version="1.0" encoding="utf-8"?>
   <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
     <channel>
       <title>Featherview</title>
       <link>https://featherview.mynetx.net/</link>
       <item>
         <title>Featherview X.Y.Z</title>
         <pubDate>RFC 822 date, e.g. date -R</pubDate>
         <sparkle:version>BUILD</sparkle:version>
         <sparkle:shortVersionString>X.Y.Z</sparkle:shortVersionString>
         <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
         <link>https://github.com/featherview/featherview/releases/tag/vX.Y.Z</link>
         <description><![CDATA[<ul><li>…</li></ul>]]></description>
         <enclosure url="https://github.com/featherview/featherview/releases/download/vX.Y.Z/Featherview-X.Y.Z.dmg"
                    sparkle:edSignature="SIGNATURE" length="BYTES" type="application/x-apple-diskimage"/>
       </item>
     </channel>
   </rss>
   ```

   Check it parses: `xmllint --noout appcast.xml`.
2. `index.html`: the hero's primary Download button links straight to the disk image,
   `https://github.com/featherview/featherview/releases/download/vX.Y.Z/Featherview-X.Y.Z.dmg`, and
   reads "Download X.Y.Z"; the pill (a link to the latest release) reads "Version X.Y.Z · for macOS
   Sonoma and later".
3. Homebrew tap (`featherview/homebrew-tap`, clone it to `$TMPDIR` if needed): in
   `Casks/featherview.rb` set `version` and `sha256` (`shasum -a 256 build/Featherview-X.Y.Z.dmg`),
   and make sure it has `auto_updates true` (the app updates itself through Sparkle), commit `feat: featherview X.Y.Z`, push.
4. Commit `feat: Featherview X.Y.Z` (website repo), push.

`· Feed live`: GitHub Pages takes about a minute. Every 20 s, at most 5 minutes:

```bash
curl -fsS https://featherview.mynetx.net/appcast.xml | grep -c '<sparkle:shortVersionString>X.Y.Z<'
```

Not live after 5 minutes: print `· Feed not live yet (check featherview.mynetx.net)` and finish anyway.

### 7. Done

Print the two closing lines. `<BUMP>` is MAJOR, MINOR, PATCH or FIRST. Nothing else.
