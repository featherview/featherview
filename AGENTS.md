# Featherview — agent guide

A fast, keyboard-driven image viewer for macOS with batch conversion. Open source.
Mac only. Native Swift.

- What to build: `docs/spec.md` (the product spec, the only source of requirements)
- In what order: `docs/roadmap.md` (five milestones; one detailed plan per milestone)
- How to build it: `docs/superpowers/plans/` (task-by-task plans, newest first by date)

## Clean-room rules (non-negotiable)

Featherview is a clean-room project inspired by the *workflow* of classic Windows viewers.
It must never derive from another product's code or assets. Its *behaviour* may be observed.

- The reference viewer runs in the maintainer's Windows VM (installed by the maintainer) and may
  be **observed black-box**: use it as a user would and note what happens. Screenshots of its
  window only (never the whole screen) go to `research/screenshots/`, which is gitignored and
  never committed. See the `observe-reference` skill.
- Do not open, download, read, disassemble or decompile any other viewer's binaries, plugins,
  installers, help files or bundled files. Do not browse its website, help or FAQ.
- Observed behaviour goes into `docs/parity.md` in our own words, then into `docs/spec.md` once
  the maintainer accepts it for a release. `docs/spec.md` stays the only source of requirements;
  if it is silent, ask the maintainer or decide from first principles and record it there.
- Matching single-key shortcuts is allowed (it's behaviour, and helps people switching over).
  Do not copy icons, images, UI text, help text, dialog or settings layouts — not even by
  cropping or tracing a screenshot. Our UI is designed for the Mac.
- The name "IrfanView" may appear only in README.md and on the website (featherview.github.io),
  in a "not affiliated" disclaimer, a plain "alternative to" description or a thank-you to its
  author. Never in code, UI, bundle names or commit messages.
- No cat imagery in icons or branding.

## Stack and decisions (fixed — do not change without the maintainer)

| Topic | Decision |
|---|---|
| Language | Swift 6, strict concurrency (the package's default language mode) |
| UI | SwiftUI app shell, AppKit where SwiftUI lacks something (open panels, full screen) |
| Imaging | ImageIO first (decode/encode/metadata). A third-party codec only for a format ImageIO can't handle (today: WebP encoding; JPEG XL encoding in v2) |
| Dependencies | Open-source codec libraries are allowed if all hold: permissive licence (BSD/MIT/Apache/zlib), built from source by SwiftPM (C target or package, no prebuilt binaries), used only when that format is read or written, and no measurable cost to the performance budgets (launch, browsing, memory). Anything else: ask first. Record each one in README.md with its licence. |
| Build | Swift Package Manager + `scripts/bundle.sh` (no .xcodeproj) |
| Tests | Swift Testing (`import Testing`, `@Test`, `#expect`) in `Tests/FeatherviewCoreTests` |
| Min macOS | 14.0 (Sonoma) |
| Bundle ID | `net.mynetx.featherview` — never change it: macOS keys settings and permissions to it |
| Public URL | `featherview.mynetx.net` — the update feed (`appcast.xml`, Sparkle format) lives here, never on github.io |
| Repo | github.com/mynetx/featherview (may move to the `featherview` org later; GitHub redirects) |
| License | MIT, see `LICENSE` |

## Commands

Full Xcode must be installed and selected (`sudo xcode-select -s /Applications/Xcode.app`).
With only the Command Line Tools, `swift build` of the core works, but `swift test` fails
(Swift Testing macros missing) and the SwiftUI app fails (`@State` macro plugin missing).

```sh
swift build                      # debug build of everything
swift test                       # all tests
swift test --filter ImageListTests   # one suite
scripts/bundle.sh debug          # build/Featherview.app (ad-hoc signed)
scripts/strings.sh               # after changing UI text: extract strings into Resources/Localizable.xcstrings
open build/Featherview.app
open -a build/Featherview.app ~/Pictures/some.jpg   # open a file with it
swift run -c release featherview-bench corpus /tmp/fv   # generated test images, then: decode /tmp/fv, browse /tmp/fv/browse
swift run -c release featherview-bench thumbnail <dir>   # Finder's thumbnails through the installed app's extension
pluginkit -m -v -p com.apple.quicklook.thumbnail         # which copy of the app macOS takes them from
```

## Layout

```
Sources/FeatherviewCore/   pure logic, no SwiftUI/AppKit — everything here is unit-tested
  Formats/                 own decoders and encoders (QOI, PCX, XCF, …, WebP) and their shared pieces
  Imaging/                 decode, encode, Save As, cache, metadata, Quick Look support
  Viewer/                  image list, folders, move/copy, keys, zoom, status bar
  Batch/                   batch settings, steps, render pipeline, converter
  App/                     settings, appearance, About, default viewer, disk image art
Sources/Featherview/       the app: views, menus, keyboard, windows (thin, manually tested)
  Viewer/ Batch/ Windows/ Design/
Sources/FeatherviewThumbnail/, Sources/FeatherviewPreview/
                           Finder thumbnail and Quick Look preview extensions (scripts/bundle.sh
                           wraps each into an .appex; Info.plists and entitlements in Resources/QuickLook/)
Sources/CJPEGXR/           jxrlib (vendored C, not edited) and the small C shim JPEGXRDecoder calls
Sources/FeatherviewBench/  featherview-bench (timings without a window); FeatherviewDMG: disk image art
Tests/FeatherviewCoreTests/ Swift Testing suites, same folders as FeatherviewCore; Fixtures.swift
                           generates test images
Resources/Info.plist       bundle metadata, copied by scripts/bundle.sh
docs/spec.md               product spec
docs/parity.md             behaviour observed in the reference viewer (not requirements)
docs/roadmap.md            milestones and which plan implements each
docs/superpowers/plans/    implementation plans
```

Rule of thumb: if logic can be tested without a window, it belongs in FeatherviewCore.

## Design system

- Tokens (colours, elevation, type, metrics, radii, motion): `Sources/Featherview/Design/Theme.swift`.
- Spec: `docs/DESIGN.md`; artboards in `docs/design/canvas/project/`; source canvas
  <https://claude.ai/artifact/MBFkpbRchvBUixdnsAXveQ>.
- Never hard-code a colour, shadow, radius or duration outside `Theme.swift` (fit arithmetic keeps its
  numbers in `CanvasInsets`, which `Theme` names).

## Performance budgets (treat a regression as a bug)

| Budget | Target |
|---|---|
| Cold launch with a file to first image on screen | < 350 ms (12 MP JPEG, Apple Silicon; AppKit + SwiftUI alone take ~300 ms to show the window; with Liquid Glass ~385 ms, accepted for milestone 3 until the own-look pass sets the budget again). Measured after a normal quit (no window restored): ~380 ms (was ~520 ms, issue #2) |
| Next/previous image when prefetched | no visible delay (≈ 20 ms to swap is fine; `Navigate` p50 19 ms, p95 25 ms) |
| Next/previous image, not prefetched | < 150 ms (12 MP JPEG; `Navigate` ~107 ms landscape, ~61 ms portrait) |
| Opening a folder of 10,000 files | < 500 ms to first image, UI never blocks |
| Memory while browsing | bounded by the 8-image cache, decoded to fit the screen per axis (rounded up to JPEG's next halving step, at most 2× per side) |

How: decode off the main thread to fit the screen per axis, rounded up to full, ½, ¼ or ⅛ size (any size in between costs a slow resample; see `ImageDecoder.decodeSize`); HEIC/HEIF and own formats decode at the exact size instead (no slower, fewer bytes), prefetch 2 neighbours each
way, never touch file contents while scanning a folder. Next/previous budgets are measured as the `Navigate` signpost (from `show()`, right after the key press, until Core Animation has
committed the image, what the user sees), not the log line. Measure: the app logs how long each image
took to appear — `log stream --level debug --predicate 'subsystem == "net.mynetx.featherview"'`.
Without a window: `swift run -c release featherview-bench decode <dir>` (fit and full-size decode times; `--json` / `--baseline` to compare) and `browse <dir>/browse --interval-ms 300` (or 30, a held key).
Instruments' Points of Interest shows the `Decode`, `Scan` and `Navigate` signposts and the `FirstImage` event (`Signposts.swift`).
Use Instruments (Time Profiler) to find where time goes. Measure launches after a real quit (⌘Q), not after `pkill`: a killed app gets its window
restored, which hides ~140 ms that every user who quit normally pays.

## Conventions

- TDD for FeatherviewCore: failing test first, then code. Test images come from `Fixtures`,
  never committed binaries.
- Never lose user data: write to a temp file and swap in; never overwrite existing files in
  batch output; delete means move to Trash.
- User-facing errors are short sentences naming the file ("Can't open IMG_1234.jpg"), never
  raw error dumps; one bad file never stops browsing or a batch.
- User-facing text is translatable (spec "Languages"): SwiftUI string literals already are; anything
  else uses `String(localized:)`. Never build sentences by concatenating pieces.
- Layout uses leading/trailing, never left/right, so right-to-left languages mirror the window.
- Keep `shortcut:` comments for known limits, in the form `shortcut: <limit>, <when to upgrade>`.
- Commit messages: conventional commits (`feat:`, `fix:`, `test:`, `docs:`, `chore:`).
- No AI attribution in commits, PRs or issues: no `Claude-Session:`, `Co-Authored-By:` or session links
  (applies to the website repo too).

## Out of scope for v1

Plugins, interactive painting/editing (batch operations are in, see spec), scanning, OCR, printing, slideshows with effects,
animation playback (v2: spec "Animation"), lossless JPEG crop, video, Windows/Linux, auto-update (v1 only tells about a new version, spec "Updates").
