# Featherview — Performance Plan (measure first)

> Not a milestone in `docs/roadmap.md`: fixes to the viewer's speed and memory found in a code review,
> in the order the maintainer set. Don't add features here.

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

| Task | Needs |
|---|---|
| 1 | — |
| 2 | — |
| 3 | 1 |
| 4 | 2 (same file, `ViewerView.swift`) |
| 5 | 3, 4 |
| 6 | 3, and a recorded `browse` baseline |

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
- peak memory footprint (`Footprint.swift`: `task_info(TASK_VM_INFO)` → `phys_footprint`, sampled
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

- [ ] Write the corpus generator; run it; check sizes and that `12mp-portrait-exif6.jpg` shows upright in Preview
- [ ] Write `decode` mode with `fitDecode` mirroring today's call; run it on the maintainer's Mac
- [ ] Write `browse` mode and `Footprint.swift`; run at 300 ms and 30 ms
- [ ] Add the signposts; `swift build`, `swift test` pass
- [ ] Check in Instruments (Points of Interest) that `Navigate`, `Decode` and `Scan` appear while browsing the corpus
- [ ] Record all numbers in "Measurements" (machine, macOS, commit)
- [ ] Commit: `feat: featherview-bench and signposts for decode, scan and navigation`

### Task 2: The menu stops re-reading the image list

`ViewerView.swift:394`, in `ViewerCommands`, Save As reads `model?.list.current` and
`model?.list.isHolding`. That makes `ViewerCommands` depend on `list`, so every arrow key
re-evaluates the commands and SwiftUI rebuilds the main menu on the main thread. All other items read
`availability`, which `ViewerModel.updateAvailability()` sets only when a value flips.
`availability.canChangeFile` is exactly `list.current != nil && !list.isHolding`.

**Files:** Modify `Sources/Featherview/ViewerView.swift` (one line).

- [ ] Replace with `.disabled(model?.availability.canChangeFile != true)`
- [ ] By hand: Save As is disabled with no image, enabled with one, disabled on a held (trashed, "show the next image" off) image
- [ ] If Task 1 is merged: compare `Navigate` p50 before/after in Instruments while browsing `browse/` at 300 ms (expect a small gain; record it, even if zero)
- [ ] Commit: `fix: the menu no longer rebuilds on every image`

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

- [ ] Failing tests, then `fitDecodeSize`, then the decode parameter, then the cache key, then the viewer
- [ ] Update `fitDecode` in the bench; run `decode` before (Task 1's numbers) and after; record both
- [ ] By hand: a portrait photo fills the window height sharply at fit; full screen on a 5K display stays sharp
- [ ] Update `AGENTS.md` "Performance budgets" memory line: "decoded to fit the screen per axis"
- [ ] Commit: `fix: fit decodes portrait images at the size the screen shows`

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

- [ ] Failing tests, `ZoomSteps.drawSize`, view uses it
- [ ] By hand with `50mp-landscape.jpg`: + from fit grows the image a little and it sharpens when the decode lands; no shrink, no jump; the point under the window centre stays put
- [ ] Commit: `fix: zooming from fit no longer shows the image at half size first`

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

- [ ] Interfaces + failing tests (step choice per factor, no re-decode within a step)
- [ ] Viewer: target per factor; prefetch ±1 while zoomed
- [ ] Bench before/after; by hand: browse 50 MP images at 50 % zoom, next image shows without waiting for a full decode
- [ ] Commit: `perf: zoom decodes at the step it shows and prefetches while zoomed`

### Task 6: Decode scheduling and a byte budget, together

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
| 1 (baseline) | | | `featherview-bench decode <dir>` | |
| 1 (baseline) | | | `featherview-bench browse <dir>/browse --interval-ms 300` | |
| 1 (baseline) | | | `featherview-bench browse <dir>/browse --interval-ms 30` | |
