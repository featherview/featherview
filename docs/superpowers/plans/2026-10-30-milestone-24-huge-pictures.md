# Milestone 24: Huge pictures Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: run with the `plan-wave` workflow, wave by wave:
> Wave 1 = Tasks 1 and 2 (independent), Wave 2 = Task 3, Wave 3 = Task 4. Task 5 needs the screen and
> waits for the maintainer's go. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A 1.5-gigapixel Photoshop file (the Hubble Andromeda mosaic, `heic1502a.psb`, 69,536 × 22,230,
4.6 GB) opens in under a second and zooms to 100 % without holding a 6 GB decode.

**Architecture:** Part 1: an own reader for the stored composite of 8-bit RGB PSD/PSB files (raw or
RLE) reads only the rows it needs with `pread`, in parallel bands, and area-averages straight to the
size asked for; `ImageDecoder` routes qualifying files to it and everything else to ImageIO as today.
Part 2: when a zoom's halving-step decode would be far larger than the screen and the file allows
reading a part, the viewer shows the fit decode enlarged and lays a sharp decode of only the visible
part (plus a margin) over it, decoding the next part when panning nears the margin's edge.

**Tech Stack:** Swift 6, `pread` + `DispatchQueue.concurrentPerform`, CoreGraphics, Core Animation
(a sublayer of the canvas's image layer), Swift Testing.

**Spec:** `docs/spec.md` › Viewer (the "Very large pictures" bullet after "A fill mode's zoom…") and
› Formats (the PSD/PSB reader paragraph under "Layered app formats"). Budgets: AGENTS.md "Huge pictures" row.

## Spike facts (2026-10-30, MacBookPro18,3, 32 GB, `heic1502a.psb`)

- File: version 2 (PSB), 3 channels, 8 bit, RGB, no layers (layer and mask section 40 bytes),
  composite **raw** (compression 0) at byte 23,468, ICC profile resource 1039 (sRGB IEC61966-2.1),
  thumbnail resource 1036 (160 px JPEG).
- ImageIO today (`featherview-bench decode --screen 3024x1964 --runs 1`): fit decode 8692 × 2778 in
  14.9 s first (no purge), 5.1 s warm; full size 69536 × 22230 = 6.2 GB in 4.9–8.2 s; bench peak
  footprint 8.1 GB. ImageIO's thumbnail at 3024: 3.9 s warm.
- Own reader spike (scratch program, area averaging, one `pread` per channel per output row band,
  `concurrentPerform` over output rows): 3024 × 967 in **752 ms after `sudo purge`**, 171–201 ms warm,
  footprint 59 MB; 8692 × 2778 in 217 ms warm. Output matched ImageIO's visually (same stars and
  colours, less noise, since every source pixel is averaged). Reading only every n-th row was rejected:
  it drops stars between rows.
- ImageIO reads PSB wider than 65,535 px (this file) — our own decoders' `checkedSize` limit does not
  apply to this reader.

## Global Constraints

- Swift 6 strict concurrency. FeatherviewCore stays free of AppKit/SwiftUI.
- Never upscale: the reader's output size is at most the region's size per side.
- ImageIO stays the decoder for every PSD/PSB the reader declines: 16/32 bit, grey, CMYK, Lab,
  multichannel, indexed, bitmap, more than 3 channels (alpha), zip compression (2, 3), an EXIF/XMP
  orientation other than 1, or any header it can't follow. Declining is never an error.
- Display decodes still go through `ImageDecoder.inColorSpace` (the screen's space), as today.
- Budgets (AGENTS.md row added in Task 3): `heic1502a.psb` fit decode < 1 s cold, < 300 ms warm; a
  zoomed part on screen < 150 ms after panning stops (`RegionDecode` signpost); zoomed memory = fit
  decode + one part of at most (2 × visible width) × (2 × visible height) at the step's resolution.
  Browsing budgets for all other files unchanged.
- TDD for FeatherviewCore; test images come from `PSDFixture` (built in code), never committed binaries.
- Comments describe the code as it is. `shortcut: <limit>, <when to upgrade>` for known limits.
- No user-facing text is added (nothing to translate).

## Review Focus

1. A PSD the reader accepts but renders differently from ImageIO (wrong channel order, rows off by
   one in RLE, PSD's 2-byte vs PSB's 4-byte row counts, odd widths): the picture must look as it did
   before — Task 1 `readsRawAndRLEInBothVersions` with an odd width; Task 3 `fastPathMatchesImageIO`.
2. A damaged or truncated file (RLE counts past the end, a PackBits run longer than the row, a file
   shortened after the header was read): one bad file, "Can't open …", never a crash or a hang — Task 1
   `corruptRLEThrows`, `truncatedRawThrows`.
3. A PSD with an alpha channel, 16 bits, CMYK or grey: still opens exactly as before through ImageIO —
   Task 1 `declinesWhatImageIOReads`; Task 3 `declinedPSDStillOpens`.
4. Panning fast across a zoomed huge picture: never more than one part decode running, the newest wins,
   a stale part never lands over the wrong place, and nothing sharp is drawn for another image or zoom
   step — Task 4 (submits through `LatestWins`, drops a result whose url/step/rect no longer match).
5. A part request at the picture's edges (visible rect partly outside the picture when it is smaller
   than the window along one axis, or the last odd row/column at a halving step) — Task 2
   `regionGrowsAndClamps`, `regionAlignsToStep`; Task 1 `regionAtImageEdge`.

---

### Task 1: `PSDComposite`, the stored composite of 8-bit RGB PSD/PSB (Core)

**Files:**
- Create: `Sources/FeatherviewCore/Formats/PSDComposite.swift`
- Create: `Tests/FeatherviewCoreTests/Formats/PSDFixture.swift`
- Test: `Tests/FeatherviewCoreTests/Formats/PSDCompositeTests.swift`

**Interfaces:**
- Produces:
  - `public struct PSDComposite: Sendable` with `public let width: Int`, `public let height: Int`,
    `public let icc: Data?` (resource 1039's bytes, nil without one).
  - `public init?(url: URL)` — reads only the header, the section lengths, the resource list and (RLE)
    the row byte-count table; nil when the file isn't one the reader handles (Global Constraints) or the
    header can't be followed. Orientation is not checked here (Task 3 does).
  - `public func decode(region: CGRect? = nil, size: PixelSize) throws -> CGImage` — `region` in
    full-size pixels (integral, inside the picture; nil = whole picture), area-averaged to `size`
    (clamped to at most the region per side, at least 1 × 1). 8-bit RGB, `noneSkipLast`, in
    `CGColorSpace(iccData:)` of `icc` (falling back to sRGB when that fails or there is none).
    Throws `OwnDecodeError.corrupt` for any short read or bad RLE.
- `Tests/…/PSDFixture.swift`: `enum PSDFixture { static func make(width: Int, height: Int, pixels: [(UInt8, UInt8, UInt8)], version: Int = 1, compression: Int = 0, icc: Data? = nil, channels: Int = 3, depth: Int = 8, mode: Int = 3) -> Data }`
  (row-major RGB pixels; RLE via PackBits with literal and repeat runs; for `channels > 3` an extra
  channel of 255; for `depth 16` each sample doubled into two bytes).

- [ ] **Step 1: Write the failing tests** in `PSDCompositeTests.swift`

```swift
@Test(arguments: [(1, 0), (1, 1), (2, 0), (2, 1)])  // (version, compression)
func readsRawAndRLEInBothVersions(version: Int, compression: Int) throws
// 7 × 5 with pseudo-random pixels (odd width; RLE gets runs and literals): decode(size: 7×5) equals the pixels exactly

@Test func areaAveragesOnDownscale() throws
// 4 × 2: row 0 (0,0,0) (10,20,30) (100,100,100) (200,0,50); row 1 (2,2,2) (12,22,32) (100,100,100) (0,0,52)
// decode(size: 2×1) == [(6,11,16), (100,50,76)]  — mean of each 2×2 block, rounded half up (302 / 4 = 75.5 → 76)

@Test func regionMatchesCropOfFullDecode() throws
// 9 × 7 random: decode(region: (2,3,4,3), size: 4×3) == the full decode's pixels in that rect

@Test func regionAtImageEdge() throws
// 9 × 7: decode(region: (5,4,4,3), size: 2×2) == means over columns [5,7) [7,9) × rows [4,5) [5,7) (the decode's integer bounds)

@Test func takesTheICCProfile() throws
// icc: CGColorSpace(name: CGColorSpace.displayP3)!.copyICCData() → composite.icc equals it, decoded image's colorSpace?.copyICCData() equals it;
// no icc → colorSpace?.name == CGColorSpace.sRGB

@Test func declinesWhatImageIOReads() throws
// init returns nil for: depth 16, mode 4 (CMYK), mode 1 (grey), channels 4, compression 2, a file of 20 bytes, "8BPX" signature, version 3

@Test func corruptRLEThrows() throws
// RLE fixture with one row count raised past the file's end → decode throws; a row whose PackBits run decodes past the width → throws

@Test func truncatedRawThrows() throws
// raw fixture, init succeeds, then the file is truncated by 10 bytes → decode throws
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --filter PSDCompositeTests`
Expected: FAIL, `PSDComposite` not defined.

- [ ] **Step 3: Implement `PSDComposite`**

Header (big-endian): `8BPS`, version (1 PSD / 2 PSB), 6 reserved, channels (2), height (4), width (4),
depth (2), mode (2, RGB = 3); then colour mode data (4-byte length), image resources (4-byte length;
entries `8BIM`, id (2), Pascal name padded to even, size (4), data padded to even; keep id 1039),
layer and mask info (4-byte length in PSD, 8 in PSB), then the composite: compression (2). Raw: channel
planes one after another, `width` bytes per row. RLE: a table of `channels × height` row byte counts
(2 bytes each in PSD, 4 in PSB), then the PackBits rows in the same order; keep the prefix sums as row
offsets (`[Int]`, `channels × height + 1`).

Decode, as the spike: `DispatchQueue.concurrentPerform` over output rows; output row `oy` covers source
rows `r0 = y0 + oy * rh / oh ..< y0 + (oy + 1) * rh / oh`, output column `ox` covers source columns
`x0 + ox * rw / ow ..< x0 + (ox + 1) * rw / ow` (integer bounds, so every source pixel counts once).
Per channel one `pread` of the band's rows (raw: `(c * height + r0) * width` onward; RLE: from
`offsets[c * height + r0]` to `offsets[c * height + r1]`), loop on short reads, throw on 0 or -1.
RLE rows unpack (PackBits: n ≥ 0 copies n + 1 bytes, −127…−1 repeats the next byte 1 − n times, −128
skips) into a `width`-byte row; a row that doesn't come out at exactly `width` bytes throws. Sum per
output pixel in `UInt64` (a fit decode's box can exceed 2³² / 255 pixels), divide rounding half up. One file
descriptor per decode, opened in `decode`, closed with `defer`; errors inside the concurrent loop are
collected (a lock-protected flag) and thrown after it.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter PSDCompositeTests`
Expected: PASS (all 11 cases).

- [ ] **Step 5: Commit**

```bash
git add Sources/FeatherviewCore/Formats/PSDComposite.swift Tests/FeatherviewCoreTests/Formats/PSDFixture.swift Tests/FeatherviewCoreTests/Formats/PSDCompositeTests.swift
git commit -m "feat: own reader for the stored composite of 8-bit RGB PSD and PSB, at any size or region"
```

---

### Task 2: `RegionZoom`, when and which part to decode (Core)

**Files:**
- Create: `Sources/FeatherviewCore/Viewer/RegionZoom.swift`
- Test: `Tests/FeatherviewCoreTests/Viewer/RegionZoomTests.swift`

**Interfaces:**
- Consumes: `ImageDecoder.stepSize(full:step:)`, `PixelSize`.
- Produces (`public enum RegionZoom`):
  - `static func usesRegion(image: PixelSize, step: Int, screens: [PixelSize]) -> Bool` — the step
    decode (`stepSize` per side) holds more than 4 × the largest screen's pixel area.
  - `static func region(visible: CGRect, image: PixelSize, step: Int) -> CGRect` — `visible` in
    full-size pixels, grown by half its width and height on each side, snapped outward to multiples of
    `1 << step`, clamped to the picture; integral.
  - `static func decodeSize(region: CGRect, step: Int) -> PixelSize` — each side divided by `1 << step`,
    rounded up.
  - `static func needsNewRegion(visible: CGRect, decoded: CGRect, image: PixelSize) -> Bool` — true
    when `visible` (clamped to the picture) comes within an eighth of its own width (height) of a side
    of `decoded` that isn't the picture's edge.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func bigStepUsesRegion() {
    let screen = [PixelSize(width: 3024, height: 1964)]
    #expect(RegionZoom.usesRegion(image: PixelSize(width: 69536, height: 22230), step: 0, screens: screen))
    #expect(RegionZoom.usesRegion(image: PixelSize(width: 69536, height: 22230), step: 2, screens: screen))
    #expect(!RegionZoom.usesRegion(image: PixelSize(width: 4032, height: 3024), step: 0, screens: screen))  // 12 MP
    #expect(!RegionZoom.usesRegion(image: PixelSize(width: 12000, height: 8000), step: 3, screens: screen))
}

@Test func regionGrowsAndClamps() {
    let image = PixelSize(width: 69536, height: 22230)
    #expect(RegionZoom.region(visible: CGRect(x: 1000, y: 1000, width: 3000, height: 2000), image: image, step: 0)
            == CGRect(x: 0, y: 0, width: 5500, height: 4000))
    #expect(RegionZoom.region(visible: CGRect(x: 68000, y: 21000, width: 3000, height: 2000), image: image, step: 0)
            == CGRect(x: 66500, y: 20000, width: 3036, height: 2230))
}

@Test func regionAlignsToStep() {
    let r = RegionZoom.region(visible: CGRect(x: 10001, y: 10003, width: 3000, height: 2000),
                              image: PixelSize(width: 69536, height: 22230), step: 2)
    #expect(r == CGRect(x: 8500, y: 9000, width: 6004, height: 4004))  // grown 8501…14501 × 9003…13003, snapped to 4
    #expect(RegionZoom.decodeSize(region: r, step: 2) == PixelSize(width: 1501, height: 1001))
}

@Test func newRegionNearTheMarginOnly() {
    let image = PixelSize(width: 69536, height: 22230)
    let decoded = CGRect(x: 8500, y: 9000, width: 6000, height: 4000)
    #expect(!RegionZoom.needsNewRegion(visible: CGRect(x: 10000, y: 10000, width: 3000, height: 2000), decoded: decoded, image: image))
    #expect(RegionZoom.needsNewRegion(visible: CGRect(x: 11400, y: 10000, width: 3000, height: 2000), decoded: decoded, image: image))
    #expect(!RegionZoom.needsNewRegion(visible: CGRect(x: 0, y: 0, width: 3000, height: 2000),
                                       decoded: CGRect(x: 0, y: 0, width: 4500, height: 3000), image: image))  // picture's edge
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --filter RegionZoomTests` — Expected: FAIL, `RegionZoom` not defined.

- [ ] **Step 3: Implement `RegionZoom`** (pure arithmetic on `CGRect`/`Int`; work in `Int` and build the
  `CGRect` at the end so the tests compare exact values).

- [ ] **Step 4: Run them to verify they pass**

Run: `swift test --filter RegionZoomTests` — Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/FeatherviewCore/Viewer/RegionZoom.swift Tests/FeatherviewCoreTests/Viewer/RegionZoomTests.swift
git commit -m "feat: decide when a zoomed picture decodes only its visible part, and which part"
```

---

### Task 3: `ImageDecoder` routes PSD/PSB to the reader; part decodes; bench and budgets

**Files:**
- Modify: `Sources/FeatherviewCore/Imaging/ImageDecoder.swift` (`decodeFile`, `thumbnail`, two new functions)
- Modify: `Sources/FeatherviewBench/` (the `decode` subcommand: a `region` row)
- Modify: `AGENTS.md` (Performance budgets: "Huge pictures" row; `RegionDecode` in the signpost list)
- Test: `Tests/FeatherviewCoreTests/Imaging/PSDRoutingTests.swift`

**Interfaces:**
- Consumes: Task 1 `PSDComposite`, Task 2 `RegionZoom.decodeSize(region:step:)`.
- Produces (on `ImageDecoder`):
  - `public static func readsRegions(_ url: URL) -> Bool` — extension `psd`/`psb` (any case) and
    `PSDComposite(url:)` accepts it and its orientation (ImageIO property) is 1 or absent.
  - `public static func decodeRegion(_ url: URL, region: CGRect, step: Int, colorSpace: CGColorSpace?) throws -> CGImage`
    — `PSDComposite.decode(region:size: RegionZoom.decodeSize(region:step:))`, then `inColorSpace`;
    `DecodeError.unreadable(url)` when the reader declines or fails.
- Behaviour: in `decodeFile`, after the ImageIO source and `displaySize` (orientation known), a file that
  `readsRegions` decodes through `PSDComposite` at the longest side ImageIO would have used
  (`fit(size, exact: true)` — own-reader decodes are exact, like `OwnDecoders` — else the `halvingSteps`
  / `maxPixelSize` rule already there), the short side `round(short × longest / long)`, at least 1.
  `thumbnail` does the same at `min(side, longest)` (no embedded-thumbnail attempt for these files).
  Any throw from the reader falls back to ImageIO once, so a reader bug costs speed, not the picture.

- [ ] **Step 1: Write the failing tests** (`PSDRoutingTests.swift`, fixtures from Task 1's `PSDFixture`)

```swift
@Test(arguments: [0, 1]) func fastPathMatchesImageIO(compression: Int) throws
// 64 × 48 gradient PSD: ImageDecoder.decode(url) vs CGImageSourceCreateImageAtIndex of the same file → every channel within 2

@Test func fitDecodeIsExactSize() throws
// 400 × 200 PSD, decode(url, halvingSteps: true, fitting: [PixelSize(width: 100, height: 100)]) → 100 × 50 (ImageIO's path would give 200 × 100)

@Test func thumbnailUsesTheReader() throws
// 400 × 200 PSD, thumbnail(url, side: 64, colorSpace: nil) → 64 × 32

@Test func declinedPSDStillOpens() throws
// depth-16 and 4-channel fixtures: readsRegions false, decode(url) succeeds at full size (ImageIO)

@Test func readsRegionsOnlyForTheReader() throws
// raw PSB true, RLE PSD true, a .jpg from Fixtures false, depth-16 PSD false

@Test func decodeRegionMatchesCrop() throws
// 64 × 48 PSD: decodeRegion(url, region: (8, 8, 32, 16), step: 1, colorSpace: nil) is 16 × 8 and equals PSDComposite.decode(region:size:16×8)
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --filter PSDRoutingTests` — Expected: FAIL (`readsRegions` / `decodeRegion` missing).

- [ ] **Step 3: Implement the routing and the two functions** in `ImageDecoder.swift` as above.

- [ ] **Step 4: Run the new tests and the PSB suite**

Run: `swift test --filter "PSDRoutingTests|PSBTests|ImageDecoderTests"` — Expected: PASS
(`decodesAHandBuiltPSB` now takes the reader and must still pass; with the corpus present,
`FEATHERVIEW_SAMPLES=… swift test --filter PSBTests` must pass unchanged).

- [ ] **Step 5: Bench row and budgets**

In `featherview-bench decode`, for files where `ImageDecoder.readsRegions` is true, add a row
`region` per screen: the centre part `RegionZoom.region(visible:` the screen's size centred`, step: 0)`
through `decodeRegion`, timed like the other rows. Run
`swift run -c release featherview-bench decode ~/Downloads/hubble --screen 3024x1964 --runs 3`
(the maintainer's download; skip the step if absent and say so) and record fit, full and region times.
Add to AGENTS.md's budget table, after "Next/previous image, not prefetched":
`| Huge pictures | 8-bit RGB PSD/PSB through the own reader: heic1502a.psb (69,536 × 22,230, 4.6 GB) fit decode < 1 s cold, < 300 ms warm; a zoomed part on screen < 150 ms after panning stops (`RegionDecode`). Measured: <fill in> |`
and `RegionDecode` to the signpost list in the "How:" paragraph.

- [ ] **Step 6: Commit**

```bash
git add Sources/FeatherviewCore/Imaging/ImageDecoder.swift Sources/FeatherviewBench Tests/FeatherviewCoreTests/Imaging/PSDRoutingTests.swift AGENTS.md
git commit -m "feat: 8-bit RGB PSD and PSB decode through the own reader at the size needed"
```

---

### Task 4: Viewer shows a zoomed huge picture by parts (app)

**Files:**
- Create: `Sources/Featherview/Viewer/ViewerModel+Region.swift`
- Modify: `Sources/Featherview/Viewer/ViewerModel.swift` (`show()`'s zoomed branch, `shownStep`)
- Modify: `Sources/Featherview/Viewer/ImageCanvas.swift` (region layer, visible-rect reporting)
- Modify: `Sources/Featherview/Viewer/ViewerView.swift:130-138` (pass region and callback)
- Modify: `Sources/FeatherviewCore/Imaging/Signposts.swift` only if a name constant is wanted (the
  signpost is `Signposts.poster.beginInterval("RegionDecode", …)`)

**Interfaces:**
- Consumes: Task 2 `RegionZoom.usesRegion/region/needsNewRegion`, Task 3
  `ImageDecoder.readsRegions/decodeRegion`, `LatestWins` (Core), `knownInfo` page-0 size.
- Produces (model): `var region: (image: CGImage, rect: CGRect)?` (observed; `rect` in full-size
  pixels), `@ObservationIgnored var regionStep: Int?`, `func visibleRectChanged(_ rect: CGRect)`
  (full-size pixels), `private let regionDecodes = LatestWins()`.
- Produces (canvas): `ImageCanvas` gains `var region: (image: CGImage, rect: CGRect)? = nil`,
  `var fullPixelSize: CGSize? = nil`, `var onVisibleRect: (CGRect) -> Void = { _ in }`.

Behaviour:
- In `show()`'s zoomed branch (page 0, `compareSession == nil`, `pendingTransform` identity): after
  `zoomDecode(url)` gives `.step(step)` with `decode.cache === fullSizeCache`, if
  `RegionZoom.usesRegion(image:step:screens:)` and `readsRegions(url)` (off the main thread), decode
  the fit picture instead (`cache.image(for: url, target: .fit(screens))`, usually already there), show
  it with `fit: false` so the canvas draws it enlarged at the file's size (the path a smaller decode
  takes today), set `shownStep = (step, size)` so `setZoom` re-runs `show()` only when the step changes,
  and set `regionStep = step`. Every other case: `regionStep = nil`, `region = nil`, as today.
- `visibleRectChanged`: ignored while `regionStep` is nil; when `region` is nil or
  `needsNewRegion(visible:decoded:image:)`, submit to `regionDecodes`: `RegionZoom.region(...)`,
  `Task.detached` `decodeRegion(url, region:step:colorSpace: screenSpace)` inside a `RegionDecode`
  signpost; on return set `region` only if `list.current`, `regionStep` and the requested step still
  match. A failed part decode leaves the enlarged fit picture (no error message: the picture opened).
- `region = nil` and `regionStep = nil` on any `show()` of another file or page, on zoom to a fit mode,
  and when the step changes (the new step requests its own part).
- Canvas: `contentView.postsBoundsChangedNotifications = true`; a coordinator observes
  `NSView.boundsDidChangeNotification` and, with `updateNSView` after a resize, reports
  `scrollView.clearRect` intersected with the document, scaled by `fullPixelSize.width / size.width`
  (and height), via `onVisibleRect`. `ImageLayerView` gets `regionLayer` as a sublayer of `imageLayer`
  (so turns and the mirror apply to it), `contentsGravity = .resize`, frame = `rect` scaled to
  `imageLayer.bounds` by `bounds.width / fullPixelSize.width`, set in `show` and `layout()` with actions
  disabled, same magnification filter rule as the picture; nil region hides it.
- `// shortcut: compare panes and a pending rotation or flip decode whole steps (no parts), give them parts if people compare or turn huge pictures.`

- [ ] **Step 1: Build**: `swift build` — Expected: success, no new warnings.
- [ ] **Step 2: Full suite**: `swift test` — Expected: PASS.
- [ ] **Step 3: Bundle**: `scripts/bundle.sh debug` — Expected: `build/Featherview.app`.
- [ ] **Step 4: Commit**

```bash
git add Sources/Featherview/Viewer Sources/FeatherviewCore/Imaging/Signposts.swift
git commit -m "feat: a zoomed huge picture decodes only the part on screen"
```

---

### Task 5: Screen check (waits for the maintainer's go)

With `~/Downloads/hubble/heic1502a.psb` and a folder of 12 MP JPEGs, using the `run-featherview` skill
(caffeinate; guard each keystroke on the frontmost app):

- [ ] Open the PSB after a real quit and `sudo purge` (ask the maintainer to run it): `FirstImage` /
  `Navigate` < 1 s; then ←/→ away and back: < 300 ms.
- [ ] 1 (Actual Size): a sharp part within 150 ms of the key (`RegionDecode`), the enlarged fit picture
  meanwhile; drag and two-finger pan across the picture: parts follow, never a gap or a stale part.
- [ ] App footprint while at 100 % (`footprint -p Featherview` or Activity Monitor's Memory): below
  1 GB (today it would be over 6 GB).
- [ ] + / − through ½, ¼ and back to Fit: each step's part lands, Fit drops the part.
- [ ] 12 MP JPEG folder: `Navigate` p50/p95 unchanged against the AGENTS.md numbers; Actual Size on a
  JPEG decodes the whole step as before (no parts).
- [ ] Record the numbers in AGENTS.md's "Huge pictures" row, mark milestone 24 done in
  `docs/roadmap.md` and `ROADMAP.md`, commit `docs: huge pictures budgets measured`.
