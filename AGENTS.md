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
- The name "IrfanView" may appear only in README.md and on the website (featherview.mynetx.net),
  in a "not affiliated" disclaimer, a plain "alternative to" description or a thank-you to its
  author. Never in code, UI, bundle names or commit messages.
- No cat imagery in icons or branding.

## Stack and decisions (fixed — do not change without the maintainer)

| Topic | Decision |
|---|---|
| Language | Swift 6, strict concurrency (the package's default language mode) |
| UI | SwiftUI app shell, AppKit where SwiftUI lacks something (open panels, full screen) |
| Imaging | ImageIO first (decode/encode/metadata). A third-party codec only for a format ImageIO can't handle (today: WebP and JPEG XL encoding) |
| Dependencies | Open-source codec libraries are allowed if all hold: permissive licence (BSD/MIT/Apache/zlib), built from source by SwiftPM (C target or package, no prebuilt binaries), used only when that format is read or written, and no measurable cost to the performance budgets (launch, browsing, memory). Sparkle (MIT, its SwiftPM binary package) for automatic updates. Anything else: ask first. Record each one in README.md with its licence. |
| Build | Swift Package Manager + `scripts/bundle.sh` (no .xcodeproj) |
| Tests | Swift Testing (`import Testing`, `@Test`, `#expect`) in `Tests/FeatherviewCoreTests` |
| Min macOS | 14.0 (Sonoma) |
| Bundle ID | `net.mynetx.featherview` — never change it: macOS keys settings and permissions to it |
| Public URL | `featherview.mynetx.net` — the update feed (`appcast.xml`, Sparkle format) lives here, never on github.io |
| Repo | github.com/featherview/featherview |
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
swift build --build-tests --triple x86_64-apple-macosx14.0 --scratch-path .build/x86   # Intel tests, then run under Rosetta:
arch -x86_64 xcrun xctest .build/x86/out/Products/Debug/FeatherviewCoreTests.xctest   # (arch -x86_64 swift test runs arm64; firstEncodesInAFreshProcess… needs swift test's runner, fails here only)
scripts/strings.sh               # after changing UI text: extract strings into Resources/Localizable.xcstrings, then translate the new keys
scripts/merge-strings.py         # catalog merge conflict: resolves it, then git add Resources/Localizable.xcstrings
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
Sources/CJPEGXR/           jxrlib (vendored C; any change marked `featherview patch:` and offered upstream) and the small C shim JPEGXRDecoder calls
Sources/FeatherviewJXL/    JPEG XL writing (libjxl, vendored in Sources/CJPEGXL); only the app links it, so the
                           extensions stay without libjxl; the app hands it to ImageEncoder.jxlEncoder at launch
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
| Cold launch with a file to first image on screen | < 410 ms (12 MP JPEG, Apple Silicon, after a normal quit, no window restored; AppKit + SwiftUI alone take ~300 ms to show the window, Liquid Glass ~85 ms more). Measured with the own look: ~400 ms (12 MP JPEG), ~395 ms (10,000-file folder) |
| Next/previous image when prefetched | no visible delay (≈ 20 ms to swap is fine; `Navigate` p50 21 ms, p95 26 ms; Zoom to Width ~30 ms for landscapes, ~130 ms for enlarged portraits) |
| Next/previous image, not prefetched | < 150 ms (12 MP JPEG; `Navigate` ~121 ms landscape, ~66 ms portrait) |
| Opening a folder of 10,000 files | < 500 ms to first image, UI never blocks (measured in every Sort By order: name ~430 ms, size ~470 ms, date modified ~485 ms; Date Taken shows the first by name, ~410 ms, and re-sorts later) |
| Memory while browsing | bounded by the 8-image cache, decoded to fit the screen per axis (rounded up to JPEG's next halving step, at most 2× per side) |
| T to the thumbnail grid on screen | < 100 ms for any folder up to 10,000 files (cells laid out, names shown; `GridShow`). Measured: ~90 ms for 10,000 (84–99 ms; most of it is NSCollectionView making the visible cells) |
| First screen of thumbnails complete | < 400 ms for 12 MP JPEGs without a usable embedded thumbnail, < 150 ms for 12 MP HEICs with a 320 px embedded one (default size, 1220 × 700 window; `GridFill`). Measured in an 805 × 585 window: ~282 ms JPEG, ~127 ms HEIC |
| Scrolling a 10,000-file grid | no frame dropped by grid work (< 8 ms main-thread work per frame); when scrolling stops, the new screen completes within the row above |
| Grid memory | thumbnail cache ≤ 3 × the largest screen's pixel area × 4 bytes, on top of the 8-image cache; Return to the image within the not-prefetched budget |
| Compare With… to the second picture on screen | < 150 ms for a 12 MP JPEG (`CompareShow`, measured ~100 ms); stepping the first pane keeps the next/previous budgets |
| Difference on screen (D, or a step with it on) | < 100 ms after both decodes, 12 MP (`Difference`, measured ~30 ms; Compare warms Core Image up first, which otherwise adds ~50–80 ms to the first D) |
| Compare memory | on top of browsing: at most one fit image held by the second pane, one zoom decode and one difference image |
| Info panel histogram | ≤ 5 ms per count of a 2560 × 1600 decoded picture, off the main thread (`featherview-bench histogram`). Measured: decodes up to 2134 × 1600 ~2 ms warm, ≤ 3.3 ms the first count; 12 MP landscapes, which a 2560 × 1600 screen decodes at full size, ~4 ms warm (p95 5.2), ~8 ms the first count |
| Place data | load ≤ 50 ms, off the main thread, once, on the first geotagged picture; lookup p95 ≤ 1 ms (`featherview-bench places --time`). Measured: 4.6 MB file loads in ~16 ms (Japanese, the language with the most names); 10,000 random lookups median 0.002 ms, p95 0.02 ms, max ~4 ms |

How: decode off the main thread to fit the screen per axis, rounded up to full, ½, ¼ or ⅛ size (any size in between costs a slow resample; see `ImageDecoder.decodeSize`); HEIC/HEIF and own formats decode at the exact size instead (no slower, fewer bytes), prefetch 2 neighbours each
way, never touch file contents while scanning a folder. Next/previous budgets are measured as the `Navigate` signpost (from `show()`, right after the key press, until Core Animation has
committed the image, what the user sees), not the log line. Measure: the app logs how long each image
took to appear — `log stream --level debug --predicate 'subsystem == "net.mynetx.featherview"'`.
Without a window: `swift run -c release featherview-bench decode <dir>` (fit and full-size decode times; `--json` / `--baseline` to compare) and `browse <dir>/browse --interval-ms 300` (or 30, a held key).
Instruments' Points of Interest shows the `Decode`, `Scan`, `Navigate`, `GridShow`, `GridFill`, `CompareShow` and `Difference` signposts and the `FirstImage` event (`Signposts.swift`); `featherview-bench grid` times thumbnail decodes without a window, `histogram <dir>` the info panel's histogram and `places --time build/places/places.fvpl` the place data.
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

Plugins, interactive painting/editing (batch operations are in, see spec), scanning, OCR, printing, slideshows with effects, lossless JPEG crop, video, Windows/Linux.
