# Featherview v1 roadmap

`docs/spec.md` says what v1 is. This file splits it into five milestones, each shippable and
testable on its own. Each milestone gets its own detailed plan in `docs/superpowers/plans/`,
written (superpowers:writing-plans) when the previous milestone is merged, so it can use the real
interfaces instead of guessed ones. Run a milestone's plan wave by wave with the `plan-wave`
workflow.

Milestones marked **observe first** have reference-viewer behaviour not yet recorded in
`docs/parity.md`; run the `observe-reference` skill for those items before writing the plan.

| # | Milestone | Plan | Status |
|---|---|---|---|
| 1 | Core viewer and batch | `docs/superpowers/plans/2026-10-15-featherview-v1.md` | done 2026-10-16 |
| 2 | Viewer complete | `docs/superpowers/plans/2026-10-16-milestone-2-viewer-complete.md` | done 2026-10-16 |
| 3 | Formats and Save As | to write after 2 | — |
| 4 | Batch complete | to write after 3 | — |
| 5 | WebP output | to write after 3 (independent of 4) | — |
| 6 | Languages | to write after 4 and 5 | — |
| 7 | App formats | to write after 3 | — |
| 8 | Finder previews | to write after 3 and 7 | — |

## 1. Core viewer and batch

Folder scanning, bounded navigation, decoding at screen size with an 8-image cache and
prefetch, metadata, lossless rotate, Move to Trash, info panel, fit / actual size / ×1.1 zoom,
full screen (F, Esc), drag and drop, ⌘O; batch with JPEG/PNG/HEIC/TIFF, quality, limit size,
`{name}`/`{n}` rename, never-overwrite planning, parallel run. Meets the performance budgets.

## 2. Viewer complete

Spec: "Viewer" (all of it), "Settings", "Windows".

- Folder chooser past either end (keyboard-driven, parent and subfolders, image counts).
  `ImageList.next()` returning false is the hook. Core: `FolderTree` (siblings, parent, children,
  image counts, Finder order).
- Arrow keys pan when the image is larger than the window; two-finger scroll pans; never
  navigates.
- Return and double-click toggle full screen; ⌘C copies the image (full size, upright).
- F7 / F8 move / copy with 14 destination slots (1–9, 0, B–E), " 2" suffixes, next image after a
  move. Core: `DestinationSlots` (persisted), `FileMover` (never overwrite, sidecars).
- Sidecar files (`.xmp`, `.aae`, `.thm`) move, copy and trash with their image.
- One viewer window per file opened from Finder (`WindowGroup(for: URL.self)`).
- Settings window (⌘,) with every setting in the spec, persisted in `UserDefaults`.
- Toolbar for mouse users (spec "Toolbar"), SwiftUI `.toolbar` calling the same model actions as
  the keys.
- Dragging pans a zoomed image; right-click context menu; multi-page files (⌥← / ⌥→, page in
  the title, page toolbar buttons); "No images in <folder>" for an imageless folder.
  Observed 2026-10-16 (`docs/parity.md` "Mouse, pages and toolbar").

## 3. Formats and Save As

Spec: "Formats", "Format options", ⇧⌘S Save As.

- Runtime format registry from `CGImageSourceCopyTypeIdentifiers` /
  `CGImageDestinationCopyTypeIdentifiers`.
- About window (spec "About window"): icon, version, links, supported formats from the
  registry, licence and acknowledgements, Copy for bug reports.
- Per-format option models and encoders for every ImageIO-writable format (JPEG target file
  size by binary search on quality).
- Own pure-Swift encoders: PGM, PPM, QOI, PCX (golden-file tests against hand-computed bytes).
- Save As from the viewer with the format's options; options remembered per format, profiles.
- Batch output uses the registry (replaces the fixed list from milestone 1).
- HDR display (spec "Formats"): HDR decode only for images that carry HDR data (macOS 15+),
  `allowedDynamicRange(.high)` in the viewer. Measure decode time and memory on an HDR iPhone
  photo against an SDR one.
- Own decoders (spec "Formats", decided 2026-10-16): SVG through AppKit; pure-Swift QOI, PCX/DCX,
  XBM, XPM, WBMP, Sun RAS, IFF/LBM. One `OwnDecoders` registry consulted by `ImageFormats` and
  `ImageDecoder`, each decoder unit-tested on hand-built files (fixtures generated in tests, the
  same golden-byte approach as the encoders), corrupt and truncated input included.
- Option dialogs of GIF, JPEG 2000, TGA, PDF observed 2026-10-16 (`docs/parity.md`); PDF options
  decided in spec "Format options".
- Viewer look (maintainer, 2026-10-16): closer to the reference viewer's density while following
  Apple's HIG and Liquid Glass. Candidates, each to accept into the spec first: a status bar
  (dimensions, zoom %, file size, index, date), a compact toolbar, zoom % in the title, Liquid
  Glass on the chooser, F7/F8 panel and messages (macOS 26+, material below). Clean-room: our
  own icons, order and labels. Status bar and Liquid Glass decided 2026-10-16 (spec "Viewer").
- Toolbar speed, part of the redesign: a prefetched next image takes ≈20 ms, over the 16 ms
  budget (milestone 1: ≈12 ms). The title changes on every image and AppKit re-lays out the nine
  SwiftUI toolbar items. Native `NSToolbarItem`s or a title outside the toolbar should fix it;
  measure before and after. Miss accepted until then (maintainer, 2026-10-16).

## 4. Batch complete

Spec: "Batch window (⌘B)" (all of it).

- Modes convert / rename / both; rename-only copies without re-encoding.
- Input list: Add Folder with subfolders, Sort, Move up/down, Save / Load List.
- Rename: `{date}`, `{folder}`, counter advances only on success (the planner from milestone 1
  assigns names up front; this milestone assigns the counter as files finish, still
  clash-checked), Preview Names.
- Operation pipeline in spec order: crop, resize (all modes), rotate / flip, colour operations,
  borders / canvas / text / watermark. Core Image where it fits; each operation unit-tested on
  `Fixtures` images.
- Presets; Replace existing (to Trash), Move originals to Trash, Keep file dates, Recreate
  subfolders.
- Stop, Pause / Resume, Copy Log.
- Nicer batch window (maintainer request 2026-10-16; milestone 1's is a plain form): designed
  for the Mac before it's built — input list with thumbnails and drag and drop, settings
  grouped by step, live preview of output names, progress and log in the window. Mockups first
  (artifact), reviewed by the maintainer, then the plan.
- **Observe first:** the sub-dialogs of canvas size, text overlay, watermark, border, and
  "more effects"; the batch preview image.

## 5. WebP output

Spec: "Write (open-source encoder)". libwebp built from source as a SwiftPM C target, loaded
only when writing WebP; WebP options (quality, lossless, effort, preset). Verify no change to
launch time and memory budgets. Record libwebp and its licence in README.md.

## 6. Languages

Spec: "Languages". Last, because by then every UI string exists. Move all user-facing strings
into `Localizable.xcstrings` (bundled by `scripts/bundle.sh`), translate into the 30 languages,
check right-to-left layout (Arabic, Hebrew) and long strings (German) in the viewer, batch and
settings windows. A test fails if a catalog key is missing a language.

## 7. App formats

Spec "Formats" (layered app formats). PSB (stored composite), XCF, PDN, PSP decoded in pure Swift
and shown flattened, through the `OwnDecoders` registry from milestone 3. Each format gets its
own task: these are large binary formats (XCF tiles and compression, PDN's serialized layers,
PSP blocks). Test files: generated where the format is simple enough to write in a test,
otherwise small files the maintainer exports from the real apps (licence-free, our own content),
stored under `Tests/` only if the maintainer agrees to committed binaries.

## 8. Finder previews

Spec "Formats" (Finder previews). A Quick Look preview extension and a thumbnail extension
(`.appex`, sandboxed) for the own-decoder formats, built and signed by `scripts/bundle.sh`
(SwiftPM can't produce app extensions), sharing FeatherviewCore. Check: Finder icon thumbnails,
Space preview, open panel preview; no effect on the app's launch time.

## Own look (any time before the v1 release)

Maintainer, 2026-10-16: the app looks like a stock macOS app; Featherview's own taste and feel is
missing. Give it a design pass of its own (identity, colour, typography, motion, the small
touches that make a viewer feel crafted), mockups first as an artifact, reviewed by the
maintainer, then planned. Coordinate with milestone 4's batch-window mockups so both share one
visual language. Clean-room rules still apply.

## v2 (not in v1)

JPEG XL writing (libjxl), thumbnail browser, anything in "Out of scope for v1" in `AGENTS.md`.
