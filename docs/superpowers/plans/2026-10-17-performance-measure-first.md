# Featherview — Performance Plan (measure first)

> Not a milestone in `docs/roadmap.md`: fixes to the viewer's speed and memory found in a code review,
> in the order the maintainer set. Don't add features here.
>
> **Done:** Tasks 1–5. Task 6 skipped for now (see its note). Open findings: "Not in this plan".
> **Addendum (review of Tasks 1–5):** Tasks 7–10 below. Task 8 decides whether Task 6's skip stands.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. In this repo, run it wave by wave with the `plan-wave` workflow.

**Goal:** Every speed or memory change has a number before and after. First a benchmark that runs
without a window, then the fixes the review found, most certain first.

**Status when written:** a code review only. Nothing was built or measured: the review ran on Linux
without Xcode. Every ms figure below is from code comments or an estimate, never a measurement.
The order of the review's findings was a guess, which is why measuring comes first.

**Spec and rules:** `AGENTS.md` "Performance budgets" (a regression is a bug), "Conventions".
`docs/spec.md` is silent on everything here except RAW and HDR ("Formats").

## Decisions the maintainer made (from the review discussion)

1. **Order:** benchmark (Task 1) → menu one-liner (Task 2) → fit decode per axis (Task 3) → zoom
   placeholder size (Task 4) → zoom decode size and prefetch (Task 5) → decode scheduling and cache
   budget together (Task 6). Task 6 starts only after a browsing baseline is recorded.
2. **Tasks 1 and 2 have no risk; do them as written.** Task 3 is the real gain: phone photos are
   portrait, and decoding them at 4× the pixels needed is a bug in the fit rule, not a tuning question.
3. **Scheduling and the cache budget go together (Task 6):** a byte budget decides what is dropped
   under pressure, and that is the same decision as what gets cancelled. Blocking ImageIO calls in
   `Task.detached` hold Swift's cooperative pool threads (one per core). The fix is our own queue with
   2–3 jobs.
4. **RAW embedded previews are a product decision, not an optimisation. Not in this plan.** The
   preview is the camera's JPEG with the camera's white balance and tone curve. ImageIO's full
   develop looks different, so showing the preview in fit mode and the develop when zoomed shifts
   colours on zoom. The maintainer says the reference viewer shows the preview by default, so this
   is defensible (not observed through `observe-reference`; record it in `docs/parity.md` if it is
   adopted). Preview size ranges from thumbnail to full resolution by camera, so a size check is
   required. Decide this in the spec before building it.
5. **Release:** ad-hoc signing is fine for the maintainer's own use. Once the app goes to anyone else,
   step one is a Developer ID signature plus notarization, not Sparkle. Without them, macOS 15+ users
   must allow the app in System Settings, and TCC asks for every folder permission again after each
   update, which works against a fast viewer. Leaving out an Intel build is a decision, not a gap.
   Neither is in this plan.

## Global Constraints

- macOS 14.0 minimum; Swift 6 language mode, strict concurrency. No new dependency.
- `FeatherviewCore` never imports SwiftUI or AppKit (`os` and ImageIO are fine).
- TDD for `FeatherviewCore` (Swift Testing, images from `Fixtures`, never committed binaries). The
  app target and the benchmark executable are checked by hand.
- Every task that changes decoding, caching or scheduling records the benchmark before and after
  in "Measurements" at the end of this file, on the same Mac and with the same command. A median
  that gets worse by more than 10 % without an accepted reason is a failed task.
- Commit messages: conventional commits, no AI attribution lines.
- Keep `shortcut:` comments for known limits, in the form `shortcut: <limit>, <when to upgrade>`.

## Review Focus

- Fit decode size at the exact boundary: a 3024×4032 portrait on a 3024×2016 screen needs exactly
  2016 px, so the ½ step (2016) must be chosen, not full size. Floating point gives 2016.0000001 and
  rounds up to full size. Pinned in Task 3 (`fitDecodeSizeExactBoundary`).
- EXIF-rotated images: the fit is computed on the *displayed* size (orientation applied), as
  `displaySize` returns it. Pinned in Task 3 (`fitDecodeUsesDisplayedOrientation`).
- Several screens: the decode must be big enough for the most demanding screen, not the one with the
  longest side. Pinned in Task 3 (`fitDecodeSizeTakesTheMostDemandingScreen`).
- Zoom placeholder: while the full-size decode loads, the fit decode is drawn at the size the full
  image will have, so nothing shrinks or jumps. Pinned in Task 4 (`zoomDrawSizeUsesFullPixels`).
- The benchmark must call the same code paths the viewer calls, or before and after mean nothing.

---

## Wave plan

| Wave | Tasks | Why |
|---|---|---|
| A | 1, 2 | independent: benchmark + signposts, and a one-line menu fix |
| B | 3, 4 | fit decode (Core + cache + viewer) and zoom placeholder (ZoomSteps + view): different files. Needs 1 for numbers |
| C | 5 | zoom decode size and prefetch: builds on the cache key from 3 and the draw size from 4 |
| D | 6 | scheduling + byte budget: only after a browsing baseline from Task 1's `browse` mode is in "Measurements" |
| E | 7, 8 | addendum: own formats at the exact fit size (Core), and a slow-decode gate for Task 6 (bench corpus): different files |
| F | 9, 10 | addendum: measurements in the app (navigate metric and outlier, memory pressure); one Mac, one at a time |

| Task | Needs |
|---|---|
| 1 | — |
| 2 | — |
| 3 | 1 |
| 4 | 2 (same file, `ViewerView.swift`) |
| 5 | 3, 4 |
| 6 | 3, and a recorded `browse` baseline |
| 7 | 3 |
| 8 | 3 |
| 9 | 2 |
| 10 | 8 |

---

### Task 1: `featherview-bench` and signposts

**Files:**
- Modify: `Package.swift` (product + target)
- Create: `Sources/FeatherviewBench/main.swift`, `Sources/FeatherviewBench/Corpus.swift`,
  `Sources/FeatherviewBench/Footprint.swift`
- Create: `Sources/FeatherviewCore/Signposts.swift`
- Modify: `Sources/FeatherviewCore/ImageCache.swift` (decode interval)
- Modify: `Sources/Featherview/ViewerModel.swift`, `Sources/Featherview/ImageCanvas.swift`,
  `Sources/Featherview/ViewerView.swift` (navigate interval, scan interval, first-image event)
- Modify: `AGENTS.md` "Commands" and "Performance budgets" → "Measure" (two lines: how to run the bench)

**Package:** add `products: [.executable(name: "featherview-bench", targets: ["FeatherviewBench"])]`
and `.executableTarget(name: "FeatherviewBench", dependencies: ["FeatherviewCore"])`. The app stays
the only thing `scripts/bundle.sh` packages.

**Corpus (`Corpus.swift`):** `featherview-bench corpus <dir>` writes generated images, never
committed. The content must not be a solid colour (solid colours compress to nothing and decode
unrealistically fast): a diagonal gradient plus deterministic per-pixel noise (an integer hash of
x, y), so JPEG sizes come close to real photos (12 MP ≈ 3–6 MB at quality 0.9). Files:

| Name | Size | Type | Note |
|---|---|---|---|
| `12mp-landscape.jpg` | 4032×3024 | JPEG q0.9 | |
| `12mp-portrait.jpg` | 3024×4032 | JPEG q0.9 | |
| `12mp-portrait-exif6.jpg` | 4032×3024 stored | JPEG q0.9 | orientation 6, so it displays as portrait |
| `50mp-landscape.jpg` | 8688×5792 | JPEG q0.9 | |
| `50mp-portrait.jpg` | 5792×8688 | JPEG q0.9 | |
| `12mp-landscape.heic` | 4032×3024 | HEIC q0.8 | |
| `12mp-portrait.heic` | 3024×4032 | HEIC q0.8 | |
| `12mp.png` | 4000×3000 | PNG | no halving steps in PNG: decode cost is the full image |
| `browse/0001.jpg` … `browse/0040.jpg` | 4032×3024 / 3024×4032 alternating | JPEG q0.9 | for `browse` |

Generating 50 MP in a debug build is slow; the usage text says to run with `-c release`.
RAW: no generator. `--raw <dir>` adds the maintainer's own camera files to `decode`; they are never
copied into the repo or the corpus.

**`decode` mode:** `swift run -c release featherview-bench decode <dir> [--screen WxH ...] [--runs 10] [--json out.json] [--baseline in.json]`
- Screens default to `3024x1964` (MacBook Pro 14"), `3456x2234` (16"), `5120x2880` (5K), all in pixels.
- For every file × screen: call the viewer's fit decode *exactly as `ViewerModel` + `ImageCache`
  call it today*: `ImageDecoder.decode(url, maxPixelSize: max(screen.w, screen.h), halvingSteps: true,
  hdr: ImageDecoder.supportsHDR, colorSpace: CGColorSpace(name: CGColorSpace.displayP3))`. Keep that call in
  one function, `fitDecode(_:screens:)`, in `main.swift`: Task 3 changes only that function, so the
  numbers stay comparable.
- Plus one full-size decode per file (`maxPixelSize: nil, halvingSteps: true`): today's zoom path, the baseline for Task 5.
- Report per row: file, screen, decoded W×H, MB (`bytesPerRow × height`), first run ms, then median /
  p95 / min ms of `--runs`. A first run reads the file from disk; true cold needs `sudo purge`
  first, which the bench never runs itself (the usage text says so).
- `--json` writes the rows. `--baseline` compares medians and exits 1 if any row is > 10 % slower,
  printing which.

**`browse` mode:** `featherview-bench browse <dir>/browse [--interval-ms 300] [--screen WxH]`
simulates arrow-key browsing through an `ImageCache(capacity: 8, …)` the way `ViewerModel.show()`
uses it today: cancel the previous step's task; `await cache.image(for: current, maxPixelSize:)`;
then `cache.prefetch(neighbors radius 2)` (copy `ImageList.neighbors`). Start a step every
`--interval-ms` whether or not the last one finished (that is what a held key does). Report:
- per step: ms from step start until its image is returned (or "superseded" when cancelled first),
  split by whether the image was already cached;
- median / p95 / max of the returned steps, count superseded;
- peak decoded bytes the cache keeps (`ImageCache.decodedBytes`, `bytesPerRow × height`, the same cost
  Task 6 budgets) and peak memory footprint (`Footprint.swift`: `task_info(TASK_VM_INFO)` → `phys_footprint`,
  which leaves out the decoded images: ImageIO keeps them in purgeable volatile memory), both sampled
  every step).
Run at 300 ms (reading pace) and 30 ms (held key, macOS key repeat at its fastest). This is
Task 6's baseline: Task 6 must not make 300 ms worse and should improve 30 ms.

**Signposts (`Signposts.swift` in Core):**
```swift
import os
public enum Signposts {
    /// Shows in Instruments' Points of Interest and in the os_signpost instrument.
    public static let poster = OSSignposter(subsystem: "net.mynetx.featherview", category: .pointsOfInterest)
}
```
(If strict concurrency rejects the `static let`, wrap it in a `Sendable` box and say why in one line.)
- `Decode` interval around the `ImageDecoder.decode` call inside `ImageCache`'s detached task
  (`ImageCache.swift`, the `Task.detached` in `image(for:maxPixelSize:)`); metadata: file name and
  `maxPixelSize`.
- `Scan` interval around `FolderScanner.images` in `ViewerModel.open` (both call sites).
- `Navigate` interval: begins in `ViewerModel.show(page:)`, ends when the canvas has committed that
  image. `ImageLayerView.show` gets an `onCommit: (CGImage) -> Void`, called from
  `CATransaction.setCompletionBlock` only when `contents` changed. `ViewerModel` keeps the pending
  interval state and the URL. It ends the interval with `prefetched: yes/no` when the committed image
  is the one it waits for, and ends a superseded interval as `superseded` when `show` is called again.
- `FirstImage` event in `firstImageDrawn()`. The existing log line stays (AGENTS.md documents it).
  Its comment should say that it measures until the model has the image, not until the image is on
  screen; `Navigate` covers that.

- [x] Write the corpus generator; run it; check sizes and that `12mp-portrait-exif6.jpg` shows upright in Preview
- [x] Write `decode` mode with `fitDecode` mirroring today's call; run it on the maintainer's Mac
- [x] Write `browse` mode and `Footprint.swift`; run at 300 ms and 30 ms
- [x] Add the signposts; `swift build`, `swift test` pass
- [x] Check in Instruments (Points of Interest) that `Navigate`, `Decode` and `Scan` appear while browsing the corpus
- [x] Record all numbers in "Measurements" (machine, macOS, commit)
- [x] Commit: `feat: featherview-bench and signposts for decode, scan and navigation`

### Task 2: The menu stops re-reading the image list

`ViewerView.swift:394`, in `ViewerCommands`, Save As reads `model?.list.current` and
`model?.list.isHolding`. That makes `ViewerCommands` depend on `list`, so every arrow key
re-evaluates the commands and SwiftUI rebuilds the main menu on the main thread. All other items read
`availability`, which `ViewerModel.updateAvailability()` sets only when a value flips.
`availability.canChangeFile` is exactly `list.current != nil && !list.isHolding`.

**Files:** Modify `Sources/Featherview/ViewerView.swift` (one line).

- [x] Replace with `.disabled(model?.availability.canChangeFile != true)`
- [x] By hand: Save As is disabled with no image, enabled with one, disabled on a held (trashed, "show the next image" off) image
- [x] If Task 1 is merged: compare `Navigate` p50 before/after in Instruments while browsing `browse/` at 300 ms (expect a small gain; record it, even if zero)
- [x] Commit: `fix: the menu no longer rebuilds on every image`

### Task 3: Fit decode per axis

**Bug:** `ImageDecoder.decodeSize(full:target:)` is called with `target` = the longest side of the
*largest* screen (`ViewerModel.swift:97-99`) and compares it with the image's longest side
(`ImageDecoder.swift:88`). A portrait image on a landscape screen is limited by the screen's
*height*, so it gets decoded much larger than it can be shown:

| Image | Screen | Today | Needed | Per axis |
|---|---|---|---|---|
| 3024×4032 | 3024×1964 | 4032 (full) | 1964 | 2016 (½), ¼ of the pixels |
| 4032×3024 | 3024×1964 | 4032 | 2619 | 4032 (unchanged) |
| 8688×5792 | 5120×2880 | 8688 (full, ≈ 200 MB) | 4320 | 4344 (½, ≈ 50 MB) |
| 5792×8688 | 5120×2880 | 8688 (full) | 2880 | 4344 (½) |

**Files:**
- Modify: `Sources/FeatherviewCore/ImageDecoder.swift`, `Sources/FeatherviewCore/ImageCache.swift`
- Modify: `Sources/Featherview/ViewerModel.swift` (screens instead of `screenPixels`)
- Modify: `Sources/FeatherviewBench/main.swift` (`fitDecode` only)
- Test: `Tests/FeatherviewCoreTests/ImageDecoderTests.swift`, `Tests/FeatherviewCoreTests/ImageCacheTests.swift`

**Interfaces (produces):**
```swift
/// A screen's size in pixels (points × backing scale).
public struct PixelSize: Hashable, Sendable { public let width: Int; public let height: Int }

extension ImageDecoder {
    /// The longest side to decode an image of `image` (displayed size, orientation applied) at, so it
    /// fits any of `screens` without enlarging: the smallest halving step at or above that size.
    /// Integer arithmetic: `ceil(longest × screen.h / image.h)`, never Double (see Review Focus).
    public static func fitDecodeSize(image: PixelSize, screens: [PixelSize]) -> Int
}
```
- `ImageDecoder.decode` gets a `fitting screens: [PixelSize]? = nil` parameter. When set, it computes
  `fitDecodeSize` from the `displaySize` it already reads (`ImageDecoder.swift:79`) and uses that as
  `kCGImageSourceThumbnailMaxPixelSize`. Own formats: scale to the same size. `maxPixelSize` keeps
  its meaning for batch and the other callers.
- `ImageCache`: the request key becomes an enum `DecodeTarget: Hashable, Sendable { case full; case
  fit([PixelSize]) }` in place of `maxPixelSize: Int?` (the cache is only used by the viewer; check
  with grep). "Joined only at the same size" stays: same target, not same Int.
- `ViewerModel`: `screens` = every `NSScreen` as `PixelSize` (frame × backingScaleFactor), read once
  like today; empty → `[PixelSize(width: 2560, height: 1600)]`.
  shortcut: screens are read at launch; a display plugged in later decodes for the old set, re-read on `NSApplication.didChangeScreenParametersNotification` if that comes up.

**Tests first:**
- `fitDecodeSize` table: the four rows above; `40×20` on any screen → 40 (never upscales);
  `fitDecodeSizeExactBoundary`: 3024×4032 on 3024×2016 → 2016;
  `fitDecodeSizeTakesTheMostDemandingScreen`: 3024×4032 on [3024×1964, 5120×2880] → 4032 (the 5K needs
  2880 > 2016).
- `fitDecodeUsesDisplayedOrientation`: a 4000×2000 JPEG with orientation 6 (displays 2000×4000) on a
  3000×1000 screen → decoded 500×1000.
- `ImageCache`: two requests for the same URL with different `fit` targets don't join; same target joins.
- Existing `decodeSizeIsSmallestHalvingStepAtOrAboveTarget` stays unchanged (`decodeSize` is reused).

- [x] Failing tests, then `fitDecodeSize`, then the decode parameter, then the cache key, then the viewer
- [x] Update `fitDecode` in the bench; run `decode` before (Task 1's numbers) and after; record both
- [x] By hand: a portrait photo fills the window height sharply at fit; full screen on a 5K display stays sharp (no 5K display: checked by numbers, 50 MP on 5120×2880 decodes to 4344×2896 for a 4320×2880 fit, portrait 2896×4344 for 1920×2880)
- [x] Update `AGENTS.md` "Performance budgets" memory line: "decoded to fit the screen per axis"
- [x] Commit: `fix: fit decodes portrait images at the size the screen shows`

### Task 4: Zoom placeholder at the right size

**Bug:** `ViewerView.drawSize` (`ViewerView.swift:127-134`) computes `.factor` from the *decoded*
image's pixels. On the first zoom step from fit, `ViewerModel.setZoom` starts a full-size decode and
the fit decode stays on screen meanwhile. For a 50 MP image (fit decode 4344 px), that draws at
4344 × factor instead of 8688 × factor: it shows at half size, then jumps when the full decode lands
(hundreds of ms, estimated).

**Files:**
- Modify: `Sources/FeatherviewCore/ZoomSteps.swift`, `Sources/Featherview/ViewerView.swift`
- Test: `Tests/FeatherviewCoreTests/ZoomStepsTests.swift`

**Interfaces (produces):**
```swift
extension ZoomSteps {
    /// Points to draw `decoded` at. Fit: shrink to `view`, never enlarge (as today, from `decoded`).
    /// Factor: from `full` (the file's displayed pixel size) when known, so a smaller decode shown
    /// while the full one loads already has its final size; from `decoded` when `full` is nil.
    public static func drawSize(decoded: CGSize, full: CGSize?, factor: Double?, view: CGSize,
                                displayScale: Double) -> CGSize
}
```
- `ViewerView.drawSize` calls it with `full = model.fileInfo?.pixelSize` only when
  `model.fileInfo?.isFor(model.list.current, page: model.page) == true` (never another file's size).

**Tests first:** `zoomDrawSizeUsesFullPixels`: decoded 4344×2896, full 8688×5792, factor 0.44, scale 2
→ 1911.36×1274.24 pt. `full` nil → from decoded (today's result). Fit: unchanged results for a
small image (never enlarged) and a large one.

- [x] Failing tests, `ZoomSteps.drawSize`, view uses it
- [x] By hand with `50mp-landscape.jpg`: + from fit grows the image a little and it sharpens when the decode lands; no shrink, no jump; the point under the window centre stays put
- [x] Commit: `fix: zooming from fit no longer shows the image at half size first`

### Task 5: Zoom decode at the needed step, prefetch while zoomed

Part two of the zoom finding. Today every `.factor` zoom decodes full size (`ViewerModel.swift:318,
344-345`), even at 25 %, and browsing while zoomed prefetches nothing (`ViewerModel.swift:371`:
`if let size`), so every next image is an uncached full decode.

**Design (write the exact interfaces when starting; the plan-wave reviewer checks these points):**
- Decode for a factor at `decodeSize(full:, target: ceil(longest × factor))`, so a factor ≤ ½ needs
  no full decode. `DecodeTarget` gets `case step(Int)` (the halving step, not the factor), so zooming
  within a step never re-decodes. Zooming past the decoded step shows the current image
  enlarged (Task 4 keeps its size right) and decodes the next step.
- Keep `fullSizeCache` capacity 1 for steps above fit size. While zoomed, prefetch ±1 at the current
  step, not ±2: these images are large.
- Bench: add a `zoom` row per 50 MP file at factors 0.25, 0.5 and 1.0.

- [x] Interfaces + failing tests (step choice per factor, no re-decode within a step)
- [x] Viewer: target per factor; prefetch ±1 while zoomed
- [x] Bench before/after (done, see Measurements); by hand: browse 50 MP images at 50 % zoom, next image shows without waiting for a full decode (app, 8 × 50 MP landscape, zoomed in 6 steps from fit, Space × 7 at 1.5 s: every next image shown in 19–25 ms, prefetched; the two zoom steps that needed a new decode took 81 and 154 ms)
- [x] Commit: `perf: zoom decodes at the step it shows and prefetches while zoomed`

### Task 6: Decode scheduling and a byte budget, together

**Skipped for now.** The gate run (Measurements, "6 (gate)") showed no queueing problem, and the maintainer chose to skip the byte budget too (peak 243 MB decoded while browsing).

**Task 8 gate: the skip no longer holds for scheduling.** On slow decodes (Measurements, "8 (gate)", 12 MP HEIC and 50 MP JPEG on the 10-core M1 Pro), a held key at 30 ms shows the last HEIC 2.0× slower than its solo fit decode (258 vs 132 ms), over the 1.5× gate; 50 MP JPEG stays under (1.4×). The scheduling part is due; the byte-budget part follows Task 10.

**Don't start until** Task 3 is merged and a `browse` baseline at 300 ms and 30 ms (after Task 3) is in
"Measurements". If the 30 ms numbers show no queueing problem, stop and report: the finding was
estimated.

**Findings:**
- Decodes are `Task.detached(priority: .userInitiated)` running blocking ImageIO calls
  (`ImageCache.swift`, `image(for:)`; `ViewerModel.swift:335`). They hold cooperative pool threads
  (one per core), all at the same priority: the current image, ±1, ±2, and superseded decodes that
  can't be stopped once running. With a held key, stale work makes the current image wait.
- `ImageCache` counts images (8 + 1), not bytes, and ignores memory pressure (`ImageCache.swift:16,
  86-90`). `ViewerModel.ready` holds strong references outside the budget.

**Design (one decision, two parts):**
- A `DecodeQueue` in Core: its own threads (a `DispatchQueue`-backed executor or an `OperationQueue`
  with `maxConcurrentOperationCount` 2–3, measured), outside the cooperative pool. Jobs carry a rank:
  current = 0, ±1 = 1, ±2 = 2, by browsing direction (a forward run prefetches +1, +2, +3, then −1).
  When the current image changes, waiting jobs outside the new window are dropped before they start.
  Running jobs finish; their result is stored only if still inside the window and the budget.
- Byte budget: cost = `bytesPerRow × height`. Default `min(physicalMemory / 5, 2 GB)`; the current
  image is always kept even if larger. Eviction: farthest from current first, not least recently used.
  `ready` counts against the same budget (it must not keep what the cache evicted).
- Memory pressure (`DispatchSource.makeMemoryPressureSource`): `.warning` → keep current ±1 and drop
  waiting prefetch jobs; `.critical` → current only. These are the same jobs the budget drops, which is
  why the two parts are one task.

- [ ] Interfaces + failing tests: rank order, dropping waiting jobs on a move, budget eviction by distance, pressure levels (inject the pressure event)
- [ ] Replace the detached decodes in `ImageCache` and `ViewerModel` (page decodes too)
- [ ] Bench `browse` at 300 ms and 30 ms, and `decode` (must not regress); record all
- [ ] Commit: `perf: decode on our own queue, nearest first, within a byte budget`

---

## Addendum: review of Tasks 1–5

A review of the merged Tasks 1–5 (`1121cfe..759684e`, code and Measurements read, nothing built: the
review ran on Linux again) found four open points. They are Tasks 7–10. Task 8 comes first in
importance: it decides whether the Task 6 skip holds beyond the easy case it was measured on.

### Task 7: Own formats decode at the exact fit size

**Finding:** Task 3 gave own formats the halving step too (`ImageDecoder.swift`, `decodeFile`, own-format
branch: `limit = own.size(data, page).flatMap(fit)`). Halving steps only pay off in JPEG, which decodes
them directly. Own raster decoders always decode at full size and then resample in `scaled`, and that
resample costs the same for any target. Rounding up to the step only keeps more pixels:
- A 4000×3000 QOI on a 3024×1964 screen needs 2619 px. The step gives full size (4000), and before
  Task 3 it was 3024 (the screen's longest side).
- An SVG renders at the step, up to 2× the needed size per side, so up to 4× the pixels.

**Files:**
- Modify: `Sources/FeatherviewCore/ImageDecoder.swift`
- Test: `Tests/FeatherviewCoreTests/ImageDecoderTests.swift`
- Modify: `Sources/FeatherviewBench/main.swift` (only for the PNG/HEIC experiment below)

**Interfaces:**
```swift
extension ImageDecoder {
    /// The longest side an image of `image` (displayed size) needs to fit any of `screens` without
    /// enlarging: `fitDecodeSize` before it rounds up to a halving step. Integer arithmetic, as there.
    static func fitNeededSize(image: PixelSize, screens: [PixelSize]) -> Int
}
```
- `fitDecodeSize` becomes `decodeSize(full: longest, target: fitNeededSize(...))`, with unchanged results
  (its existing tests stay as they are).
- Own formats in fit mode: `limit = fitNeededSize(...)`. Zoom steps (`step`) for own formats stay as
  they are: the cache keys them by step.

**Tests first:**
- `ownFormatsDecodeAtTheExactFitSize`: a 4000×3000 QOI (`QOICodec.encode` of an `RGBAImage`, as in
  `QOICodecTests`) decoded `fitting: [3024×1964]` → 2619×1964.
- `fitNeededSize` table: the four rows of Task 3's table give 1964, 2619, 4320, 2880.

**Experiment, then decide (PNG and HEIC through ImageIO):** the same question applies there.
`kCGImageSourceThumbnailMaxPixelSize` at the needed size instead of the step could be smaller and no
slower. Add a temporary `--exact` flag to `decode` that passes `fitNeededSize` as `maxPixelSize` instead
of the step, and run both on `12mp.png`, `12mp-landscape.heic` and `12mp-portrait.heic` (3024×1964
screen, 10 runs). If exact is at most 10 % slower than the step and smaller, use exact for every type
except JPEG, record the rule in `AGENTS.md` "Performance budgets" → "How", and keep the flag out of the
commit. Otherwise record the numbers and leave ImageIO types alone.

- [ ] Failing tests, `fitNeededSize`, own formats use it
- [ ] PNG/HEIC experiment; record numbers; act on the rule above
- [ ] `decode` with `--baseline` against the latest JSON: no row slower
- [ ] Commit: `fix: own formats decode at the size the screen needs, not a JPEG step`

### Task 8: Slow-decode gate for Task 6

**Finding:** the "6 (gate)" row measured only the easy case: `browse/` holds 12 MP JPEGs (33–82 ms each),
on a 10-core M1 Pro with a local SSD. The finding behind Task 6 is that blocking ImageIO calls fill
Swift's cooperative pool, and it shows only when decodes are slow. HEIC is the iPhone's default
format and decodes in 123–232 ms (Measurements, Tasks 1 and 3). 50 MP JPEGs and Macs with fewer cores
are slower still. The skip holds only for what was measured.

**Files:** Modify `Sources/FeatherviewBench/Corpus.swift` (two folders), and this file's Measurements.

**Corpus:** add `browse-heic/0001.heic … 0040.heic` (12 MP, alternating landscape and portrait like
`browse/`, HEIC q0.8) and `browse-50mp/0001.jpg … 0020.jpg` (8688×5792 and 5792×8688 alternating, JPEG q0.9).

**Runs:** on each folder, `browse --interval-ms 300` and `--interval-ms 30`, 3 runs each, after one
warm-up run (Measurements showed the first run is cold). Also take the solo fit-decode median of the
same files from `decode` (one file of each orientation is enough).

**Gate:** at 30 ms, compare the median of the returned not-cached steps with the solo fit-decode
median.
- Up to 1.5× the solo decode: no queueing problem, Task 6 stays skipped. Record this in Task 6's note,
  with the formats and the Mac it was measured on.
- Over 1.5×, or a 300 ms run with superseded steps (prefetch not keeping up at reading pace): stale
  work delays the current image. Then Task 6's scheduling part is due. The byte-budget part follows
  Task 10.
- If a Mac with fewer cores is at hand (base M1/M2, MacBook Air), run the HEIC folder there too. That
  one counts more than the M1 Pro.

- [ ] Corpus folders; runs; gate verdict recorded in Measurements and in Task 6's note
- [ ] Commit: `test: bench corpus for slow decodes, and the Task 6 gate on them`

### Task 9: One navigation metric in the budget, and the 170 ms outlier

**Finding:** `AGENTS.md` "Performance budgets" says "≈ 20 ms to swap is fine; measured 11 ms median".
That is the old log line, which measures until the model has the image. The `Navigate` signpost from
Task 1 measures until Core Animation has committed it, which is what the user sees: p50 23.5–25 ms,
p95 36–41 ms, max 170–173 ms (Measurements, row "2"). Its median is above "≈ 20 ms", and its max is
above the 150 ms budget for a *non*-prefetched image. Both were already true before Task 2.

**Files:** Modify `AGENTS.md` ("Performance budgets"); Measurements. Code only if the outlier has a fix
inside this plan's scope (otherwise report it).

- [x] Ask the maintainer which metric the "next/previous" budgets mean (recommended: `Navigate`, it is
      what the user sees). Write it into both rows, with today's `Navigate` numbers instead of "measured
      11 ms median"
- [x] Find the outlier: in the app, 39 × → through `browse/` at 300 ms, recorded in Instruments with
      Points of Interest + Time Profiler. Take the `Navigate` intervals over 100 ms, check whether they
      were prefetched, and see what the main thread did during them (decode, colour conversion, SwiftUI
      update, toolbar, first draw)
- [x] Record the cause in Measurements. A fix goes in its own commit with before/after numbers, or under
      "Not in this plan" if it's outside scope
- [x] Commit: `docs: next/previous budgets measured as Navigate`

### Task 10: Are decoded images purgeable, and what happens under memory pressure

**Finding:** the bench shows a peak of 243–390 MB decoded in the cache but an 8 MB process footprint.
The bench's explanation is that ImageIO keeps decoded pixels in purgeable volatile memory, which
`phys_footprint` leaves out. That is a hypothesis, and both of its outcomes matter:
- If true, macOS reclaims the cache by itself under pressure. That is the real argument for skipping
  Task 6's byte budget.
- The price would be that an image whose pixels were purged is decoded again lazily, possibly on the
  main thread, when Core Animation draws it. That would be a stall the user sees.

**Files:** none in code unless the result asks for it; Measurements; Task 6's note.

- [ ] Confirm the hypothesis: while `browse` runs at 300 ms, `vmmap --summary <pid>` (or `footprint -v
      <pid>`) shows the purgeable-volatile size. Record it beside the bench's decoded bytes. Note that
      images redrawn into the screen's colour space (`ImageDecoder.redrawn`) come from a `CGContext`, not
      from ImageIO, so check which of the two the purgeable memory is
- [ ] Browse under pressure: in the app, 39 × → through `browse/` at 300 ms, once normally and once while
      `memory_pressure -l warn` runs (never `critical` on the working Mac). Record `Navigate` p50/p95/max
      for both, and look in Time Profiler for ImageIO decode frames on the main thread
- [ ] Verdict in Task 6's note:
      - No main-thread re-decode and p95 within 1.5×: the byte budget stays skipped, with this row as
        the reason.
      - Otherwise: Task 6's budget and pressure part is due, independent of Task 8's verdict on scheduling.
- [ ] Commit: `docs: decoded images under memory pressure, Task 6 budget verdict`

---

## Not in this plan (review findings left open)

- RAW embedded previews: see Decision 4; spec first.
- Display colour space fixed to the main screen at launch (`ViewerModel.swift:103`): on another
  display Core Animation converts each image on the main thread. HDR images are never pre-converted
  (`ImageDecoder.swift:66`).
- Up to four file opens per image (`ImageDecoder.swift:79-80`, `FileInfo.swift:16`,
  `OverlayTemplate.swift:11`). Cheap locally, measurable on SMB or USB disks.
- No folder watching; cache key is the URL only (an image edited elsewhere shows stale).
- `isFolderPath` on the main thread in `open` and `cache.removeAll()` on every open
  (`ViewerModel.swift:159, 168`).
- Release: Developer ID + notarization first once the app is shared (Decision 5).
- App-level launch and browse timing through `osascript` key events and Instruments: only if
  browsing itself misbehaves after Task 6 (the maintainer's call).

## Measurements

Same Mac, same command, release build. Fill in per task; never edit an earlier row.

| Task | Commit | Mac / macOS | Command | Result |
|---|---|---|---|---|
| 1 (baseline) | 5d02ec6 | Apple M1 Pro, 32 GB / macOS 27.0.1 | `featherview-bench decode <dir>` | Fit decode median (every screen unless noted): 12 MP JPEG 81–83 ms, always full size 4032×3024 (48.8 MB); EXIF-6 JPEG 110–112 ms; 12 MP HEIC 225–233 ms; 12 MP PNG 216 ms; 50 MP JPEG 119–128 ms at ½ (50.3 MB) on 3024 and 3456 screens, 336–359 ms full (201.3 MB) on 5120; full-size decode 50 MP 361–365 ms. JSON: `build/bench/baseline-task1.json` |
| 1 (baseline) | 5d02ec6 | Apple M1 Pro, 32 GB / macOS 27.0.1 | `featherview-bench browse <dir>/browse --interval-ms 300` | 40 returned, 0 superseded; cached 39: median 0.2 ms, p95 0.3 ms; not cached 1: 115 ms; peak cache 390 MB decoded, footprint 8 MB |
| 1 (baseline) | 5d02ec6 | Apple M1 Pro, 32 GB / macOS 27.0.1 | `featherview-bench browse <dir>/browse --interval-ms 30` | 1 returned (92 ms), 39 of 40 superseded: nothing is shown until the key is let go; peak cache 390 MB decoded, footprint 280 MB |
| 3 (after) | task-3 | Apple M1 Pro, 32 GB / macOS 27.0.1 | `featherview-bench decode <dir> --baseline build/bench/baseline-task1.json` | Portrait on 3024x1964 now at ½: 12 MP JPEG 83.0 → 33.7 ms (48.8 → 12.2 MB), EXIF-6 JPEG 111.3 → 42.1 ms, 12 MP HEIC 231.8 → 123.0 ms, 50 MP portrait 128.4 → 71.5 ms (50.3 → 12.6 MB). 5120x2880: 50 MP landscape 359.0 → 128.7 ms and portrait 336.5 → 123.3 ms, both at ½ (201.3 → 50.3 MB). Landscape 12 MP and portrait on 3456x2234 decode the same size as before (2234 > 2016 needs full). Only `--baseline` flag: 12 MP landscape JPEG full 81.8 → 90.9 ms, a path this task doesn't change; load average 4–6 from other builds during the run (a first run under more load flagged every landscape row). JSON: `build/bench/after-task3.json` |
| 3 (after) | task-3 | Apple M1 Pro, 32 GB / macOS 27.0.1 | `featherview-bench browse <dir>/browse --interval-ms 300` | 40 returned, 0 superseded; cached 39: median 0.2 ms, p95 0.7 ms; not cached 1: 114 ms; peak cache 243 MB decoded (was 390), footprint 8 MB |
| 6 (gate) | f98ea83 | Apple M1 Pro, 32 GB / macOS 27.0.1 | `featherview-bench browse <dir>/browse --interval-ms 30`, 6 runs | Runs 2–6: 19–20 of 40 returned, every other image shown from cache (0.1 ms), the rest superseded; not cached 33–35 ms, the same as one fit decode, so no stale work delays the current image. Run 1 (cold disk, load average 4): 1 of 40 returned, 41 ms. Peak cache 243 MB decoded, footprint 214–272 MB. No queueing problem: Task 6 stops here per its gate, reported to the maintainer |
| 5 (after) | 4a2ffd0 | Apple M1 Pro, 32 GB / macOS 27.0.1 | `featherview-bench decode <dir>`, zoom rows, 5 runs, load average ~5.6 | Before: every zoom decoded full size, ~355 ms, 201.3 MB. After, 50 MP landscape: 0.25 → 2172×1448 66 ms 12.6 MB; 0.5 → 4344×2896 121 ms 50.3 MB; 1.0 → full 354 ms 201.3 MB. 50 MP portrait: 0.25 → 71 ms 12.6 MB; 0.5 → 120 ms 50.3 MB. Steps above fit size use the 1-image cache and aren't prefetched |
| 2 (before/after) | de75b16 → b3bc7d6 | Apple M1 Pro, 32 GB / macOS 27.0.1 | App, `browse/`, 39 × → at 300 ms (accessibility key events), `Navigate` from `sudo log show --signpost` | Navigate p50 23.5 → 25.0 ms, p95 41.0 → 36.0 ms, max 173 → 170 ms (n = 40 each): no measurable gain. All four signposts appear (Scan 3 ms for 40 files, Decode, Navigate, FirstImage) |
| 7 (experiment) | task-7 | Apple M1 Pro, 32 GB / macOS 27.0.1 | `featherview-bench decode <dir> --screen 3024x1964 --runs 10`, step vs. a temporary exact switch (`fitNeededSize` as `maxPixelSize`), load average 3–4.6 | Exact is smaller everywhere: 12 MP PNG 48.0 → 20.6 MB, landscape HEIC 48.8 → 20.6 MB, portrait HEIC 12.2 → 11.6 MB. Speed, median step → exact: landscape HEIC 163–167 → 125–142 ms, portrait HEIC 120–125 → 120–126 ms, PNG 220–222 → 242–243 ms; PNG again at 20 runs × 3: 219.1–219.7 → 241.6–260.0 ms, 10.0–18 % slower. PNG fails the "at most 10 % slower" rule, so ImageIO types stay at the halving step. HEIC alone would pass (faster and ~60 % fewer bytes for landscape): a candidate for the maintainer, not done here |
| 7 (after) | task-7 | Apple M1 Pro, 32 GB / macOS 27.0.1 | `featherview-bench decode <dir> --baseline build/bench/after-task3.json`, 3 runs | Run 3: no median more than 10 % slower. Runs 1–2 flagged only 12 MP landscape HEIC (176.9 → 198–240 ms, load average 5–6), an ImageIO path this task doesn't change. Own formats (QOI etc.) aren't in the corpus; the unit test shows a 4000×3000 QOI now decodes at 2619×1964 instead of 4000×3000 |
| 8 (solo) | task-8 | Apple M1 Pro, 10 cores, 32 GB / macOS 27.0.1 | `featherview-bench decode <dir>/solo --screen 3024x1964 --runs 10` (`browse-heic/0001`, `0002`, `browse-50mp/0001`, `0002`), load average ~4–5 | Fit decode median: HEIC landscape 174.8 ms (full 4032×3024), portrait 131.7 ms (½, 1512×2016); 50 MP landscape 111.9 ms (½, 4344×2896), portrait 63.8 ms (¼, 1448×2172) |
| 8 (gate) | task-8 | Apple M1 Pro, 10 cores, 32 GB / macOS 27.0.1 | `featherview-bench browse <dir>/browse-heic` and `browse-50mp`, `--interval-ms 300` and `30`, 1 warm-up + 3 runs each, load average 2–4 | 300 ms: no superseded steps; HEIC 38 of 40 from cache, not cached 252–260 ms (step 1, cold start with 4 prefetches beside it) and 59–73 ms (step 2); 50 MP 19 of 20 from cache, not cached 133–148 ms (step 1). 30 ms: nothing shown until the key is let go (HEIC 39 of 40, 50 MP 19 of 20 superseded, unlike `browse/` where every other image came from cache); the last image (portrait) took HEIC 238/258/264 ms, median 258 ms = **2.0× solo** (131.7); 50 MP 90/86/90 ms, median 89.6 ms = 1.4× solo (63.8). Peak cache 280 MB (HEIC) / 251 MB (50 MP) decoded, footprint up to 570 MB. **Verdict: over 1.5× on HEIC, so stale work delays the current image and Task 6's scheduling part is due.** No Mac with fewer cores was at hand |
| 8 (gate, alone) | e2c97e6 | Apple M1 Pro, 10 cores, 32 GB / macOS 27.0.1 | Same as "8 (solo)" and "8 (gate)", nothing else building, load average 1.9–3.0 | Solo fit decode median: HEIC portrait 130.5 ms, 50 MP portrait 67.9 ms. 30 ms, last image after 1 warm-up: HEIC 242/258/223 ms, median 242 ms = **1.9× solo**; 50 MP 88/83/83 ms, median 83 ms = 1.2×. 300 ms: no superseded steps; HEIC not cached 247–255 ms (step 1, cold) and 48–58 ms (step 2); 50 MP 140–145 ms (step 1). Confirms the verdict: HEIC over 1.5×, Task 6's scheduling part is due |
| 9 | 6205597 | Apple M1 Pro, 10 cores, 32 GB / macOS 27.0.1 | App, release, `browse/`, 39 × → at 300 ms (System Events key events), `Navigate` from `sudo log show --signpost`, 3 runs, step 0 (the open) left out, load average 4–6 | Prefetched next: p50 19.0 ms, p95 25.3 ms, max 28.3 ms (n = 117). Not prefetched (fresh launch, one jump, 5 runs each): Home to a 12 MP landscape 107 ms median (max 113), End to a portrait 61 ms (max 64). Both within budget |
| 9 (outlier) | b3bc7d6, cff4e9a, f98ea83, 6205597 | Apple M1 Pro, 10 cores, 32 GB / macOS 27.0.1 | Same run per build | The 165–178 ms max of row "2" is step 0, the open itself, not a next/previous step: b3bc7d6 152–178 ms (3 of 3 runs), cff4e9a 152 ms, f98ea83 27–28 ms, main 24 ms. Cause: the early toolbar build before the first image, fixed by f98ea83 (issue #2). Time Profiler under `xctrace` records no signposts without admin ("log archive is corrupt"), so timings come from `log show`; no fix needed in this plan |

Memory baseline for Task 6 is "peak cache … MB decoded" (`bytesPerRow × height`, what the byte budget counts); the footprint misses purgeable decoded images and is only a side number.
