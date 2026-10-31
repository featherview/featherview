# Featherview v1 roadmap

`docs/spec.md` says what v1 is. This file splits it into five milestones, each shippable and
testable on its own. Each milestone gets its own detailed plan in `docs/superpowers/plans/`,
written (superpowers:writing-plans) when the previous milestone is merged, so it can use the real
interfaces instead of guessed ones. Run a milestone's plan wave by wave with the `plan-wave`
workflow.

Plans of done milestones are in git history only: `git show 5dcca24:<plan path>`.

Milestones marked **observe first** have reference-viewer behaviour not yet recorded in
`docs/parity.md`; run the `observe-reference` skill for those items before writing the plan.

| # | Milestone | Plan | Status |
|---|---|---|---|
| 1 | Core viewer and batch | `docs/superpowers/plans/2026-10-15-featherview-v1.md` | done |
| 2 | Viewer complete | `docs/superpowers/plans/2026-10-16-milestone-2-viewer-complete.md` | done |
| 3 | Formats and Save As | `docs/superpowers/plans/2026-10-16-milestone-3-formats-save-as.md` | done |
| 4 | Batch complete | `docs/superpowers/plans/2026-10-17-milestone-4-batch-complete.md` | done |
| 5 | WebP output | `docs/superpowers/plans/2026-10-16-milestone-5-webp.md` | done |
| 6 | Languages | `docs/superpowers/plans/2026-10-18-milestone-6-languages.md` | done |
| 7 | App formats | `docs/superpowers/plans/2026-10-17-milestone-7-app-formats.md` | done |
| 8 | Finder previews | `docs/superpowers/plans/2026-10-19-milestone-8-finder-previews.md` | done |
| 9 | Animation (v2) | `docs/superpowers/plans/2026-10-22-milestone-9-animation.md` | done |
| 10 | Document icon (v2) | `docs/superpowers/plans/2026-10-22-document-icon.md` | done |
| 11 | Viewer conveniences (v2) | `docs/superpowers/plans/2026-10-22-milestone-11-viewer-conveniences.md` | done |
| 12 | Zoom modes and flip (v2) | `docs/superpowers/plans/2026-10-22-milestone-12-zoom-modes-flip.md` | done |
| 13 | Thumbnail grid (v2) | `docs/superpowers/plans/2026-10-22-milestone-13-thumbnails.md` | done |
| 14 | Slideshow (v2) | `docs/superpowers/plans/2026-10-22-milestone-14-slideshow.md` | done |
| 15 | Compare images (v2) | `docs/superpowers/plans/2026-10-22-milestone-15-compare.md` | done |
| 16 | Batch extras (v2) | `docs/superpowers/plans/2026-10-22-milestone-16-batch-extras.md` | done |
| 17 | JPEG XL writing (v2) | `docs/superpowers/plans/2026-10-22-milestone-17-jpeg-xl-writing.md` | done |
| 18 | Quick wins (v2): Refresh, random image, desktop placement, grid tooltips | `docs/superpowers/plans/2026-10-22-milestone-18-quick-wins.md` | done |
| 19 | Simplify: decisions from the app into tested Core types, catalog format, duplicates | `docs/superpowers/plans/2026-10-22-milestone-19-simplify.md` | done |
| 20 | Hardening: fuzzing, sanitizers, real files through every write path, Intel, crash reports | `docs/superpowers/plans/2026-10-23-milestone-20-hardening.md` | done |
| 21 | Grid columns that fill the window, right-click menu, drag out | `docs/superpowers/plans/2026-10-25-milestone-21-grid-columns-menu-drag.md` | done |
| — | Automatic updates through Sparkle (spec "Updates") | no plan; commits 0949b8d, a5f9bd3 | done |
| — | First open on every account (spec "Distribution"): disk image background stored in its `.DS_Store`, "Read Me First" file with the Terminal line, Homebrew cask `postflight`, website card | no plan; branch `release-0.12.1` (3a5da45, a046241, 796c52b), merged into main | done, shipped in 0.12.1: tested on this Mac as a standard user with a quarantined image (Finder copy with admin prompt, line without admin, launch without prompt) and a quarantined Homebrew install into `~/Applications` |
| 22 | Photos library: browse albums, drops from Photos, batch from and into the library | `docs/superpowers/plans/2026-10-26-milestone-22-photos-library.md` | planned |
| 23 | Info panel: histogram, exposure card, foldable groups, place names, all metadata, keyboard focus and VoiceOver (runs before 22) | `docs/superpowers/plans/2026-10-28-milestone-23-info-panel.md` | done, shipped in 0.12.0: place names in the app's language; screen check: `Navigate` with the panel open over 200 12 MP JPEGs p50 19.9 ms, p95 21.9 ms; first place 75–79 ms after the panel opens, cold; keyboard, All Metadata keys, VoiceOver tree, German light, Arabic dark, Increase Contrast, Reduce Motion (groups fold as a cut) |
| 24 | Huge pictures: own readers for 8-bit RGB PSD/PSB and huge TIFF at the size needed, zoom by parts | `docs/superpowers/plans/2026-10-30-milestone-24-huge-pictures.md` | done: screen check on heic1502a.psb and both Hubble TIFFs: first image 525 ms after launch (PSB), parts at 100 % 36–60 ms (PSB) and 119–148 ms (TIFF) while panning, app footprint at most 327 MB; 12 MP JPEG `Navigate` p50 21 ms, p95 24 ms |
| 25 | Photoshop layers: files without a stored composite drawn from their layers, every blend mode, groups, masks, fills, adjustment layers (runs before 22) | `docs/superpowers/plans/2026-10-30-milestone-25-photoshop-layers.md` | done: tasks 1–9. Oracle: 104 of 108 unique comparable files within target (96.3 %, target ≥ 95 %); over, with `shortcut:` comments: Brightness/Contrast's curve, Hue/Saturation on near greys, gradients mixed in Photoshop's working space, noise gradients' generator (none described in Adobe's spec). Fit decode of the 12 MP, 30-layer file ~292 ms (budget < 500 ms). Screen check (release): all 55 corpus files without a composite show a picture, none blank or failing; grid shows all; files with layer effects show without them; first image 399–400 ms after launch; slowest fit decode in the folder 16 ms. Finder and Quick Look stay macOS's (it never asks an app's extension for PSD/PSB) |

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
  Alternate, never taking over as default by itself; the user is asked once instead (spec
  "Default viewer", own-look plan Task 9). Check with `lsregister -dump` and Finder's Open With.
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
  grouped by step, live preview of output names, progress and log in the window. Mockups accepted by the
  maintainer; the layout is in spec "Batch window" › "Window".
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

Done: checked on this Mac in light and dark; the launch budget in `AGENTS.md` comes from it.

Decided: the maintainer accepted the mockups' recommendations (artifact KsGLFNEAZZwWU9iEmwNddZ).
The accepted look is in `docs/spec.md` ("Viewer", "Toolbar", "Look", "Batch window › Window",
"Preferences", "Distribution"): canvas under the glass toolbar and a floating glass status strip,
Graphite as the default background, an optional "hide toolbar and status bar while viewing", the
grouped-card form for Preferences and the batch steps, system accent everywhere (feather colours only
in About, the empty-window hint and the disk image), instant browsing with short motion elsewhere, and
a designed disk image with translated first-open help. Also: asking once to open images instead of Preview (spec "Default viewer"). Minimum macOS stays 14; glass on macOS 26 and
later, the normal material before. Plan: `docs/superpowers/plans/2026-10-18-own-look.md`. Launch is
measured again at its end (after a real ⌘Q) and that number becomes the budget in `AGENTS.md`.

## v2 (not in v1)

The reference viewer's menu commands that make sense on a Mac, split into milestones 9–17, plus
JPEG XL writing. Left out on purpose: painting and editing in the viewer, printing, scanning, OCR,
plugins and video (`AGENTS.md` "Out of scope for v1"); file search (Spotlight and Finder do it), hex
view, e-mail (the Share menu covers it), screenshots (macOS has them), showing or hiding the menu bar
and title (not a Mac thing), new blank images, panoramas and tiled images (editing).

Each milestone takes the reference viewer's feature in the Mac's form: Mac menu names and
places, the system's own panels and services, no separate tool windows where Mac apps use a mode
of the same window.

### Viewer conveniences (v2)

Parity "Viewer conveniences". File › Open Recent (opened files only, also in the Dock menu);
Rename… (F2 as the single key) by editing the name in the window's title, as Preview does; View ›
Sort By (name, date, date taken, size, kind; ascending or descending) for the viewer's list, as in
Finder, keeping the current image; Share (toolbar button and File › Share, the system's share menu,
which also covers e-mail); Set as Desktop Picture; Window › Float on Top, as QuickTime Player has
it; File › New from Clipboard (⌘N), an unsaved image that Save As writes, as in Preview, asking
before it is discarded; View › Follow New Files, which shows each file arriving in the folder (all
the reference's watched folder does). Not taken: a random image command (shuffle belongs to the
slideshow).

### Zoom modes and flip (v2)

Parity "Zoom modes and flip". View › Zoom to Width / Zoom to Height next to Zoom to Fit (0) and
Actual Size (1), for tall or wide images, starting at the top or leading edge; View › Keep Zoom,
which keeps the zoom and scroll position from image to image (for checking the same detail across a
series). Flip Horizontal / Vertical (H / V) in the Image menu, as in Preview's Tools menu, saved
losslessly through the orientation like Featherview's rotate (the reference only flips the view).

### Thumbnail grid (v2)

Parity "Thumbnails", in the Mac form: a grid mode of the viewer window itself (as Photos and
Finder's icon view), not a second window. T or ⌘-shortcut toggles it, opening on the current image;
Return or double-click views the selected image; selection for move, copy, Trash and batch (B);
View › Sort By shared with the viewer; a size slider; Quick Look on Space. No folder tree (Finder
and the Go menu choose folders). Decoded off the main thread at cell size; a 10,000-file folder stays
responsive.

### Slideshow (v2)

Parity "Slideshow". View › Slideshow, as in Preview: full screen through the system's full-screen
mode, the viewer's list from the current image at an interval, with shuffle (each image once per
round) and repeat, Space to pause as in Photos, arrows to step, Esc back to the window on the image
shown. Playing in the window as well (automatic viewing in the reference). No setup dialog with its
own file list, no transition effects or exports.

### Compare images (v2)

Parity "Compare images". Two images in one window, side by side, zoom and pan in step (on by
default; two windows tiled by macOS can't keep them in step), next / previous stepping the first
pane, swap, and a difference view; started from two selected thumbnails or with a second image
chosen in an open panel.

### Batch extras (v2)

Parity "Batch extras". Extract all frames or pages to files; split an image into tiles; set or
shift the date taken (as Photos' Adjust Date and Time) for every format whose metadata ImageIO
writes, with the file date following. Outputs never overwrite existing files (`AGENTS.md`), unlike
the reference.

### JPEG XL writing (v2)

JPEG XL as an output format in Save As and batch with quality and lossless options: ImageIO first
(check whether this macOS writes it), else libjxl built from source if it meets the dependency
rules in `AGENTS.md`.

### Animation (v2, done)

Spec: "Animation". Animated GIF, PNG (APNG), WebP and HEIC sequences play in the viewer through
ImageIO's frames and delays; Windows animated cursors (ANI) play from their own frame order and
rates. Batch and Save As keep writing the first frame. Memory stays bounded (frames decoded at fit
size, a window of frames instead of all of them for long animations) and browsing budgets hold:
the first frame shows as fast as a still image.

### Document icon (v2, done)

Files in the formats only Featherview reads show the feather (without the app icon's tile) on the
system's document page, with the extension under it, through `UTTypeIcons` in our type
declarations; a default app's own document icon still wins. Plan:
`docs/superpowers/plans/2026-10-22-document-icon.md`.

## Next version (after v2)

Ideas from the maintainer's QA that no spec covers yet; each gets a plan and a spec section first.

- Photos library: browse and convert pictures from Apple's Photos library without exporting them first.
  - **Drops from Photos:** dragging pictures from the Photos app onto the window or Dock icon opens them
    (Photos hands over file promises; they land in a temporary folder and the viewer browses them like
    a dropped selection).
  - **File › Open from Photos… (⇧⌘O):** a sheet lists Library, Favorites, Recents, the user's albums
    and the media types (Screenshots, Panoramas, …). Choosing one browses it like a folder: arrow
    keys, Home/End, grid (T), slideshow, Compare, info panel (EXIF from the original). Order is the
    album's own order (Library and smart albums: date taken); Sort By is disabled there. Videos are
    skipped; Live Photos show their still; edited photos show the current version, as Photos does.
  - **Read-only, data safe:** Copy to Folder (F8) and Save As export the current version; Batch
    Convert… takes the selection. Rotate, rename and Move to Folder are disabled, since changing a
    library picture is an edit in Photos. Delete moves to Photos' Recently Deleted, after the system's
    own confirmation.
  - **Batch output to Photos:** a destination choice "Add to Photos library" next to the output
    folder; uses the add-only permission, which never lets the app read the library.
  - **Permission only when used:** the Photos access prompt appears the first time Open from Photos…
    is chosen, never at launch; once denied, the sheet says how to allow it in System Settings ›
    Privacy & Security › Photos. Nothing calls Photos before then (linking it costs launch nothing measurable), so launch and
    browsing budgets stay as they are.
  - **Budgets:** an album browses within the folder budgets (first image < 500 ms for 10,000 pictures,
    prefetched swap ≈ 20 ms), decoding fit-to-screen through Photos' image manager with the same
    2-each-way prefetch and 8-image cache. A picture stored only in iCloud shows Photos' local preview
    at once and sharpens when the original arrives; the status bar says "Downloading from iCloud…".
  - **Not planned:** organising the library (albums, keywords, favourites), syncing edits back, and
    Photos' "Edit With" round trip.

- Info panel: more of what photographers check, without a network call.
  - **Histogram** on top: luminance or RGB, clipping marks at both ends with the clipped share on
    click; computed from the already decoded screen-size image (no extra decode); HDR shows the
    standard range and a marker beyond it.
  - **Exposure card:** shutter, aperture, ISO and focal length (35 mm equivalent when it differs) as
    tiles with glyphs, plus exposure bias, flash, white balance and metering.
  - **Foldable groups** (Image, Location, Description, File), each with a one-line summary when
    closed; open and closed state is kept for every image until the app quits.
  - **More fields:** folder (Show in Finder), format, megapixels, colour profile, bit depth, HDR,
    software, title, caption, keywords, rating, creator, copyright, JPEG comment.
  - **Location:** coordinates and altitude with Open in Maps; no map inside the panel, so nothing
    loads over the network.
  - **Candidate: place name offline** ("near Andermatt, Switzerland"): GeoNames `cities1000` packed
    with LZFSE (~2 MB in the app), grid lookup loaded lazily on the first geotagged image, countries
    localized through `Locale`. Beyond 25–50 km from a town: the Natural Earth region or sea that
    contains the point, with the nearest country ("Sahara, near Tunisia", "South Atlantic, off
    Gambia" within ~200 km of a coast, else just "North Pacific Ocean"). GeoNames is CC BY 4.0
    (accepted): credit with links to GeoNames and the licence, noting the data is simplified, in
    the About window and README. The data file is generated fresh by every release (not committed),
    cached locally; without network the build takes the last cached file and the release report says
    so. Shown short in the panel header ("Andermatt, Switzerland") and in full as the first line of
    Location ("near Andermatt, Uri, Switzerland").
  - **Show all metadata…:** every EXIF, GPS, IPTC, XMP and TIFF tag with readable labels, search and
    copy; internal entries hidden.
  - Design: <https://claude.ai/artifact/Lf6bXo8PaC2Exi6A6Unvmx>, option B2-1b-2 chosen (coral line
    histogram, coral glyphs, place under the file line). Reference behaviour: `docs/parity.md`, "Metadata".
  - **Not planned:** editing metadata in the panel (Adjust Date Taken stays the only metadata edit).

- Accessibility pass for the whole app (idea, after M23): the info panel gets full keyboard focus and
  VoiceOver in M23; the same for toolbar, grid, batch window, sheets and Settings (focus rings,
  VoiceOver labels, Increase Contrast) is a separate milestone once M23 shows the pattern.
