# Featherview v1 — Milestone 6 Implementation Plan (Languages)

> **Milestone 6** in `docs/roadmap.md`. Every UI string exists by now (milestones 1–5 and 7 are
> done). Don't add features from other milestones here.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. In this repo, run it wave by wave with the `plan-wave` workflow.

**Goal:** The app speaks the 30 languages spec "Languages" lists, follows the system (or per-app)
language, mirrors its layout and its ← → keys in Arabic and Hebrew, and a test fails whenever a
catalog key is missing a language, a translation is empty, or its placeholders don't match.

**Architecture:** One String Catalog, `Resources/Localizable.xcstrings`, outside every SwiftPM
target (SwiftPM would otherwise compile it into `Bundle.module`, which `Text` and
`String(localized:)` don't read). `scripts/strings.sh` fills it from the code: a full build with the
Swift compiler's `-emit-localized-strings` writes one `.stringsdata` per source file (the same
type-checked extraction Xcode uses, so custom `LocalizedStringKey` parameters such as
`ToolbarButton`'s and `IntRow`'s are found), then `xcstringstool sync` merges them into the catalog.
`scripts/bundle.sh` compiles the catalog into `<lang>.lproj` folders in the app bundle, where
`Bundle.main` (the app, for FeatherviewCore's `String(localized:)` too) finds them. A Swift Testing
suite parses the catalog JSON and checks every translation. Arabic and Hebrew mirror through
SwiftUI/AppKit's own layout direction; the only code that knows about direction is the ← → mapping
(a pure function in Core) and the image canvas, which is pinned left-to-right.

**Tech Stack:** Swift 6, SwiftPM, String Catalogs (`xcstringstool` from Xcode 27.1), SwiftUI/AppKit
layout direction, Foundation formatters, Swift Testing, `jq` (maintainer machine only: audit and
merge steps, never the build).

**Spec:** `docs/spec.md` "Languages" (all of it). Roadmap: `docs/roadmap.md` §6. Rules, budgets and
commands: `AGENTS.md`. Read the spec section and AGENTS.md first.

**Checked while planning (on this Mac, Xcode 27.1; facts, not committed code):**

- `xcrun --find xcstringstool` → `/Applications/Xcode-27.1.0.app/Contents/Developer/usr/bin/xcstringstool`,
  subcommands `print`, `compile`, `sync`, `extract`, `generate-symbols`, `installloc`.
- `swiftc -c -emit-localized-strings -emit-localized-strings-path <dir> file.swift` writes
  `<dir>/file.stringsdata` (JSON: `tables.Localizable[].key`, with `%lld` for `Int` and `%@` for
  `String` interpolations). It found `Text("Hello \(n) files")`, `Button("Open…")`,
  `String(localized: "Can't open \(name)")` **and** a literal passed to a custom
  `title: LocalizedStringKey` parameter. With `-typecheck` instead of `-c` it writes nothing.
  The `<dir>` must exist beforehand (created by hand in the check).
- `xcrun xcstringstool sync Localizable.xcstrings --stringsdata a.stringsdata …` adds the keys only
  when the catalog file is **named after the table** (`Localizable.xcstrings`; a file named
  `L.xcstrings` stayed empty). It rewrites the whole file in Xcode's formatting.
- `xcrun xcstringstool compile Localizable.xcstrings -o <dir>` writes `<lang>.lproj/Localizable.strings`
  and, for plural variations, `<lang>.lproj/Localizable.stringsdict` (`NSStringPluralRuleType`,
  forms `one`/`other`). A language without any entries gets no folder (so English, the source,
  gets none unless it has plural variations).
- `xcstringstool extract --all-potential-swift-keys` (lightweight, untyped) lists every literal that
  might be a key in a `__PotentialKeys` table: used once, by the audit, to find literals the typed
  extraction missed.
- `jq` 1.8.2 is installed (`/opt/homebrew/bin/jq`); `python3` too, not needed.
- Strings already go through the catalog's APIs almost everywhere (SwiftUI literals, 70+
  `String(localized:)` in app and Core, `LocalizedStringKey` parameters). Known gaps, fixed in
  Task 3: `MetadataReader` labels and units (`"Dimensions"`, `"50 mm"`, `"1/250 s"`), ternaries that
  make a `String` (`BatchView.swift:80` `"\(name) (edited)"`, `SettingsView.swift:214` `"None"`),
  `AboutView.swift:81` (`joined(separator: ", ")`), hand-built `"%"` in `StatusLine` and
  `BatchSteps`, and the `inflect: true` markup in `BatchImagesColumn.countLine`.
- Menu titles carry their key: `Button("Next  (→ or Space)")` in `ViewerView.swift`;
  `MenuKeys.swift` uses `MenuKey.parse` (Core) on the item's **localized** title to set the key
  equivalent while a menu is open. The `"  ("` separator, `" or "` and key names (`Space`, `F7`,
  `⌘⌫`) inside the parentheses are parsed, never shown.
- Arrow handling is in `ViewerView.handle(_:)` (`.leftArrow`/`.rightArrow`, plain and ⌥) and
  `handleChooser(_:_:)`; panning (`PanController.pan(dx:dy:)` in `ImageCanvas.swift`) is already
  physical. The toolbar uses `chevron.backward`/`chevron.forward`, which SF Symbols mirror in
  right-to-left layouts by themselves. The anchor grid in `BatchStepViews.swift:492` is already
  pinned `.leftToRight` (picture positions).
- Unverified (Task 1 checks it): that `swift build -Xswiftc -emit-localized-strings …` passes the
  flags through SwiftPM's driver for every file. Fallback if it doesn't: `xcrun xcstringstool extract
  --SwiftUI --modern-localizable-strings Sources/Featherview/*.swift Sources/FeatherviewCore/*.swift
  -o <dir>`. It is untyped, so literals passed to our own `LocalizedStringKey` parameters
  (`ToolbarButton`, `IntRow`, `SliderRow` …) are missed and must be listed by hand from
  `--all-potential-swift-keys`; record the switch in this plan if it happens.

## Decisions (made while planning; the maintainer asked not to be asked technical questions)

1. **Catalog location:** `Resources/Localizable.xcstrings`, not inside a target. No SwiftPM
   `resources:`; no `Bundle.module`. Core's `String(localized:)` keeps its default bundle
   (`Bundle.main` = the app; in tests the runner, which falls back to the English key).
2. **Extraction:** the compiler's typed extraction via `scripts/strings.sh`, run by hand (not by
   `bundle.sh`: a full extra build would cost every bundle a minute). It always deletes
   `.build/strings` first, because an incremental build only emits strings for files it recompiles
   and would leave deleted files' strings behind. Its own `--scratch-path` keeps the normal build
   cache untouched by the extra flags.
3. **Stale keys** (in the catalog, no longer in code; `sync` marks them `"extractionState" :
   "stale"`) fail the catalog test, naming them; whoever removed the string deletes the entry.
4. **Compiled format:** `--serialization-format binary` (smaller, quicker to load at launch).
   `bundle.sh` always creates `en.lproj` (empty unless English has plural variations) so macOS
   lists English among the app's languages. Info.plist gets `CFBundleDevelopmentRegion` `en` and
   `CFBundleLocalizations` with the 30 codes.
5. **Language codes** (lproj names): `en zh-Hans zh-Hant hi es ar fr pt-BR ru id de ja tr vi ko it
   th pl uk ms nl ro el hu sv cs ca he da fi` (spec order). Spanish is `es`, Portuguese is `pt-BR`.
6. **Info.plist strings** (`CFBundleTypeName` "Image", "PDF document", "Other image") stay English:
   macOS shows the type's own description for `public.image`, not ours, since we're an Alternate
   handler. `shortcut: document type names untranslated, add InfoPlist.xcstrings if Finder ever
   shows them`.
7. **Plurals instead of `inflect: true`:** automatic grammar agreement covers only a few languages;
   catalog plural variations work in all 30 and the test can check them. `countLine` becomes a plain
   `String(localized:)`; every string whose number counts a noun gets plural variations in English
   and in each language whose plural rules have more than `other`.
8. **Plural form rule** (checked by the test): every plural has `other`; in `zero`, `one` and `two`
   forms the count may be left out ("ملف واحد", "eine Datei"), except in `one` for fr, pt-BR, hi, ru
   and uk, where CLDR `one` also covers 0 or 21, 31 …: those keep the count ("%lld fichier");
   everything else matches the source.
   A whole-string plural is allowed only for a source with exactly one integer; strings with two
   counts use substitutions (`%#@name@`).
9. **Menu key hints:** translations keep the `"  (…)"` suffix byte for byte (`" or "`, `Space`, `F7`,
   `⌘⌫` stay English: they are parsed, never shown), except ← and → swap in `ar` and `he`. So the
   menu shows ← for Next there with no code change, and `MenuKey.parse` keeps working. The test
   checks it through `MenuKey.parse` itself.
10. **Arrows in strings:** inside parentheses an arrow names a key and swaps in `ar`/`he` (menu hints,
   tooltips like "Next image (→)"). Outside parentheses (the batch log's "a.jpg → a.png", whose file
   names are left-to-right text) arrows stay as in the source in every language.
11. **Which keys swap in Arabic and Hebrew:** every ← → that steps through things: next/previous
   image, ⌥ next/previous page, and the folder chooser (→ enters, ← goes up; mirrored there).
   Panning a zoomed image stays physical (spec). The direction is the SwiftUI environment's
   `layoutDirection` (it follows the app's language), not a setting.
12. **The canvas never mirrors:** `ImageCanvas`'s `NSScrollView` is pinned `.leftToRight`, so the
   picture, its scroll origin and drag direction are physical in every language. Picture-position
   labels ("Left:", "Top left") are about the picture, not the layout, and stay.
13. **Same word, two meanings:** where one English key is used in two senses that other languages
   word differently (rotation "Left"/"Right" vs. picture position "Left"/"Right"), the picture
   positions get their own keys via `LocalizedStringResource("anchor.left", defaultValue: "Left",
   comment: …)`. Elsewhere a `comment:` gives translators the context.
14. **Formatters:** percentages use `.formatted(.percent…)`, millimetres and seconds
   `Measurement(…).formatted(.measurement(width: .abbreviated, usage: .asProvided))`, lists
   `.formatted(.list(type: .and, width: .narrow))`. Pixel dimensions and counts inside localized
   format strings stay `%lld` (plural selection needs the integer). The exposure fraction
   "1/250 s" stays a localized format string (no formatter writes fractions).
15. **Not translated, ever:** "Featherview", format names (JPEG, WebP, PaintShop Pro …), rename and
   text placeholders (`{name}`, `{n}`, `{n:3}`, `{date}`, `{folder}`), file names, the version line
   and copyright (`Text(verbatim:)`). Keys with no letters at all ("%lld × %lld", "%lld / %lld",
   "%@ → %@") are marked `"shouldTranslate" : false`; the test rejects that mark on a key with letters.
16. **Translations are ours:** written by the task agents from their own knowledge, using the
   terms macOS uses in that language for Finder, Trash, Full Screen, Settings, Open, Save As, Quit,
   Minimize and Show Info. No reading of other apps' or the system's localization files (`.lproj`,
   `.loctable`, `.strings` under `/System` or `/Applications`): clean-room, and no copying.
17. **Merging parallel translation branches:** every translation task edits the same catalog, so
   git conflicts are certain. Languages are disjoint, so a JSON deep merge is exact; the recipe is
   in the wave plan. The `plan-wave` merger skips such branches ("not trivial"); the main session
   then merges them with the recipe.
18. **Preferences:** stays AppKit toolbar tabs (6 panes) unless Task 12 finds a German or another
   language's tab label cut off or the panes have grown past 7; then the plan's answer is a sidebar
   Settings window, decided and planned in the maintainer's session (not here).

## Global Constraints

- macOS 14.0 minimum; Swift 6 language mode, strict concurrency. No new dependency (`jq` is a
  maintainer tool used in two steps, never by `bundle.sh`, `swift build` or `swift test`).
- "One String Catalog (`Localizable.xcstrings`); every user-facing string goes through it,
  including error messages and the batch log."
- "Use leading/trailing, never left/right, in layout code; AppKit views use
  `userInterfaceLayoutDirection`. Never mirrored: the image itself, rotate symbols and their
  direction (rotate left stays counter-clockwise), crop coordinates."
- "Numbers, sizes, dates and units use system formatters, never hand-built strings."
- "Keyboard shortcuts stay the same in every language, except ← and → in Arabic and Hebrew:
  they follow the mirrored screen, so ← is next image and → is previous (the "next" chevron
  points left there). ↑ ↓ Space Page Up/Down Backspace are unchanged; panning a large image
  stays physical (← pans left)."
- "File names produced by rename templates are not translated."
- Never build sentences by concatenating pieces: one localized format string with arguments.
- TDD for FeatherviewCore and the catalog test; the app is checked by hand (Task 12, main session).
- Commit messages: conventional commits, no AI attribution lines, no dates in docs or comments.
- `shortcut:` comments for known limits, in the form `shortcut: <limit>, <when to upgrade>`.
- Clean-room: no other product's translations, help text or UI text, in any language.

## Review Focus

- A translator rewrites a menu hint ("Weiter  (→ oder Leertaste)"): the menu loses its shortcut
  column and nobody notices, because the key itself still works (ViewerView handles it). Pinned in Task 4
  (`menuKeyHintMustStay`) through `MenuKey.parse`.
- Arabic plurals with zero/one/two/few/many/other, Russian one/few/many/other: a form missing, empty
  or with a `%@` where the source has `%lld` crashes or garbles the batch summary. Pinned in Task 4
  (`pluralWithoutOtherIsReported`, `mismatchedSpecifierIsReported`, `pluralOneMayOmitCount`).
- Reordered arguments ("%2$@ … %1$lld") in a translation are fine; a swapped *type* is not. Pinned
  in Task 4 (`positionalSpecifiersMatchByIndex`).
- Hebrew/Arabic: → pressed with an image zoomed in pans right (physical), but at the edge it goes to
  the *previous* image. Pinned in Task 2 (`arrowStepsFollowLayoutDirection`) plus Task 12's check.
- A string added after this milestone that nobody translates: the catalog test fails in CI for every
  language until it is. Pinned by Task 4 (`shippedCatalogIsComplete`, enabled in Task 11).

## Wave plan

| Wave | Tasks | Why |
|---|---|---|
| A | 1, 2 | tooling + bundle (scripts, Info.plist, catalog) and the ← → swap (Core + viewer): disjoint files |
| B | 3, 4 | string audit (owns the catalog and app files) and the catalog test (new test files only); both need Task 1 |
| C | 5, 6, 7, 8, 9, 10 | translations, five or four languages each; catalog only; merged with the recipe below |
| D | 11 | turn on the all-30 check, README, full suite |
| E | 12 | GUI check by the main session (needs the screen: ask the maintainer first), roadmap done |

**Merge recipe for wave C** (main session, in the main checkout on `main`, one branch at a time):

```sh
git merge --no-ff --no-commit <branch>      # conflicts only in Resources/Localizable.xcstrings
git show :2:Resources/Localizable.xcstrings > /tmp/fv-ours.json
git show :3:Resources/Localizable.xcstrings > /tmp/fv-theirs.json
jq -s '.[0] * .[1]' /tmp/fv-ours.json /tmp/fv-theirs.json > Resources/Localizable.xcstrings
scripts/strings.sh                          # rewrites the file in Xcode's formatting
swift test --filter StringCatalogTests
git add Resources/Localizable.xcstrings && git commit --no-edit
```

The first branch usually merges cleanly; use the recipe only when the catalog conflicts.
`*` merges objects recursively, so each key's `localizations` gets both sides' languages. A branch
that touched any other file is not a translation branch: merge it normally.

---

### Task 1: Catalog, extraction script, bundle and Info.plist

**Files:**
- Create: `scripts/strings.sh`
- Create: `Resources/Localizable.xcstrings` (by the script)
- Modify: `scripts/bundle.sh` (after the `Acknowledgements.txt` copy)
- Modify: `Resources/Info.plist`
- Modify: `AGENTS.md` (Commands block: one line for `scripts/strings.sh`)

**Interfaces:**
- Produces: `scripts/strings.sh` (no arguments; exit status non-zero when the build fails);
  `Resources/Localizable.xcstrings` with `"sourceLanguage" : "en"`; bundle layout
  `build/Featherview.app/Contents/Resources/<lang>.lproj/Localizable.strings[dict]`;
  Info.plist `CFBundleLocalizations` = the 30 codes of Decision 5, in that order.

- [x] **Step 1: Write `scripts/strings.sh`** (executable, `#!/bin/sh`, `set -eu`, `cd "$(dirname "$0")/.."`, the header comment says what it does and that it is run by hand after changing UI text):

```sh
OUT=.build/strings
rm -rf "$OUT"                                   # full build: incremental builds only emit recompiled files
mkdir -p "$OUT/data"                            # the compiler doesn't create it
swift build --product Featherview --scratch-path "$OUT/build" \
  -Xswiftc -emit-localized-strings -Xswiftc -emit-localized-strings-path -Xswiftc "$PWD/$OUT/data"
[ -f Resources/Localizable.xcstrings ] ||
  printf '{"sourceLanguage":"en","strings":{},"version":"1.0"}\n' > Resources/Localizable.xcstrings
xcrun xcstringstool sync Resources/Localizable.xcstrings --stringsdata "$OUT"/data/*.stringsdata
```

- [x] **Step 2: Run it** — `scripts/strings.sh` (takes a minute or two; give it a 600 s timeout).
  Expected: `.build/strings/data/ViewerView.stringsdata` and `BatchConverter.stringsdata` exist;
  `xcrun xcstringstool print Resources/Localizable.xcstrings | grep -c .` prints well over 300;
  `xcrun xcstringstool print Resources/Localizable.xcstrings | grep -F 'Next  (→ or Space)'` and
  `grep -F "Can't open %@"` both match. If the flags don't reach the compiler (no `.stringsdata`
  files), switch to the fallback in "Checked while planning", note it there, and continue.
- [x] **Step 3: Run it again** — `git diff --stat Resources/Localizable.xcstrings` shows no change
  (the script is idempotent).
- [x] **Step 4: bundle.sh** — after the Acknowledgements copy add, with a one-line comment
  (catalog compiled into one `.lproj` per language; `en.lproj` always, so English is listed):

```sh
xcrun xcstringstool compile Resources/Localizable.xcstrings --output-directory "$APP/Contents/Resources" \
  --serialization-format binary
mkdir -p "$APP/Contents/Resources/en.lproj"
```

- [x] **Step 5: Info.plist** — add `CFBundleDevelopmentRegion` = `en` and `CFBundleLocalizations`
  = array of the 30 codes (Decision 5). `plutil -lint Resources/Info.plist` → OK.
- [x] **Step 6: Verify the bundle** — `scripts/bundle.sh debug`, then `ls build/Featherview.app/Contents/Resources`
  shows `en.lproj`, and `plutil -p build/Featherview.app/Contents/Info.plist | grep -A31 CFBundleLocalizations`
  lists 30 codes. (Translations come in wave C, so only `en.lproj` exists yet.)
- [x] **Step 7: AGENTS.md** — in Commands add `scripts/strings.sh   # after changing UI text: extract strings into Resources/Localizable.xcstrings`.
- [x] **Step 8: Commit** — `git add scripts/strings.sh scripts/bundle.sh Resources/Localizable.xcstrings Resources/Info.plist AGENTS.md && git commit -m "feat: string catalog, extraction script, bundled localizations"`

### Task 2: ← and → follow the layout direction

**Files:**
- Modify: `Sources/FeatherviewCore/ViewerKey.swift`
- Test: `Tests/FeatherviewCoreTests/ViewerKeyTests.swift`
- Modify: `Sources/Featherview/ViewerView.swift` (`handle(_:)`, `handleChooser(_:_:)`)
- Modify: `Sources/Featherview/ImageCanvas.swift` (`makeNSView`, where `scrollView` is set up)

**Interfaces:**
- Produces: `ViewerKey.arrowGoesForward(isRightArrow: Bool, rightToLeft: Bool) -> Bool`
  (`public static`): true when the arrow means next/enter.

- [x] **Step 1: Write the failing test** `arrowStepsFollowLayoutDirection`:

```swift
@Test func arrowStepsFollowLayoutDirection() {
    #expect(ViewerKey.arrowGoesForward(isRightArrow: true, rightToLeft: false))
    #expect(!ViewerKey.arrowGoesForward(isRightArrow: false, rightToLeft: false))
    #expect(!ViewerKey.arrowGoesForward(isRightArrow: true, rightToLeft: true))   // → is previous in Arabic/Hebrew
    #expect(ViewerKey.arrowGoesForward(isRightArrow: false, rightToLeft: true))
}
```

- [x] **Step 2: Run** `swift test --filter ViewerKeyTests` → FAIL (no member `arrowGoesForward`).
- [x] **Step 3: Implement** in `ViewerKey.swift` with a doc comment quoting the spec rule (one expression: `isRightArrow != rightToLeft`).
- [x] **Step 4: Run** `swift test --filter ViewerKeyTests` → PASS.
- [x] **Step 5: Wire it in `ViewerView`** — `@Environment(\.layoutDirection) private var layoutDirection`;
  `let rtl = layoutDirection == .rightToLeft`. Plain ← →: the `pan(dx:)` call is unchanged
  (physical), and when it returns false the arrow goes `arrowGoesForward(…) ? model.next() : model.previous()`.
  ⌥← ⌥→: same with `nextPage()`/`previousPage()`. Chooser: forward → `chooserEnter()`, else
  `chooserUp()`; Space still enters. ↑ ↓ unchanged.
- [x] **Step 6: Pin the canvas** — in `ImageCanvas.makeNSView` set
  `scrollView.userInterfaceLayoutDirection = .leftToRight` with the comment
  `// The picture never mirrors (spec "Languages"): scroll origin and dragging stay physical.`
- [x] **Step 7: Build** `swift build` → succeeds; `swift test` → all pass.
- [x] **Step 8: Commit** — `git commit -m "feat: arrow keys follow the mirrored layout in right-to-left languages"` (the four files).

### Task 3: String audit and English source

**Files:**
- Modify: `Sources/FeatherviewCore/MetadataReader.swift`, `Tests/FeatherviewCoreTests/MetadataReaderTests.swift`
- Modify: `Sources/FeatherviewCore/StatusLine.swift`, `Tests/FeatherviewCoreTests/StatusLineTests.swift`
- Modify: `Sources/FeatherviewCore/BatchSteps.swift`, `Tests/FeatherviewCoreTests/BatchStepsTests.swift`
- Modify: `Sources/Featherview/BatchImagesColumn.swift` (`countLine`), `BatchView.swift:80`,
  `SettingsView.swift:214`, `AboutView.swift:81`, `BatchStepViews.swift` (`name(_ anchor:)`),
  and any further file the audit (Step 5) finds
- Modify: `Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `scripts/strings.sh` (Task 1).
- Produces: a catalog whose keys are every user-facing string, English plural variations where a
  number counts a noun, `shouldTranslate: false` on letter-free keys, no stale keys. Task 4's test
  runs on it; Tasks 5–10 translate it.

- [x] **Step 1: Failing tests for the Core formatters** — in `MetadataReaderTests`, the expected
  values come from the formatters (the suite runs in the developer's locale):
  `Focal length` == `Measurement(value: 50, unit: UnitLength.millimeters).formatted(.measurement(width: .abbreviated, usage: .asProvided))`,
  exposure `2` == `Measurement(value: 2, unit: UnitDuration.seconds).formatted(.measurement(width: .abbreviated, usage: .asProvided))`;
  `"1/250 s"` stays as is. In `StatusLineTests` the zoom field == `0.46.formatted(.percent)`; in
  `BatchStepsTests` the resize summary == `0.5.formatted(.percent)`.
- [x] **Step 2: Run** `swift test --filter "MetadataReaderTests|StatusLineTests|BatchStepsTests"` →
  the formatter cases FAIL where the formatter's output differs from today's hand-built string
  (en_US: "46%" vs "46 %"); in de_DE some may already pass, which is expected. Run once with
  `LANG=en_US.UTF-8 swift test --filter …` if none fail.
- [x] **Step 3: Implement** — `MetadataReader`: labels through `String(localized:)` (with
  `comment: "Info panel label"`), mm and decimal seconds through `Measurement` (Decision 14),
  `"1/\(n) s"` as `String(localized:comment: "exposure time, a fraction of a second")`.
  `StatusLine` zoom and `BatchSteps` percent through `.formatted(.percent…)`; keep "MP" as the
  localized `"\(…) MP"`. Tests that look up labels by English name keep working (the test runner
  has no translations).
- [x] **Step 4: Run** the three suites → PASS.
- [x] **Step 5: Find the rest** — `scripts/strings.sh`, then

```sh
xcrun xcstringstool extract --all-potential-swift-keys Sources/Featherview/*.swift Sources/FeatherviewCore/*.swift -o .build/strings/potential
jq -r '.tables.__PotentialKeys[]?.key' .build/strings/potential/*.stringsdata | sort -u > .build/strings/potential.txt
jq -r '.tables.Localizable[]?.key' .build/strings/data/*.stringsdata | sort -u > .build/strings/extracted.txt
comm -23 .build/strings/potential.txt .build/strings/extracted.txt
```

  Go through every line: a literal a person can read in the UI (labels, alerts, accessibility
  labels, tooltips, log lines, error messages) must reach the catalog; SF Symbol names, keys,
  identifiers, `UserDefaults` keys, file extensions, format names, placeholders and log/signpost
  text don't. Fix the known gaps listed in "Checked while planning": `countLine` →
  `String(localized: "\(count) files · \(size)")` (drop the comment about markup);
  `"\(name) (edited)"` → `String(localized:)`; `"None"` → `String(localized:)`; the format list →
  `.formatted(.list(type: .and, width: .narrow))`; the nine anchor names → their own keys
  (Decision 13: `"anchor.topLeft"` … `"anchor.bottomRight"`, `defaultValue` the current English,
  `name(_:)` returns `LocalizedStringResource`). Add `comment:` to keys that are a single word or
  a fragment ("on", "Same format", "page 1 of %lld", "Empty", "Left", "Right") saying where it shows.
- [x] **Step 6: Re-extract** — `scripts/strings.sh`; delete every entry the sync marked
  `"extractionState" : "stale"` (by hand in the JSON, or `jq 'del(.strings[] | select(.extractionState == "stale"))'`
  then `scripts/strings.sh` to reformat).
- [x] **Step 7: English source plurals** — for every key whose integer counts a noun ("%lld files ·
  %@", "%lld converted, %lld failed", "%lld converted, %lld failed, %lld not converted" and any the
  audit added), add an `en` localization with plural variations `one`/`other` (two counts:
  substitutions, Decision 8). Mark letter-free keys `"shouldTranslate" : false` (Decision 15).
  Re-run `scripts/strings.sh` (keeps them; formatting only).
- [x] **Step 8: Verify** — `swift build && swift test` pass; `scripts/bundle.sh debug` succeeds and
  `en.lproj/Localizable.stringsdict` now exists in the bundle.
- [x] **Step 9: Commit** — `git commit -m "feat: every user-facing string in the catalog, system formatters for units"`.

### Task 4: Catalog check test

**Files:**
- Create: `Tests/FeatherviewCoreTests/StringCatalog.swift` (test-target helper: model + checks)
- Create: `Tests/FeatherviewCoreTests/StringCatalogTests.swift`

**Interfaces:**
- Consumes: `MenuKey.parse(_:)` (Core, public); `Resources/Localizable.xcstrings` and
  `Resources/Info.plist`, found from `#filePath` (three `deletingLastPathComponent()` up).
- Produces (internal to the test target):
  ```swift
  struct StringCatalog: Decodable {          // the xcstrings JSON: sourceLanguage, strings
      static let languages: [String]         // Decision 5's 30 codes, "en" first
      static let shippedURL: URL
      static func load(_ url: URL) throws -> StringCatalog
      static func decode(_ json: String) throws -> StringCatalog   // for inline test catalogs
      var presentLanguages: Set<String>      // every language some key has, plus "en"
      /// One short sentence per problem, naming the key and language.
      func problems(languages: some Collection<String>) -> [String]
  }
  ```
  Model: `Entry { extractionState: String?, shouldTranslate: Bool?, localizations: [String: Localization]? }`,
  `Localization { stringUnit: StringUnit?, variations: Variations?, substitutions: [String: Substitution]? }`,
  `StringUnit { state, value }`, `Variations { plural: [String: Localization]? }`,
  `Substitution { argNum: Int?, formatSpecifier: String, variations: Variations }`.

**What `problems(languages:)` checks** (for each key, skipping `shouldTranslate == false` except
check 10; the *source text* is the `en` localization's value — its `other` form for plurals — else
the key):
1. stale entry (`extractionState == "stale"`);
2. a listed language (other than `en`) has no localization;
3. a leaf (`stringUnit`, every plural form, every substitution form) has an empty value or a state
   other than `translated`;
4. a plural has no `other` form;
5. format specifiers differ from the source's: parse `%(?:(\d+)\$)?[-+ #0']*\d*(?:\.\d+)?(?:hh|h|ll|l|q|z|t|j|L)?([@dDiuUxXoOfFeEgGaAcCsSp])`
   (skip `%%`), give unnumbered ones running indices from 1, normalize the type (`d i u lld …` →
   integer, `f e g …` → double, `@` → object), compare as `[index: type]`; in `zero`/`one`/`two`
   forms the plural's own integer may be missing; `%#@name@` tokens compare as a set of names;
6. "Featherview" in the source → in the translation;
7. `MenuKey.parse(source)` non-nil → `MenuKey.parse(translation)` non-nil with equal `modifiers`
   and `key`, where for `ar`/`he` the source's `"\u{F702}"`/`"\u{F703}"` are swapped first;
8. arrows: inside `(…)` the counts of ← and → equal the source's, swapped for `ar`/`he`; outside
   parentheses equal the source's in every language;
9. `{…}` placeholders (`\{[a-z]+(?::\d+)?\}`) equal the source's as a set;
10. `shouldTranslate == false` on a key containing a letter.

- [x] **Step 1: Write the failing unit tests** on small inline catalogs (each builds a one-key JSON,
  `#expect` on `problems(languages: ["en", "de"])` or `["en", "ar"]`): `completeCatalogHasNoProblems`,
  `missingLanguageIsReported`, `emptyTranslationIsReported`, `untranslatedStateIsReported`,
  `mismatchedSpecifierIsReported` (`"Can't open %@"` → `"%lld lässt sich nicht öffnen"`),
  `positionalSpecifiersMatchByIndex` (`"%@ in %lld"` → `"%2$lld: %1$@"` passes; `"%2$@: %1$lld"` fails),
  `pluralOneMayOmitCount` (ar `one` "ملف واحد" passes, ar `other` without `%lld` fails),
  `pluralWithoutOtherIsReported`, `brandNameMustStay`, `menuKeyHintMustStay`
  (de `"Weiter  (→ oder Leertaste)"` fails, `"Weiter  (→ or Space)"` passes; ar `"التالي  (← or Space)"`
  passes, ar `"التالي  (→ or Space)"` fails), `arrowsSwapInRightToLeftOnly` (`"Next image (→)"`:
  de with ← fails; he with ← passes; `"%@ → %@"`-style text outside parentheses swapped in he fails),
  `placeholdersInBracesStay`, `staleKeyIsReported`, `untranslatableKeyWithLettersIsReported`.
- [x] **Step 2: Run** `swift test --filter StringCatalogTests` → FAIL (no `StringCatalog`).
- [x] **Step 3: Implement `StringCatalog`** (Decodable model, `load`, `decode`, `presentLanguages`,
  `problems`), each problem a sentence like `"de: \"Can't open %@\" has %lld where the source has %@"`.
- [x] **Step 4: Add the shipped-catalog tests:**

```swift
@Test func shippedCatalogHasNoProblemsInItsLanguages() throws {
    let catalog = try StringCatalog.load(StringCatalog.shippedURL)
    #expect(catalog.problems(languages: catalog.presentLanguages) == [])
}
@Test(.disabled("translations land in wave C; Task 11 enables this"))
func shippedCatalogIsComplete() throws {
    let catalog = try StringCatalog.load(StringCatalog.shippedURL)
    #expect(catalog.problems(languages: StringCatalog.languages) == [])
}
@Test func infoPlistListsTheLanguages() throws {
    // Resources/Info.plist's CFBundleLocalizations == StringCatalog.languages
}
```

- [x] **Step 5: Run** `swift test --filter StringCatalogTests` → PASS (one skipped). If
  `shippedCatalogHasNoProblemsInItsLanguages` fails on stale keys or `shouldTranslate` marks, that
  is Task 3's catalog: report it, don't edit the catalog here.
- [x] **Step 6: Commit** — `git commit -m "test: catalog check for languages, placeholders, menu keys and arrows"`.

### Translation tasks (5–10): the shared steps

Each task translates every key of `Resources/Localizable.xcstrings` into its languages. Rules
(on top of Decisions 8–10, 15, 16):

- Keep every format specifier, `%#@…@` token, `{placeholder}`, "Featherview", format name and the
  `"  (…)"` menu-hint suffix exactly (Decision 9); ← → inside parentheses swap only in `ar`/`he`.
- Use the terms macOS uses in that language (Decision 16), its title/sentence capitalization for
  menus and buttons, its quotation marks, and its ellipsis character "…". Keep strings about as short
  as the English where a label sits in a toolbar, a tab or a column header.
- Plurals: give each key that has `en` plural variations the forms the language's plural rules use
  (CLDR: e.g. `ru uk pl cs` one/few/many/other, `ar` zero/one/two/few/many/other, `he` one/two/other,
  `ro` one/few/other, `zh-Hans zh-Hant ja ko th vi id ms` other only). Every form non-empty.
- State `"translated"` on every leaf. The `comment` fields say where a string shows: read them.

Steps for each task:

- [ ] **Step 1:** For each language, write `.build/l10n/<lang>.json`: an object mapping each catalog
  key (from `xcrun xcstringstool print Resources/Localizable.xcstrings`, skipping `shouldTranslate: false`)
  to its localization object (`{"stringUnit":{"state":"translated","value":"…"}}` or
  `{"variations":{"plural":{…}}}`).
- [ ] **Step 2:** Fold each into the catalog:
  `jq --arg l <lang> --slurpfile t .build/l10n/<lang>.json '.strings |= with_entries(if $t[0][.key] then .value.localizations[$l] = $t[0][.key] else . end)' Resources/Localizable.xcstrings > .build/l10n/out.json && mv .build/l10n/out.json Resources/Localizable.xcstrings`,
  then `scripts/strings.sh` (reformats; must add no keys and mark none stale).
- [ ] **Step 3:** `swift test --filter StringCatalogTests` → PASS, and
  `xcrun xcstringstool compile Resources/Localizable.xcstrings -o .build/l10n/compiled -l <lang>`
  writes `<lang>.lproj` for each of the task's languages.
- [ ] **Step 4:** Read your translations once more against the English, for meaning (not just form),
  then commit: `git commit -m "feat: <languages> translations"` (only `Resources/Localizable.xcstrings`).

### Task 5: German, French, Spanish, Italian, Portuguese (Brazil)

Languages: `de fr es it pt-BR`. German is the long-string check in Task 12: prefer the shorter
correct word in toolbar and tab labels.

### Task 6: Dutch, Swedish, Danish, Finnish, Catalan

Languages: `nl sv da fi ca`.

### Task 7: Russian, Ukrainian, Polish, Czech, Greek

Languages: `ru uk pl cs el`. Greek's question mark is ";".

### Task 8: Arabic, Hebrew, Turkish, Hungarian, Romanian

Languages: `ar he tr hu ro`. In `ar` and `he` swap ← → inside parentheses (menu hints and
tooltips, Decisions 9–10), never outside. Arabic uses "،" as its comma and "؟" as its question mark.

### Task 9: Chinese (Simplified), Chinese (Traditional), Japanese, Korean

Languages: `zh-Hans zh-Hant ja ko`. `zh-Hant` follows Taiwan's macOS vocabulary, not a character
conversion of `zh-Hans`. Full-width punctuation where the language uses it, but menu-hint
suffixes stay ASCII (Decision 9).

### Task 10: Hindi, Thai, Vietnamese, Indonesian, Malay

Languages: `hi th vi id ms`.

### Task 11: All 30 languages required, README

**Files:**
- Modify: `Tests/FeatherviewCoreTests/StringCatalogTests.swift` (remove the `.disabled` trait)
- Modify: `README.md` (feature list)

- [x] **Step 1:** Remove the `.disabled(…)` trait from `shippedCatalogIsComplete`.
- [x] **Step 2:** `swift test` → all pass, none skipped in `StringCatalogTests`. A failure names the
  key and language: fix the translation in the catalog (that language's rules above).
- [x] **Step 3:** README feature list, after the EXIF line: `- In 30 languages, with right-to-left
  layout in Arabic and Hebrew` — wording may be adjusted, no language list (the spec has it).
- [x] **Step 4:** `scripts/bundle.sh release` succeeds; `ls build/Featherview.app/Contents/Resources | grep -c lproj` → 30.
- [x] **Step 5: Commit** — `git commit -m "test: every catalog key in all 30 languages"` (test + README).

### Task 12: Check in the app (main session; needs the screen, ask the maintainer first)

Workflow agents can't use the screen: the main session does this after asking the maintainer for
the go (memory: screen bursts). Build: `scripts/bundle.sh debug`. Launch each language with
`open -n -a build/Featherview.app --args -AppleLanguages '(ar)'` (then `'(he)'`, `'(de)'`) on a
folder of sample images (`run-featherview` skill), quitting with ⌘Q between runs.

- [x] **Arabic and Hebrew, viewer:** toolbar order mirrored, the next chevron points left; ← shows
  the next image, → the previous, ⌥← next page in a PDF; zoomed in, → pans right and at the edge goes
  to the previous image; the image itself, rotate symbols and rotate direction are not mirrored
  (if `rotate.left`/`rotate.right` flip, pin those images `.leftToRight`); the info panel and status
  bar read right to left; the folder chooser enters with ← and goes up with →; the View/Image menu
  shows ← beside Next.
- [x] **Arabic and Hebrew, batch window:** columns, lists, progress bar and step list mirrored; the
  crop anchor grid and border sides not; a run's log lines and summary read correctly (file names
  left to right).
- [x] **Arabic and Hebrew, Preferences, About, Save As panel, F7/F8 panel, alerts:** mirrored, no
  clipped text.
- [x] **German, long strings:** viewer toolbar labels (Customize Toolbar sheet too), menus, batch
  step names and settings rows, the Save As accessory, alerts: nothing clipped or overlapping.
  **Preferences:** all 6 toolbar tab labels fit without truncation. If any is truncated (in German,
  or seen in another language), or the panes now exceed 7, Preferences moves to a sidebar settings
  window: stop here, record it in `docs/roadmap.md` as a follow-up for the maintainer's session to
  decide and plan.
- [x] **Launch budget:** with `-AppleLanguages '(de)'`, cold launch with a 12 MP JPEG stays within
  AGENTS.md's budget (log stream line, after a ⌘Q quit).
- [x] **Fix what this finds** (each fix its own commit, `fix:`), then set `docs/roadmap.md` row 6
  to `done` and commit `docs: milestone 6 done after manual QA`.
