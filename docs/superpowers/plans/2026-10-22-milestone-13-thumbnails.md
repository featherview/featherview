# Milestone 13: Thumbnail grid — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. In this repo, code tasks run with the `plan-wave` workflow; tasks marked "main session" need the screen and run in the main session after the maintainer's go.

**Goal:** T turns the viewer window into a grid of thumbnails of the viewer's own list (Photos' and
Finder's icon view, not a second window), with selection, Quick Look, move, copy, Trash and batch on
the selection, and a size slider. A 10,000-file folder stays responsive.

**Architecture:** Core gets a cell-size decode (`ImageDecoder.thumbnail`: the file's embedded
thumbnail when it is big enough and the right shape, else ImageIO's downsampled decode), a
`.thumbnail(side)` target for the existing `ImageCache` with a byte budget, and the grid's pure
rules (sizes, which cells to decode first, where the selection goes after a removal, keys, texts).
The app adds one `NSCollectionView` in an `NSViewRepresentable` (`ThumbnailGrid`) that replaces the
canvas while `ViewerModel.isGrid` is on. It lists `model.list.urls` as they are, so the viewer's order
(and M11's View › Sort By, whenever it lands) is the grid's order. Visible cells ask the cache;
every scroll refocuses a grid-only `DecodeQueue`, which drops waiting work for cells that left.

**Tech Stack:** Swift 6, ImageIO, SwiftUI + AppKit (`NSCollectionView`, `NSCollectionViewFlowLayout`,
`QLPreviewPanel` from Quartz), Swift Testing. No new dependency.

**Spec:** `docs/roadmap.md` "Thumbnail window (v2)" (the Mac form, which wins where it differs from
parity), `docs/parity.md` "Thumbnails" (the reference's behaviour), `docs/spec.md` "Viewer", "Keys",
"Look", `docs/DESIGN.md`. The spec has no thumbnail section yet; Task 7 writes one from the
Decisions below. Rules: `AGENTS.md`.

## Decisions (the roadmap leaves these to the plan; accepted by the maintainer)

1. **One mode of the viewer window.** T (single key) and View › "Show Thumbnails  (T)" with ⇧⌘T
   toggle it; the item reads "Show Image  (T)" in the grid. A toolbar button (`square.grid.2x2`,
   tooltip "Thumbnails (T)", toggled pill while on) does the same. Disabled while the window has no
   list (empty window, folder without images, opening).
2. **Opens on the current image:** selected and scrolled to the middle of the grid. **T, Return or
   double-click** go back to the viewer on the focused cell (the last cell clicked or moved to).
   **Esc** goes back to the image the viewer showed before T (in full screen, a second Esc leaves
   full screen as today). Opening a file or folder (⌘O, drop, Finder) leaves the grid.
3. **Order and contents:** exactly `model.list.urls`, in their order: the scan's names-only list, so
   unreadable and non-image files the list holds get cells too. The grid reloads whenever the list
   changes (the scan finishing after T, a removal, M11's sort) and keeps the selection by URL.
4. **Cell:** a square of the slider's size (64–256 pt, default 128, remembered in
   `AppSettings.thumbnailSize`), the thumbnail fitted inside, aspect kept, never enlarged, EXIF
   orientation applied, picture hairline, no shadow (DESIGN principle 1: only the picture viewed is
   solid); the file name below in one line, middle-truncated, the full name as tooltip. Selected:
   `toggledPill` backdrop behind the square, name in an accent capsule with on-accent text (DESIGN
   "Selection"). Loading: a `cardFill` square. Can't open: `photo.badge.exclamationmark` in tertiary
   in the square, tooltip "Can't open <name>" (the existing string). No folder tree, no subfolders
   (Finder and the folder chooser choose folders).
5. **Size:** a slider at the trailing end of the status strip while the grid shows (Finder puts its
   icon-size slider in its bottom bar); + / − (and the View menu's zoom items, retitled "Larger
   Thumbnails  (+)" / "Smaller Thumbnails  (−)") change it by ×1.25 within the range. Hidden strip:
   the keys still work.
6. **Decoded side:** the cell's pixels (points × backing scale) rounded up to 128, 256, 384 or 512 px,
   so a slider drag re-decodes only when it crosses a step; a cached larger thumbnail serves a
   smaller cell. 8 bits in the screen's colour space, never HDR (a grid of HDR cells would flash the
   screen's headroom).
7. **Embedded thumbnails:** used when their longest side covers the decode side *and* their aspect
   matches the image's within 2 % (camera JPEGs carry 160 × 120 thumbnails with black bars for 3:2
   photos; those are never shown). No blurry first pass: a too-small embedded thumbnail is skipped in
   the same job.
8. **What decodes:** only visible cells, then one screen ahead in the scroll direction, nearest
   first in reading order. Each scroll refocuses the grid's `DecodeQueue`: waiting jobs for cells
   that left are dropped; at most `width` running decodes finish. The grid queue is its own
   (`width` = `max(2, min(6, cores − 2))`), separate from the viewer's 3-wide queue. Animated files
   show their first frame (index 0, as M9 keeps for batch and Save As); multi-page files page 1. No
   playback in the grid.
9. **Memory:** the thumbnail cache holds at most 3 screens of pixels: `3 × (largest screen's
   pixel area) × 4 bytes` (≈ 71 MB on a 3024 × 1964 screen; the number of cells never matters, since
   cells together cover at most the screen). Kept while the window stays on its folder (T back and
   forth is instant), emptied when it opens another or closes.
10. **Selection:** click, ⇧-click range, ⌘-click toggle, ⇧-arrows extend, ⌘A (Edit › Select All),
    all `NSCollectionView`'s own behaviour. Arrows move by cell and row, mirrored in right-to-left
    languages by the flow layout itself; Home / End go to the first / last cell. No rubber-band
    selection (spec "Mouse": no selection rectangle).
11. **Actions on the selection:** Space opens Quick Look (`QLPreviewPanel`, arrows move through the
    selection while it is open; Featherview's own formats preview through M8's extension). ⌦ and
    ⌘⌫ move the selection to the Trash without asking (as in the viewer); F7 / F8 move or copy it
    through the destination panel ("Ask before moving or copying" asks once for all of them); B
    opens the Batch window with the selection added to its list. After a removal the cell after the
    last removed one is selected (the one before it at the end). One failure never stops the rest;
    the message names the file when one failed, else the count.
12. **Strip and title in the grid:** the strip shows the focused file's pixel size, file size,
    position and date (no zoom), or "12 of 120 selected" while several are selected; then the slider.
    Title: the folder's name, counter "— 120 images".
13. **Keys that do nothing in the grid:** R, L, I, 0, 1, S, ⌥→ / ⌥←, G (M9), ⌘C and ⇧⌘S; their menu items
    are disabled (they act on one viewed image). O, P, A, M, F keep their meaning.

## Spike facts (macOS 27, M1 Pro 10 cores, own test files; don't re-measure)

- `CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceThumbnailMaxPixelSize` and **neither**
  `…FromImageAlways` nor `…FromImageIfAbsent` returns the embedded thumbnail when there is one (never
  enlarged: a 160 × 120 one comes back at 160 × 120 for a max of 512), else decodes from the image at
  the max. `…WithTransform` applies the orientation to the embedded one too (orientation 6 → 120 × 160).
  Without a max size it decodes the full image (4032 × 3024), so always pass one.
- Times per file (median of 5): 12 MP JPEG, embedded 160 px: 0.3–1.2 ms; 12 MP JPEG decoded to 256 px:
  ≈ 25 ms (photo-like content), 65 ms (pure noise; ¼ and ⅛ are no faster than ½ there); 12 MP HEIC
  with a 320 × 240 embedded thumbnail (ImageIO's `kCGImageDestinationEmbedThumbnail`): 4–6 ms;
  12 MP HEIC decoded to 256 px: 160–300 ms.
- HEIC lists its thumbnails' sizes in `CGImageSourceCopyProperties`' `{FileContents}` → `Images` →
  `ThumbnailImages`; JPEG doesn't, so the decode result's size is the test.
- A JPEG cut after its start-of-scan gives no embedded thumbnail and a black decode, not an error.
  A test can still tell the embedded thumbnail from the image: splice the EXIF APP1 segment of a blue
  JPEG (with embedded thumbnail) into a red one; max 120 → blue 120 × 90, max 400 → the embedded
  160 × 120 (so the decoder must then decode the red image).
- Throughput, 48 × 12 MP JPEG to 256 px: 2 threads 649 ms, 3: 447, 4: 326, 6: 222, 8: 215.
- `NSCollectionViewFlowLayout` mirrors itself for `userInterfaceLayoutDirection = .rightToLeft`
  (item 0 at the trailing edge, x 872 of 1000). `reloadData` + layout of 10,000 items: 2 ms; layout
  attributes for a rect 1,000,000 pt down: 0.01 ms.

## Performance budgets for the grid (Task 7 measures them; a regression is a bug)

| Budget | Target | Why this number |
|---|---|---|
| T to the grid on screen (cells laid out, names shown, pictures may still load) | < 100 ms, any folder up to 10,000 files | Layout of 10,000 items is 2 ms; the rest is one SwiftUI swap and a commit. Signpost `GridShow`. |
| First screen of thumbnails complete (default size, 1220 × 700 window, ≈ 40 cells) | < 400 ms for 12 MP JPEGs without a usable embedded thumbnail; < 150 ms for 12 MP HEICs with a 320 px embedded one | 40 × 25 ms over 6 threads ≈ 170–220 ms measured; 400 leaves room for Macs with fewer cores and real photos' entropy. Embedded HEIC thumbnails cost ≈ 5 ms each. Signpost `GridFill`. |
| Scrolling a 10,000-file grid (fling, held ↓ / Page Down) | no frame dropped by grid work: < 8 ms main-thread work per frame; when scrolling stops, the new screen completes within the row above | Cell setup is a layer assignment; decoding never runs on the main thread; stale work is dropped on each refocus, so at most `width` decodes finish late. |
| Return / double-click to the image | the viewer's not-prefetched budget, < 150 ms | It is the viewer's own `show()`. |
| Memory | thumbnail cache ≤ Decision 9's budget, on top of the viewer's 8-image cache | Cells cover at most one screen; 3 screens let ↑ back show at once. |
| Cold launch | unchanged (< 410 ms) | No grid object exists until T. |

HEICs without an embedded thumbnail (most non-iPhone HEICs) take ≈ 200 ms each: no budget; they fill
in reading order and the UI never blocks.

## Where this meets parallel milestones

- **M11 View › Sort By:** the grid shows `model.list.urls` in its order and reloads on every change,
  keeping the selection by URL. Nothing here knows sort keys; M11's menu works in the grid as it is.
  Neither plan waits for the other.
- **M9 Animation:** the grid decodes index 0 (`ImageDecoder.thumbnail` passes index 0, as the M9
  plan keeps for batch and Save As), so animated GIF, APNG, WebP, HEICS show their first frame and ANI
  its first step through `OwnFormat.decode(data, 0, …)`. Viewing an animation from the grid goes
  through `show()`, which starts M9's player. Task 1 tests the GIF case with the fixture M9 already
  added (`Fixtures.writeAnimatedGIF`). G (M9's key) does nothing in the grid.

## Global Constraints

- macOS 14.0 minimum; Swift 6 strict concurrency; no new dependency.
- Performance budgets in `AGENTS.md` hold, plus the grid's above. "Never touch file contents while
  scanning a folder" holds: the grid reads files only for visible cells (and one screen ahead), and
  `FileInfo` only for the focused cell.
- Colours, radii, metrics, durations only from `Theme.swift`; leading/trailing, never left/right.
- Every user-facing string translatable, whole sentences with placeholders, plurals through the
  catalog's plural variations; new strings get all 30 languages (`scripts/strings.sh`, then the
  shared steps in `docs/superpowers/plans/2026-10-18-milestone-6-languages.md` "Translation tasks
  (5–10): the shared steps").
- Never lose user data: Trash only (recoverable), moves never overwrite (`FileMover`).
- Test images come from `Fixtures`, never committed binaries.
- Conventional commits, no AI attribution, no dates in docs or comments; `shortcut:` comments as
  `shortcut: <limit>, <when to upgrade>`.

## Review Focus

- A fling or held ↓ through 10,000 cells: no decodes pile up behind the scroll, the screen where it
  stops fills first. Pinned in Task 2 (`wantedIsBoundedToTwoScreens`) and Task 4 (refocus on every
  visible-range change), measured in Task 7.
- Trashing a selection that holds the last file, or every file: the selection lands on the survivor
  before it, or the grid shows "No images in <folder>"; never an index out of range. Pinned in Task 2
  (`focusAfterRemovingTheEnd`, `focusAfterRemovingAll`).
- A camera JPEG whose embedded 160 × 120 thumbnail is letterboxed, at a small cell on a 1× screen:
  never shown with bars. Pinned in Task 1 (`letterboxedEmbeddedIsSkipped`).
- The list changing under the grid (scan finishing after T, a move, a sort): a reused cell never shows
  another file's picture; selection kept by URL. Pinned in Task 4 (cell checks its URL before
  assigning; `GridSelection.indices` test in Task 2), checked in Task 7.
- A zero-byte file, a corrupt file and a 50 MP JPEG on the first screen: two "can't open" cells, the
  others fill around the slow one. Pinned in Task 1 (`zeroByteAndCorruptThrow`), checked in Task 7.

---

## Wave plan

| Wave | Tasks | Why |
|---|---|---|
| A | 1, 2, 3 | independent Core pieces (decoder + cache; grid rules; grid texts) |
| B | 4, 6 | the grid in the window (uses 1–3); the bench command (uses 1, 2) |
| C | 5 | actions on the selection (uses 4's view and model) |
| D | 7 (main session) | screen check, budgets, docs |

---

### Task 1: Cell-size decode and the cache's thumbnail target

**Files:**
- Modify: `Sources/FeatherviewCore/Imaging/ImageDecoder.swift`, `Sources/FeatherviewCore/Imaging/ImageCache.swift`
- Test: `Tests/FeatherviewCoreTests/Imaging/ThumbnailDecodeTests.swift`, `ImageCacheTests.swift`,
  `Tests/FeatherviewCoreTests/Fixtures.swift`

**Interfaces:**
- Produces:
  - `public static func ImageDecoder.thumbnail(_ url: URL, side: Int, colorSpace: CGColorSpace?) throws -> CGImage`
    — page / frame 0, upright, longest side `min(side, image's longest)`, 8 bits, redrawn into
    `colorSpace` like display decodes. Own formats: `OwnFormat.decode(data, 0, side)` + `scaled`.
    Throws `DecodeError.unreadable(url)`.
  - `static func ImageDecoder.acceptsEmbedded(_ thumb: PixelSize, image: PixelSize, side: Int) -> Bool`
    — `max(thumb) ≥ min(side, max(image))` and `|thumb.w/thumb.h − image.w/image.h| ≤ 0.02 × image.w/image.h`.
  - `DecodeTarget.thumbnail(Int)` (new case; `ImageCache.image(for:target:)` decodes it with
    `ImageDecoder.thumbnail(url, side:, colorSpace:)` and signpost `Decode` label "thumb <side>").
  - `ImageCache.init(capacity:hdr:colorSpace:queue:byteBudget: Int? = nil)` — evicts least recently
    used while `count > capacity` or `decodedBytes > byteBudget`.
  - A cached `.thumbnail(a)` answers a request for `.thumbnail(b)` when `a ≥ b`; never the reverse,
    and never across other targets.
  - Fixture `writeJPEGWithForeignThumbnail(to:) -> URL`: red 4000 × 3000 JPEG whose EXIF APP1
    (embedded 160 × 120 thumbnail) comes from a blue JPEG of the same size (see Spike facts).

The decode, pinned because the flags are easy to get wrong:

```swift
// 1: embedded if present, else a real decode at `side` (no FromImage* flag, max size required)
let first = CGImageSourceCreateThumbnailAtIndex(source, 0, [maxPixelSize: side, withTransform: true, cacheImmediately: true])
// keep it if acceptsEmbedded(first's size, image: displaySize, side:), else
// 2: CGImageSourceCreateThumbnailAtIndex(source, 0, [...same, FromImageAlways: true])
```

(A real decode passes `acceptsEmbedded` by construction: same aspect, longest side `min(side, full)`.)

- [ ] **Step 1: Write the failing tests** in `ThumbnailDecodeTests`:
  `embeddedUsedWhenBigEnough` (foreign-thumbnail JPEG, side 120 → 120 × 90, centre pixel blue);
  `decodesWhenEmbeddedTooSmall` (same file, side 400 → 400 × 300, centre red);
  `letterboxedEmbeddedIsSkipped` (`acceptsEmbedded(160×120, image: 6000×4000, side: 100)` false;
  `(160×120, 4000×3000, 100)` true; `(160×120, 4000×3000, 200)` false; `(120×160, 3000×4000, 100)` true);
  `smallImageNotEnlarged` (50 × 40 PNG, side 256 → 50 × 40); `orientationApplied` (4000 × 3000 JPEG,
  orientation 6, side 200 → 150 × 200); `zeroByteAndCorruptThrow` (`writeCorrupt` and an empty `.jpg`
  → `DecodeError.unreadable`); `animatedGIFShowsFirstFrame` (`writeAnimatedGIF` 3 frames → frame 0's
  colour); `multiPageTIFFShowsPageOne` (`writeMultiPageTIFF(pages: 3)` → width 8);
  `ownFormatThumbnail` (QOI 400 × 300 via `QOICodec.encode` → side 100 gives 100 × 75);
  `deepImageComesBackEightBit` (16-bit PNG → `bitsPerComponent == 8`).
  In `ImageCacheTests`: `byteBudgetEvicts` (budget of two 100 × 100 decodes, three stored → `count == 2`,
  the first gone); `largerThumbnailServesSmaller` (`.thumbnail(256)` then `.thumbnail(128)` → the same
  `CGImage` instance, `===`); `smallerThumbnailDoesNotServeLarger` (128 then 256 → a new decode, 256 wide);
  `thumbnailNeverServesFit` (`.thumbnail(512)` cached, `.fit` request decodes).
- [ ] **Step 2: Run** `swift test --filter "ThumbnailDecodeTests|ImageCacheTests"` → FAIL (no `thumbnail`).
- [ ] **Step 3: Implement** in `ImageDecoder.swift` (reuse `displaySize`, `redrawn`, `scaled`, the
  own-format branch) and `ImageCache.swift`.
- [ ] **Step 4: Run** `swift test --filter "ThumbnailDecodeTests|ImageCacheTests|ImageDecoderTests|QuickLookSupportTests"` → PASS.
- [ ] **Step 5: Commit** `feat: decode thumbnails at cell size, embedded ones when they fit`

---

### Task 2: Grid rules — sizes, decode order, selection, keys

**Files:**
- Create: `Sources/FeatherviewCore/Viewer/GridRules.swift`
- Modify: `Sources/FeatherviewCore/Viewer/ImageList.swift` (`select`), `ViewerKey.swift` (`toggleThumbnails`),
  `Sources/FeatherviewCore/App/AppSettings.swift` (`thumbnailSize`, default 128.0)
- Test: `Tests/FeatherviewCoreTests/Viewer/GridRulesTests.swift`, `ImageListTests.swift`, `ViewerKeyTests.swift`

**Interfaces:**
- Produces:
  - `public enum ThumbnailSize` — `static let range: ClosedRange<Double> = 64...256`,
    `static let standard = 128.0`, `static func decodeSide(points: Double, scale: Double) -> Int`
    (`points × scale` rounded up to 128, 256, 384 or 512; at most 512),
    `static func stepped(_ points: Double, larger: Bool) -> Double` (×1.25 or ÷1.25, clamped to `range`),
    `static func cacheBudget(screens: [PixelSize]) -> Int` (3 × largest `width × height` × 4).
  - `public enum GridWindow` — `static func wanted(visible: Range<Int>, count: Int, forward: Bool) -> [Int]`:
    the visible indices in order, then as many again ahead (after the range when `forward`, before it
    nearest first otherwise), clipped to `0..<count`.
  - `public enum GridSelection` — `static func focusAfterRemoval(urls: [URL], removed: Set<URL>) -> URL?`
    (the first survivor after the last removed index, else the last survivor before it, nil when none
    survive); `static func indices(of selected: Set<URL>, in urls: [URL]) -> IndexSet`.
  - `public enum GridKey: Equatable` — `case view, leave, quickLook, trash, move, copy, batch, larger,
    smaller, first, last, toggle` and `case passOn(ViewerKey)`;
    `static func action(characters: String, modifiers: MenuKey.Modifiers) -> GridKey?` taking
    AppKit's `charactersIgnoringModifiers`: "\r" and U+0003 → `.view`; U+001B → `.leave`; " " →
    `.quickLook`; U+F728 (⌦), or U+007F with `.command` → `.trash`; U+F70A (F7) → `.move`; U+F70B (F8)
    → `.copy`; U+F729 Home → `.first`; U+F72B End → `.last`; without modifiers, `ViewerKey.action`'s
    `.batch` → `.batch`, `.zoomIn` / `.zoomOut` → `.larger` / `.smaller`, `.toggleThumbnails` → `.toggle`,
    `.open`, `.settings`, `.about`, `.minimize`, `.toggleFullScreen` → `.passOn(key)`;
    everything else (R, L, I, 0, 1, S, arrows, any other ⌘ key) → nil (arrows belong to the collection view,
    ⌘ keys to the menus).
  - `ImageList.select(_ url: URL) -> Bool` — makes `url` current (drops a held image); false and
    unchanged when not listed.
  - `ViewerKey.toggleThumbnails` on "t" (Shift+T nothing, as other letters).

- [ ] **Step 1: Write the failing tests:** `decodeSideSteps` ((128, 2) → 256; (100, 1) → 128; (129, 2)
  → 384; (256, 2) → 512; (256, 3) → 512); `steppedClamps` (128 larger → 160; 250 larger → 256; 64
  smaller → 64); `cacheBudgetThreeScreens` ([3024×1964, 1920×1080] → 3 × 3024 × 1964 × 4);
  `wantedVisibleFirstThenAhead` (visible 40..<80 of 10,000 forward → 40…79 then 80…119; backward →
  40…79 then 39 down to 0); `wantedIsBoundedToTwoScreens` (any input → `count ≤ 2 × visible.count`);
  `wantedClipsAtEnds` (visible 9_990..<10_000 forward → 10 items); `focusAfterRemovalMidList` (a…e,
  remove b, c → d); `focusAfterRemovingTheEnd` (remove d, e → c); `focusAfterRemovingAll` → nil;
  `indicesKeepSelectionByURL` (selection {c, x} in [a, c, d] → [1]); `gridKeys` (each mapping above,
  ⌘⌫ trash, plain ⌫ nil, "r" nil, "B" with shift nil, ⌘B nil); `selectMakesCurrent` and
  `selectUnknownIsFalse` in `ImageListTests`; `tTogglesThumbnails` in `ViewerKeyTests`.
- [ ] **Step 2: Run** `swift test --filter "GridRulesTests|ImageListTests|ViewerKeyTests"` → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the same filter plus `AppSettingsTests` → PASS.
- [ ] **Step 5: Commit** `feat: grid rules for thumbnail sizes, decode order, selection and keys`

---

### Task 3: Grid texts

**Files:**
- Create: `Sources/FeatherviewCore/Viewer/GridText.swift`
- Modify: `Sources/FeatherviewCore/Viewer/StatusLine.swift`, `Resources/Localizable.xcstrings`
- Test: `Tests/FeatherviewCoreTests/Viewer/GridTextTests.swift`, `StatusLineTests.swift`

**Interfaces:**
- Produces (all `String(localized:)` with plural variations in the catalog):
  - `StatusLine.selection(count: Int, total: Int) -> StatusLine` — one field "12 of 120 selected".
  - `GridText.counter(_ count: Int) -> String` — "120 images" / "1 image" (the title counter after " — ").
  - `GridText.trashFailed(_ failed: [URL]) -> String` — one: the existing "Couldn't move \(name) to the
    Trash"; several: "Couldn't move \(n) images to the Trash".
  - `GridText.transferFailed(_ failed: [URL], operation: FileOperation, folder: URL) -> String` — one:
    the existing single-file sentences; several: "Couldn't move \(n) images to \(folder)" / "Couldn't
    copy \(n) images to \(folder)".
  - `GridText.confirm(_ urls: [URL], operation: FileOperation, folder: URL) -> String` — one: the
    existing "Move \(name) to \(folder)?" / "Copy …?"; several: "Move \(n) images to \(folder)?" /
    "Copy \(n) images to \(folder)?".
  The view's single-file messages in `ViewerModel` switch to these in Task 5 (same keys, so no
  translation changes for them).

- [ ] **Step 1: Write the failing tests:** `selectionField` ("12 of 120 selected", numbers formatted with
  the locale); `counterSingularAndPlural`; `oneFailureNamesTheFile`; `severalFailuresCount`;
  `confirmOneAndSeveral` (move and copy); run under `Locale(identifier: "en")`.
- [ ] **Step 2: Run** `swift test --filter "GridTextTests|StatusLineTests"` → FAIL.
- [ ] **Step 3: Implement;** `scripts/strings.sh`; the new keys in all 30 languages with plural
  variations (shared translation steps).
- [ ] **Step 4: Run** `swift test --filter "GridTextTests|StatusLineTests|StringCatalogTests|LocalizableCatalogTests"` → PASS.
- [ ] **Step 5: Commit** `feat: texts for the thumbnail grid in all languages`

---

### Task 4: The grid in the viewer window

**Files:**
- Create: `Sources/Featherview/Viewer/ThumbnailGrid.swift` (`ThumbnailGrid: NSViewRepresentable`,
  `GridCollectionView: NSCollectionView`, `ThumbnailCell: NSCollectionViewItem`, the coordinator as data
  source and delegate)
- Modify: `Sources/Featherview/Viewer/ViewerModel.swift` (grid state and decodes, availability),
  `ViewerView.swift` (grid instead of canvas, T key, View menu items, retitled zoom items),
  `ViewerToolbar.swift` (Thumbnails toggle item), `StatusBar.swift` (grid fields and slider),
  `Sources/Featherview/Design/Theme.swift` (grid tokens), `Sources/FeatherviewCore/Imaging/Signposts.swift`
  only if a name constant helps (signposts `GridShow`, `GridFill`)
- Test: none new in Core (Tasks 1–3 hold the logic); `swift build`, bundle, Task 7 checks on screen.

**Interfaces:**
- Consumes: `ImageDecoder.thumbnail`, `DecodeTarget.thumbnail`, `ImageCache(byteBudget:)` (1);
  `ThumbnailSize`, `GridWindow.wanted`, `GridSelection`, `GridKey`, `ImageList.select`,
  `ViewerKey.toggleThumbnails`, `AppSettings.thumbnailSize` (2); `StatusLine.selection`, `GridText.counter` (3).
- Produces (Task 5 builds on these):
  - `ViewerModel`: `private(set) var isGrid: Bool`; `var gridFocus: URL?`; `var gridSelection: [URL]`
    (list order, set by the grid); `func toggleGrid()` (on: remembers `list.current` as the Esc target,
    focuses it; off: `viewFromGrid(gridFocus)`); `func viewFromGrid(_ url: URL?)` (`list.select`, leave
    the grid, `show()`); `func leaveGridCancelling()` (Esc: back to the remembered image);
    `func thumbnail(_ url: URL, side: Int) async throws -> CGImage`; `func focusThumbnails(_ urls: [URL])`;
    `availability.canShowGrid`. The thumbnail `ImageCache` and its `DecodeQueue` are created at the first
    `toggleGrid()`, never at launch; `open(_:)` leaves the grid and drops them.
  - `GridCollectionView.onKey: (GridKey) -> Bool` (unhandled keys go up the responder chain),
    `onOpen: (URL) -> Void` (Return, double-click).

Rules:
- `ViewerView` shows `ThumbnailGrid` in place of `ImageCanvas` while `model.isGrid`; the info panel
  closes on entering. The scroll view runs under the toolbar and strip like the canvas:
  `automaticallyAdjustsContentInsets = false`, content insets from `Theme.fitInsets` (bottom from the
  strip's inset, 0 extra when it's hidden).
- Flow layout: item size = slider points × (points + name line), spacing and section insets from new
  Theme tokens (`gridGap`, `gridNameGap`, `Radius.gridCell = 8`), `allowsMultipleSelection = true`,
  `isSelectable = true`; no rubber band (override `mouseDown` drag selection off).
- Data: `model.list.urls`. On list change: `reloadData()`, then reselect `GridSelection.indices` of the
  previous selection; on entering, select and `scrollToItems(…, .centeredVertically)` the current image.
- Cells: on display, if the cache has it, set the layer's `contents` at once; else a `Task` asks
  `model.thumbnail(url, side:)` and assigns only if the cell still represents that URL (reuse); the
  task is cancelled in `prepareForReuse`. A throw shows the can't-open look (Decision 4). The picture
  fits the square with `contentsGravity = .resizeAspect` of the decoded size, never above 1 image
  pixel per screen pixel.
- Decode order: on every change of the visible index range (bounds-change notification of the clip
  view), `model.focusThumbnails(GridWindow.wanted(…).map { urls[$0] })`, `forward` from the scroll
  direction; prefetch those not cached through the cache (`prefetch` with `.thumbnail(side)`).
- Size: the slider (in `StatusBar`, grid only, `Theme` width token) and `.larger` / `.smaller` set
  `AppSettings.thumbnailSize`; the layout updates live; `decodeSide` changes re-request visible cells.
- Signposts: `GridShow` from `toggleGrid()` to the first commit of the grid; `GridFill` from the last
  visible-range change until every visible cell has a picture or the can't-open look; log line
  "grid fill <n> cells: <ms> ms".
- Menus: View › "Show Thumbnails  (T)" / "Show Image  (T)" (⇧⌘T); zoom items retitled in the grid
  (Decision 5); items Decision 13 names disabled through `Availability`. Toolbar: Decision 1's item;
  rotate, zoom, info, page buttons disabled in the grid.
- Strip: Decision 12; focused file's `FileInfo.read` off the main thread, as the viewer reads it.

- [ ] **Step 1: Implement** the model state, the grid view, the strip, menus and toolbar; `swift build`.
- [ ] **Step 2:** `scripts/bundle.sh debug`; `scripts/strings.sh`; new menu titles, tooltips and the
  slider's accessibility label ("Thumbnail size") in all 30 languages; `swift test` → all PASS.
- [ ] **Step 3: Commit** `feat: thumbnail grid as a mode of the viewer window (T)`

---

### Task 5: Actions on the selection

**Files:**
- Modify: `Sources/Featherview/Viewer/ThumbnailGrid.swift` (Quick Look, key dispatch),
  `ViewerModel.swift` (`trash(_:)`, `transfer` for several files, batch), `ViewerView.swift` (Image menu
  items act on the selection in the grid), `Sources/Featherview/Batch/BatchModel.swift`
  (`static let shared`), `Sources/Featherview/FeatherviewApp.swift` (`@State private var batch = BatchModel.shared`)
- Test: none new in Core (Task 2 and 3 hold the rules); Task 7 checks on screen.

**Interfaces:**
- Consumes: Task 4's `ViewerModel` grid API and `GridCollectionView.onKey`; `GridSelection.focusAfterRemoval`,
  `GridKey` (2); `GridText` (3); `FileMover.transfer`, `Sidecars.files`, `DestinationSlots` (existing).
- Produces:
  - `ViewerModel.trash(_ urls: [URL])` — queued behind `rotateTask` and `openTask` like
    `moveCurrentToTrash`, off the main thread, sidecars per setting, each file on its own (one failure
    doesn't stop the rest), then the trashed leave the list and both caches, the grid selects
    `focusAfterRemoval`, `errorMessage = GridText.trashFailed(failed)` if any failed.
  - `ViewerModel.transfer(to slot: Int)` acts on `operationTargets`: `gridSelection` in the grid, else
    `[list.current]`; confirm with `GridText.confirm` once; failures through `GridText.transferFailed`.
    The single-file behaviour in the viewer is unchanged.
  - `ViewerModel.batchSelection()` — `BatchModel.shared.add(files: gridSelection)`, then opens the
    Batch window (the view's `openWindow(id: "batch")`).
  - Quick Look: `GridCollectionView` implements `acceptsPreviewPanelControl`,
    `beginPreviewPanelControl` / `endPreviewPanelControl`, the panel's data source (the selection, at
    the focused item) and delegate (`previewPanel(_:handle:)` passes arrow keys to the collection view,
    `sourceFrameOnScreen` for the zoom from the cell). Space toggles the panel.

- [ ] **Step 1: Implement**; Image menu's Move to Folder…, Copy to Folder…, Move to Trash and Batch
  Convert… act on the selection in the grid (disabled with none); `swift build`; `scripts/bundle.sh debug`.
- [ ] **Step 2:** `scripts/strings.sh` (no new keys expected beyond Task 3's; add any in all 30
  languages); `swift test` → all PASS.
- [ ] **Step 3: Commit** `feat: Quick Look, move, copy, Trash and batch on the grid's selection`

---

### Task 6: `featherview-bench grid`

**Files:**
- Modify: `Sources/FeatherviewBench/main.swift` (command and usage), `Sources/FeatherviewBench/Corpus.swift`
  (folder `grid-heic` of 40 HEICs written with `kCGImageDestinationEmbedThumbnail`)
- Test: run it (below).

**Interfaces:**
- Consumes: `ImageCache(byteBudget:)`, `.thumbnail` (1); `ThumbnailSize.decodeSide`, `cacheBudget` (2).
- Produces: `featherview-bench grid <dir> [--points 128] [--scale 2] [--cells 40] [--width N]` — the
  first `cells` files in Finder order through one `ImageCache` and a `DecodeQueue(width:)` (default
  the app's Decision 8 width), all requested at once like a first screen; prints the time until the
  last one is done, p50 / p95 per file and the cache's `decodedBytes`. Also `--json` / `--baseline`
  as `decode` has them.

- [ ] **Step 1: Implement.**
- [ ] **Step 2: Run** `swift run -c release featherview-bench corpus /tmp/fv` then
  `swift run -c release featherview-bench grid /tmp/fv/browse` → total < 400 ms on this Mac, and
  `… grid /tmp/fv/grid-heic` → total < 150 ms. Note both in the commit message body.
- [ ] **Step 3: Commit** `feat: bench the grid's first screen of thumbnails`

---

### Task 7: Screen check, budgets, docs (main session, screen)

Needs the maintainer's go (screen bursts). Sample folders: the corpus (`/tmp/fv/browse`,
`/tmp/fv/grid-heic`), a 10,000-file folder (copies of one corpus JPEG, as in milestone 1's Step 8),
and a mixed folder: corrupt file, zero-byte `.jpg`, text file opened directly, EXIF-rotated JPEG,
animated GIF, multi-page TIFF, an own-format file (QOI), a 50 MP JPEG, a subfolder.

- [ ] **Step 1: Check by hand** (release build), light and dark, then in Arabic (right-to-left): T
  opens on the current image, centred; T / Return / double-click view the focused one, Esc goes back to
  the one before; arrows, ⇧-arrows, Home / End, click, ⇧-click, ⌘-click, ⌘A; Space Quick Look and arrows
  inside it (own format previews); ⌦ and ⌘⌫ on three cells (selection lands after them; Trash has
  them), the same on the last cells; F7 / F8 on a selection, with "Ask before…" on; B fills the Batch
  window; slider and + / −; the mixed folder's cells (two can't-open, rotated upright, GIF first frame,
  TIFF page 1); the 10,000 folder: fling to the end and back, held ↓, hold Page Down; full screen; Hide
  Status Bar; a scan finishing after T (open the 10,000 folder and press T at once); a removal in
  Finder while the grid shows nothing stale after the next list change.
- [ ] **Step 2: Measure** with `sudo -n /usr/bin/log show` and Instruments' Points of Interest:
  `GridShow` (10,000 files), `GridFill` for `/tmp/fv/browse` and `/tmp/fv/grid-heic` (5 runs, medians),
  frames while flinging (Instruments' Animation Hitches), memory with the grid open on the 10,000
  folder after scrolling it end to end (thumbnail cache ≤ budget), cold launch unchanged, Return to
  image < 150 ms. Fix any miss before going on.
- [ ] **Step 3: Docs:** `docs/spec.md` gets a "Thumbnail grid" section under "Viewer" with Decisions
  1–13 in spec wording, T and Space-in-grid in "Keys", the grid's budgets in `AGENTS.md`'s table;
  `docs/parity.md` "Thumbnails" rows → Featherview column as built, status `v2`; roadmap: row
  `| 13 | Thumbnail window (v2) | docs/superpowers/plans/2026-10-22-milestone-13-thumbnails.md | done |`;
  README features line.
- [ ] **Step 4: Commit** `docs: thumbnail grid done after manual QA`
