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
| 1 | Core viewer and batch | `docs/superpowers/plans/2026-10-15-featherview-v1.md` | done |
| 2 | Viewer complete | `docs/superpowers/plans/2026-10-16-milestone-2-viewer-complete.md` | done |
| 3 | Formats and Save As | `docs/superpowers/plans/2026-10-16-milestone-3-formats-save-as.md` | planned |
| 4 | Batch complete | to write after 3 | — |
| 5 | WebP output | `docs/superpowers/plans/2026-10-16-milestone-5-webp.md` | done |
| 6 | Languages | to write after 4 and 5 | — |
| 7 | App formats | `docs/superpowers/plans/2026-10-17-milestone-7-app-formats.md` | done |
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
  (`docs/parity.md` "Mouse, pages and toolbar").

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
- Own decoders (spec "Formats"): SVG through AppKit; pure-Swift QOI, PCX/DCX,
  XBM, XPM, WBMP, Sun RAS, IFF/LBM. One `OwnDecoders` registry consulted by `ImageFormats` and
  `ImageDecoder`, each decoder unit-tested on hand-built files (fixtures generated in tests, the
  same golden-byte approach as the encoders), corrupt and truncated input included.
- Finder's Open With: Featherview listed for every format it reads, so it
  shows in Open With and its suggested apps. `Info.plist` declares document types for
  `public.image`, PDF and each own-decoder format, with imported type declarations (UTIs and
  extensions) for the ones macOS doesn't know (QOI, PCX/DCX, XBM, XPM, WBMP, RAS, IFF/LBM). Rank
  Alternate, never taking over as default. Check with `lsregister -dump` and Finder's Open With.
- Option dialogs of GIF, JPEG 2000, TGA, PDF (`docs/parity.md`); PDF options
  decided in spec "Format options".
- Viewer look: closer to the reference viewer's density while following
  Apple's HIG and Liquid Glass. Candidates, each to accept into the spec first: a status bar
  (dimensions, zoom %, file size, index, date), a compact toolbar, zoom % in the title, Liquid
  Glass on the chooser, F7/F8 panel and messages (macOS 26+, material below). Clean-room: our
  own icons, order and labels. Status bar and Liquid Glass (spec "Viewer").
- Swap speed (milestone 3 Task 15): a prefetched next image is back under the
  16 ms budget. The toolbar wasn't why. 80 12 MP JPEGs, auto-advance every 150 ms, release build,
  time from the key to the main thread going idle after the frame is committed: median 64 ms /
  p90 115 before, 11 / 12 after. Two causes, both fixed: Core Animation colour-converted each new
  image on the main thread (`CA::Render::prepare_image`; display decodes now come in the screen's
  colour space, converted off the main thread), and awaiting the cache actor drew a frame with the
  new position before the image (prefetched images now swap in synchronously). The `show … ms` log
  line reads 0 ms for a prefetched swap now; it never counted the commit. Setting `window.title`
  directly instead of `.navigationTitle` doesn't work: SwiftUI puts the scene title back on its
  next update.

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
- Stop, Pause / Resume, Copy Log. A multi-page file written to a single-page format says "page 1
  of N" in its log line (spec "Output").
- Nicer batch window (milestone 1's is a plain form): designed
  for the Mac before it's built — input list with thumbnails and drag and drop, settings
  grouped by step, live preview of output names, progress and log in the window. Mockups first
  (artifact), reviewed by the maintainer, then the plan.
- HDR kept when an HDR photo is converted to HEIC or AVIF (spec "Formats");
  milestone 3 writes 8-bit SDR there.
- Format options behind an "Options…" button in the batch window (spec "Output"); Save As has had its button since milestone 3, and batch shows them inline until then.
- Observed (docs/parity.md "Batch"): the sub-dialogs of canvas size, text overlay, watermark,
  border, and "more effects"; the batch preview image.

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

The app looks like a stock macOS app; Featherview's own taste and feel is
missing. Give it a design pass of its own (identity, colour, typography, motion, the small
touches that make a viewer feel crafted), mockups first as an artifact, reviewed by the
maintainer, then planned. Coordinate with milestone 4's batch-window mockups so both share one
visual language. Clean-room rules still apply.

Questions for this pass, with what Apple's guidelines say:
- Liquid Glass and the canvas: since 78f4e39 the app links against the real SDK, so macOS 26+
  shows glass toolbars. On our black band below them they look flat. The guidelines put glass
  over content ("use the content layer to inform the color and appearance of the toolbar",
  reduce toolbar backgrounds), so mock the canvas extending under the toolbar (fit still keeps
  the image clear of it; zoomed images slide under) and the status bar the same way at the
  bottom. Also reconsider the black default background under glass.
- Hiding the toolbar: the guidelines say to consider hiding toolbars temporarily "when content is
  the primary focus, such as when viewing full-screen photos", contextually, and to let people
  restore them reliably (moving the pointer to the top of the screen). They don't ask for
  hide-on-hover in a window, and every toolbar item must also be in the menu bar. Decide whether
  windowed viewing hides the toolbar after the pointer rests (a media-player style) or only full
  screen does, as now.
- Settings window: doesn't look like a macOS 26 (Tahoe) settings window yet. Mock it in the current system style along with the rest.
- Launch time: the toolbar and canvas decide it (~385 ms with glass, 350 ms without;
  the window's first glass draw is macOS's cost). Measure launch again after this pass and set the
  budget in `AGENTS.md` then. If the toolbar may start hidden, try showing it only after the first
  image (saved 16 ms in a test; today it would make the image jump when the toolbar arrives).

## v2 (not in v1)

JPEG XL writing (libjxl), thumbnail browser, anything in "Out of scope for v1" in `AGENTS.md`.
