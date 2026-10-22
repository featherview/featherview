# Milestone 9: Animation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. In this repo, code tasks run with the `plan-wave` workflow; tasks marked "main session" need the screen and run in the main session after the maintainer's go.

**Goal:** Animated GIF, PNG (APNG), WebP, HEIC sequences and Windows animated cursors (ANI) play in
the viewer in a loop with the file's delays; the first frame shows as fast as a still image.

**Architecture:** Core gets three small pieces: `Animation` (frame count and delays read from the
file's properties, nil for stills), `FrameSource` (decodes frame *n* at the viewer's decode target
from one kept `CGImageSource`, so ImageIO composites frames in order) and `Playback` (which frame,
playing or paused, stepping; pure). The app adds an `AnimationPlayer` that, once the first frame is
on screen, decodes the following frames off the main thread and puts each straight into the
canvas's layer at its due time, without a SwiftUI update per frame. Frame 0 keeps coming from the
existing cache path, so launch and browsing budgets are untouched. Batch, Save As and ⌘C keep
using the first frame (they already decode index 0).

**Tech Stack:** Swift 6, ImageIO, SwiftUI + AppKit (macOS 14+), Swift Testing, libwebp's
`WebPAnimEncoder` (already compiled in) for a test fixture only.

**Spec:** `docs/spec.md` "Animation" (says the details are decided in this plan; Task 6 writes them
into the spec), `docs/parity.md` "Animation". Rules: `AGENTS.md`.

## Decisions (the spec leaves these to the plan)

1. **Plays on open, loops forever**, whatever loop count the file asks for (the reference viewer
   does the same; spec says "in a loop"). Each newly shown file starts at frame 1, playing; pause is
   not remembered across files.
2. **Delays:** each frame's *unclamped* delay (ImageIO's clamped value turns 40 ms into 100 ms for
   HEIC sequences and 50 ms for APNG), then the browsers' rule: 10 ms or less counts as 100 ms.
   ANI: the `rate` chunk per step, else the header's rate, in jiffies (1/60 s), same rule.
3. **G** pauses and plays (the reference viewer's key; a single key, allowed). Menu
   Image › "Pause Animation  (G)" / "Play Animation  (G)", disabled for stills.
4. **⌥→ / ⌥←** step one frame on an animation (the keys pages use; there are no pages in an
   animated file), pausing playback; nothing past either end, as pages. The page menu items and
   toolbar buttons serve both: titles "Next Frame  (⌥→)" / "Previous Frame  (⌥←)" and tooltips
   "Next frame (⌥→)" / "Previous frame (⌥←)" while an animation shows.
5. **Status bar:** "6 frames" while playing, "frame 3 / 6" while paused. The title doesn't change
   (it would flicker); the full-screen overlay doesn't either.
6. **The system's Accessibility › Display › "Play animated images"** (`AXAnimatedImagesEnabled`,
   macOS 14) off: animations open paused on frame 1; G still plays. Followed live
   (`AXAnimatedImagesEnabledDidChangeNotification`). No app setting of its own.
7. **Frames decode at the image's decode target** (fit, or the zoom's halving step); a zoom change
   re-targets the frames, keeping the frame index. Frames are decoded in order by one serial
   `FrameSource` at `.utility` priority, outside `DecodeQueue` and both caches (frame 0 stays in the
   cache as today).
8. **Memory:** all frames kept when `frameBytes × count ≤ 64 MiB`; otherwise only the frame shown and
   the next two. Everything is dropped when the file is left.
9. **Late frames are never skipped:** a frame not decoded at its due time shows as soon as it is,
   and its delay counts from then. Playback stops while the window is occluded or minimized and
   goes on from the same frame when it's visible again.
10. **Which files:** any ImageIO file with more than one frame whose type dictionary is
    `{GIF}`, `{PNG}`, `{WebP}`, `{HEICS}` or `{AVIS}` (AVIF sequences come free), and ANI. A
    multi-image HEIC without `{HEICS}` and a multi-page TIFF are not animations. `.apng` files are
    listed and read as PNG (macOS has no type for the extension), like `.jfif` as JPEG.

## Spike facts (macOS 27, own test files; don't re-measure)

- `CGImageSourceCreateThumbnailAtIndex(source, n, …)` returns frame *n* composited (a GIF whose frames
  are deltas gives the full picture). Sequential decodes from one source: 0.8 ms per frame (400×300),
  26 ms (1600×1200 at 800 px). Frame 59 from a fresh source: 93 ms — so keep one source and go in order.
- Top-level properties hold `FrameInfo` arrays (`kCGImagePropertyGIFFrameInfoArray`, `…APNG…`,
  `…WebP…`, `…HEICS…`), but APNG's and HEICS's entries lack `UnclampedDelayTime`; per-frame
  properties (`CGImageSourceCopyPropertiesAtIndex`) have it for every type.
- Clamped vs unclamped: GIF 40 ms → 40, 10 ms → 100; APNG 40 → 50; HEICS 40 → 100; WebP 40 → 40.
- ImageIO writes GIF, APNG (PNG with `kCGImagePropertyAPNGDelayTime`) and HEICS (`public.heics`,
  `kCGImagePropertyHEICSDelayTime`); a sequence saved as `.heic` reports type `public.heics`, which
  conforms to `public.heif-standard`, not `.heic`, so `OrientationRotator` refuses it (no frames lost).
- `UTType(filenameExtension: "apng")` is a dynamic type ImageIO doesn't list.

## Global Constraints

- macOS 14.0 minimum; Swift 6 strict concurrency; no new dependency.
- Performance budgets in `AGENTS.md` hold: first frame as fast as a still image; prefetched swap
  ≈ 20 ms; memory bounded (Decision 8).
- Colours, durations only from `Theme.swift`; leading/trailing, never left/right.
- Every user-facing string translatable, whole sentences with placeholders; new strings get all 30
  languages (`scripts/strings.sh`, then the shared steps in
  `docs/superpowers/plans/2026-10-18-milestone-6-languages.md` "Translation tasks (5–10)").
- Test images come from `Fixtures`, never committed binaries.
- Conventional commits, no AI attribution, no dates in docs or comments; `shortcut:` comments as
  `shortcut: <limit>, <when to upgrade>`.

## Review Focus

- A 25 fps file (40 ms frames) in every format must play at 40 ms, not 100: pinned in Task 1
  (`unclampedDelaysForEveryFormat`).
- Holding → through a folder of animations: no frame of the file just left may land on the next
  one's canvas, and no decodes pile up. Pinned in Task 5 (`player stop` is synchronous and the
  frame callback checks the URL), checked on screen in Task 6.
- A huge animation (60 frames of 1600×1200): memory stays under the 64 MiB frame budget plus the
  cache; the UI never stalls. Pinned in Task 3 (`FrameStore` tests), measured in Task 6.
- A truncated GIF (frames cut off): plays the frames that decode, then loops; never an error over
  the first frame that showed. Pinned in Task 4 (`truncatedAnimationStopsAtLastGoodFrame`).
- Stepping ⌥→ at the last frame and then G: playback goes on from the last frame to frame 1.
  Pinned in Task 3 (`playAfterStepAtEndWraps`).

---

## Wave plan

| Wave | Tasks | Why |
|---|---|---|
| A | 1, 3, 4 | independent Core pieces |
| B | 2, 5 | ANI frames (uses 1's `OwnFormat.delays`), the app (uses 1, 3, 4) |
| C | 6 (main session) | screen check, measurements, spec/roadmap/parity |

---

### Task 1: `Animation` — which files animate, and their delays

**Files:**
- Create: `Sources/FeatherviewCore/Imaging/Animation.swift`
- Modify: `Sources/FeatherviewCore/Formats/OwnDecoders.swift` (`OwnFormat.delays`),
  `Sources/FeatherviewCore/Imaging/ImageFormats.swift` (`.apng` alias, `mayAnimate`),
  `Sources/FeatherviewCore/Batch/BatchConverter.swift:146` (`"apng": "png"` in the extension map),
  `Resources/Info.plist` (an imported `.apng` type conforming to `public.png`, like the `.jfif` one at
  line 512, plus its document type)
- Test: `Tests/FeatherviewCoreTests/Imaging/AnimationTests.swift`, `Tests/FeatherviewCoreTests/Fixtures.swift`

**Interfaces:**
- Produces:
  - `public struct Animation: Equatable, Sendable { public let delays: [Duration]; public var frameCount: Int { delays.count } }`
  - `public static func Animation.read(_ url: URL) -> Animation?` — nil for a still, a single frame,
    an unreadable file, a multi-page TIFF or a HEIC collection without `{HEICS}`.
  - `static func Animation.delay(seconds: Double?) -> Duration` — Decision 2's rule; nil or ≤ 0.01 → 100 ms.
  - `OwnFormat.delays: (@Sendable (Data) -> [Double]?)?` (seconds per frame; default nil), a new
    `init` parameter with default `nil`. `Animation.read` uses it for own formats.
  - `public static func ImageFormats.mayAnimate(_ url: URL) -> Bool` — by extension: gif, png, apng,
    webp, heic, heics, heif, avif, and own formats with `delays != nil`. Cheap gate so stills never
    pay for a property read.
  - Fixtures: `writeAnimatedGIF(to:delays:width:height:)`, `writeAPNG(to:delays:…)`,
    `writeHEICS(to:delays:…)`, `writeAnimatedWebP(to:delays:…)` (via `WebPAnimEncoder`; add
    `.product(name: "libwebp", package: "libwebp-Xcode")` to the test target if `import libwebp`
    doesn't resolve). Each frame a solid colour (frame *n*: red = 40·n) so tests can tell frames apart.

- [ ] **Step 1: Write the failing tests** in `AnimationTests`:
  - `unclampedDelaysForEveryFormat`: GIF, APNG, HEICS, WebP each with delays `[0.04, 0.04, 0.5]`
    → `delays == [.milliseconds(40), .milliseconds(40), .milliseconds(500)]`.
  - `tinyDelaysCountAsHundredMilliseconds`: GIF with `[0, 0.01, 0.02]` → `[100, 100, 20]` ms.
  - `stillsAreNotAnimations`: a JPEG, a one-frame GIF, a 3-page TIFF (`writeMultiPageTIFF`), a PNG → nil.
  - `apngExtensionReadsAsPNG`: the APNG fixture renamed `.apng` → `ImageFormats.isDecodable` true,
    `Animation.read` non-nil, `ImageDecoder.decode` works.
  - `mayAnimateByExtension`: true for `.gif .apng .heics .webp .ani`, false for `.jpg .tif .qoi`.
  - `truncatedGIFDoesNotCrash`: the GIF fixture cut to 70 % of its bytes → `read` returns (nil or an
    `Animation` with `frameCount == CGImageSourceGetCount`), no trap.
- [ ] **Step 2: Run** `swift test --filter AnimationTests` → FAIL (no `Animation`).
- [ ] **Step 3: Implement.** Read top-level properties once; for the type dictionary found, take
  `UnclampedDelayTime` from its `FrameInfo` array when every entry has one, else per-frame
  properties' `UnclampedDelayTime`, else `DelayTime`. Count must equal `CGImageSourceGetCount`.
- [ ] **Step 4: Run** `swift test --filter "AnimationTests|BatchConverterTests|FolderScannerTests"` → PASS;
  `plutil -lint Resources/Info.plist` → OK.
- [ ] **Step 5: Commit** `feat: read which images animate and their frame delays`

---

### Task 2: ANI frames and rates

**Files:**
- Modify: `Sources/FeatherviewCore/Formats/ANIDecoder.swift`
- Test: `Tests/FeatherviewCoreTests/Formats/ANIDecoderTests.swift`

**Interfaces:**
- Consumes: `OwnFormat.delays` (Task 1).
- Produces: `ANIDecoder.format` with `delays` set; `decode(data, n, _)` and `size(data, n)` give
  step *n* of the animation (the `seq ` order when present, else frame order), largest image of that
  frame's ICO/CUR. `pageCount` stays 1 (frames aren't pages). Step 0 is today's first frame.

The header (`anih`, after its size field): frames, steps, width, height, bit count, planes,
rate (jiffies), flags. `seq ` is one u32 frame index per step; `rate` one u32 jiffies per step.

Real files (Windows 11's `C:\Windows\Cursors\aero_busy.ani` and `aero_working.ani`, read in the VM,
not copied): `anih` = 36, 18 frames, 18 steps, 0, 0, 32, 1, rate 3, flags 1; no `seq `, no `rate`
chunk; each frame a CUR with three images (64, 48, 32 px). So the common case is header rate only:
3 jiffies = 50 ms per frame, 18 frames in order.

- [ ] **Step 1: Write the failing tests** (extend the existing `ani(...)` builder with `rates:`):
  `stepsFollowSequence` (3 frames, `seq ` = [2, 0, 2] → step 0 and 2 decode frame 2's colour, step 1 frame 0's);
  `ratesPerStep` (`rate` = [6, 30, 6] → `delays == [0.1, 0.5, 0.1]`); `headerRateWithoutRateChunk`
  (header rate 10, no `rate` → every delay 1/6 s); `zeroRateIsHundredMilliseconds` (header rate 0 →
  `Animation.read` gives 100 ms); `outOfRangeStepIsCorrupt` (`seq ` naming frame 9 of 3 → decode of that step throws,
  step 0 still decodes); `busyCursorShape` (built like the real files: 18 CUR frames of 64/48/32 px,
header rate 3, no `seq `/`rate` → `delays` 18 × 0.05 s, each step decodes 64 × 64); `firstFrameUnchanged`
(existing tests keep passing).
- [ ] **Step 2: Run** `swift test --filter ANIDecoderTests` → FAIL.
- [ ] **Step 3: Implement.** Parse once into `(frames, steps, rates)`; keep the existing errors for raw-bitmap frames.
- [ ] **Step 4: Run** `swift test --filter "ANIDecoderTests|AnimationTests|QuickLookSupportTests"` → PASS.
- [ ] **Step 5: Commit** `feat: animated cursors give every frame and their rates`

---

### Task 3: `Playback`, `FrameStore` and the status bar field

**Files:**
- Create: `Sources/FeatherviewCore/Viewer/Playback.swift`
- Modify: `Sources/FeatherviewCore/Viewer/StatusLine.swift`
- Test: `Tests/FeatherviewCoreTests/Viewer/PlaybackTests.swift`, `StatusLineTests.swift`

**Interfaces:**
- Produces:
  - `public struct Playback: Equatable, Sendable` — `init(frameCount: Int, playing: Bool)`;
    `frame: Int` (0-based), `isPlaying: Bool`; `mutating func advance()` (next frame, last → 0);
    `mutating func togglePlaying()`; `@discardableResult mutating func step(forward: Bool) -> Bool`
    (pauses; false and unchanged at either end).
  - `public enum FrameStore` — `static let budget = 64 << 20`;
    `static func keepsAll(frameBytes: Int, count: Int) -> Bool`;
    `static func wanted(shown: Int, count: Int, keepsAll: Bool) -> [Int]` (all indices from `shown`
    on, wrapping, when `keepsAll`; else `shown` and the next two, wrapping, no duplicates).
  - `StatusLine.make(…, frame: Int?, frameCount: Int)` — two new parameters after `pageCount`, defaults
    `nil` and `1`. `frameCount > 1`: field `"\(frameCount) frames"` (plural variations in the catalog)
    when `frame == nil`, `"frame \(frame + 1) / \(frameCount)"` otherwise, in the place the page field uses.

- [ ] **Step 1: Write the failing tests:** `advanceWrapsToFirstFrame`; `stepPausesAndStopsAtEnds`
  (playing at frame 0, `step(forward: false)` → false, frame 0, paused: stepping always pauses,
  even when it can't move; at the last frame `step(forward: true)` → false); `playAfterStepAtEndWraps` (step to last, toggle, advance → 0);
  `togglePlayingKeepsFrame`; `keepsAllUnderBudget` (1 MB × 64 → true; 30 MB × 3 → false);
  `wantedWindowWraps` (shown 5 of 6, not all → [5, 0, 1]; count 2 → [1, 0]); `wantedAllStartsAtShown`;
  `StatusLineTests.framesWhilePlaying` ("6 frames"), `frameWhilePaused` ("frame 3 / 6"),
  `stillHasNoFrameField`.
- [ ] **Step 2: Run** `swift test --filter "PlaybackTests|StatusLineTests"` → FAIL.
- [ ] **Step 3: Implement**, then `scripts/strings.sh` and the two new catalog keys in all 30 languages
  (shared translation steps, see Global Constraints).
- [ ] **Step 4: Run** `swift test --filter "PlaybackTests|StatusLineTests|StringCatalogTests"` → PASS.
- [ ] **Step 5: Commit** `feat: playback state, frame memory budget and the frames field`

---

### Task 4: `FrameSource` — frames at the decode target, in order

**Files:**
- Create: `Sources/FeatherviewCore/Imaging/FrameSource.swift`
- Modify: `Sources/FeatherviewCore/Imaging/ImageDecoder.swift` (expose the thumbnail options and the
  8-bit/colour-space finishing that `decode` applies, so both share them; no behaviour change)
- Test: `Tests/FeatherviewCoreTests/Imaging/FrameSourceTests.swift`

**Interfaces:**
- Consumes: Task 1's fixtures (`writeAnimatedGIF`) — if Task 1 isn't merged yet, write a local
  GIF helper in the test file and drop it at merge.
- Produces: `public actor FrameSource` — `init(url: URL, target: DecodeTarget, colorSpace: CGColorSpace?) throws`
  (opens the file once: a `CGImageSource`, or the mapped `Data` of an own format);
  `func frame(_ index: Int) throws -> CGImage` — same size, orientation, 8 bits and colour space as
  `ImageDecoder.decode(url, halvingSteps: true, fitting:/step:, page: 0, colorSpace:)` gives frame 0
  (no HDR: animations are SDR); own formats go through `OwnFormat.decode(data, index, limit)` and
  `ImageDecoder.scaled`.

- [ ] **Step 1: Write the failing tests:** `frameZeroMatchesStillDecode` (GIF 400×300, `.fit([800×600])`:
  same width/height/bitsPerComponent as `ImageDecoder.decode`); `framesAreComposited` (GIF whose frame 2
  only covers a 10×10 corner, written with ImageIO's `kCGImagePropertyGIFDictionary` per frame:
  pixel outside the corner in frame 2 equals frame 1's); `stepTargetHalves` (`.step(1)` → half size);
  `truncatedAnimationStopsAtLastGoodFrame` (GIF cut after frame 2's data: frames 0–1 decode, a later
  frame throws `DecodeError.unreadable`); `ownFormatFrames` (an `OwnFormat` registered in the test
  with `delays` and a decode that returns a colour per index → `frame(1)` is colour 1).
- [ ] **Step 2: Run** `swift test --filter FrameSourceTests` → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `swift test --filter "FrameSourceTests|ImageDecoderTests|ImageCacheTests"` → PASS.
- [ ] **Step 5: Commit** `feat: decode animation frames in order at the viewer's size`

---

### Task 5: The player in the viewer

**Files:**
- Create: `Sources/Featherview/Viewer/AnimationPlayer.swift`
- Modify: `Sources/Featherview/Viewer/ViewerModel.swift` (start/stop/retarget the player, `nextPage`/
  `previousPage` step frames on an animation, `toggleAnimation()`, availability),
  `ImageCanvas.swift` (`ImageLayerView.showFrame(_:)`; `updateNSView` shows `player.current ?? image`),
  `ViewerView.swift` (G key, Image menu items, page items' titles), `ViewerToolbar.swift` (page buttons'
  tooltips), `StatusBar.swift` (frame field), `Sources/FeatherviewCore/Viewer/ViewerKey.swift`
  (`case toggleAnimation` on "g")
- Test: `Tests/FeatherviewCoreTests/Viewer/ViewerKeyTests.swift` (`gTogglesAnimation`; Shift+G nothing)

**Interfaces:**
- Consumes: `Animation.read`, `ImageFormats.mayAnimate` (1), `Playback`, `FrameStore`,
  `StatusLine.make(…frame:frameCount:)` (3), `FrameSource` (4).
- Produces: `@MainActor @Observable final class AnimationPlayer` — observed: `frameCount: Int`,
  `pausedFrame: Int?` (nil while playing; only these change on pause/step, never per frame);
  `@ObservationIgnored var current: CGImage?`; `var onFrame: (CGImage) -> Void`;
  `func start(url: URL, animation: Animation, target: DecodeTarget, first: CGImage, playing: Bool)`,
  `func stop()` (synchronous: cancels its task, drops frames, `current = nil`), `func retarget(_:)`,
  `func togglePlaying()`, `func step(forward: Bool) -> Bool`, `func setVisible(_ visible: Bool)`.

Rules:
- The model starts the player after the image for `url` (page 0) is shown, only if
  `ImageFormats.mayAnimate(url)` and `Animation.read` (off the main thread) is non-nil and
  `list.current == url` still. `show()` calls `player.stop()` first thing, before anything else
  changes. `playing` = `AXAnimatedImagesEnabled()` (Decision 6).
- Timing: one task; sleeps until the shown frame's delay has passed (`ContinuousClock`), awaits the next
  frame from `FrameSource` (decoding ahead per `FrameStore.wanted`), checks it's still the same URL and
  generation, then calls `onFrame`. The canvas sets `imageLayer.contents` in a no-action transaction,
  not touching `onCommit`/`Navigate`.
- Zoom change: `retarget` with the new target (same frame index). Rotation preview (`pendingTurns`)
  and leaving fades apply to frames as to stills (the layer is the same).
- `setVisible` from the window's `occlusionState` and miniaturize notifications (Decision 9).
- `availability.hasPages` also true for an animation; menu titles and tooltips per Decision 4.
- `copyImage`, Save As and rotate keep using the file (frame 0), not `current`.

- [ ] **Step 1: Write the failing `ViewerKeyTests`** → run `swift test --filter ViewerKeyTests` → FAIL → add the case → PASS.
- [ ] **Step 2: Implement** the player and wiring; `swift build`; `scripts/bundle.sh debug`.
- [ ] **Step 3:** `scripts/strings.sh`; the new menu titles, tooltips and Pause/Play items in all 30
  languages; `swift test` → all PASS.
- [ ] **Step 4: Commit** `feat: animations play in the viewer; G pauses, ⌥→ / ⌥← step frames`

---

### Task 6: Screen check, budgets, docs (main session, screen)

Needs the maintainer's go (screen bursts). Sample folder: Task 1's fixtures written by a small
`featherview-bench corpus`-style script into the scratchpad, plus 20 12 MP JPEGs, a 60-frame
1600×1200 GIF, and `aero_busy.ani` from the VM's `C:\Windows\Cursors` (556 KB: copied over in
base64 pieces of ≤ 64 KB through `vmpal_exec`, kept in the scratchpad, never committed).

- [ ] **Step 1: Check by hand** (release build): each format plays at its pace (a 40 ms GIF visibly
  smooth; `aero_busy.ani` turns like the Windows busy cursor, 18 frames at 50 ms); G pauses / plays, the status bar switches "6 frames" ↔ "frame 3 / 6"; ⌥→ / ⌥← step and stop at
  the ends; menu and toolbar titles; held → through a folder of animations and JPEGs: no stray frames,
  swap budget (`Navigate` p50/p95 in the log) unchanged; zoom in on a playing GIF re-targets; full
  screen plays; Accessibility "Play animated images" off → opens paused, G plays; window minimized →
  CPU drops to idle (Activity Monitor), restored → plays on.
- [ ] **Step 2: Measure:** launch with a GIF after ⌘Q (< 410 ms budget, same as a JPEG of its size);
  memory while the 60-frame big GIF plays (frame budget + cache); CPU while a small GIF loops.
- [ ] **Step 3: Docs:** spec "Animation" gets Decisions 1–10 in spec wording (drop "(v2)", remove
  "first frame; animation in v2" from "Viewer" and ANI's "(playing it: …)"); `docs/parity.md` rows → `v2`;
  roadmap: a row `| 9 | Animation | docs/superpowers/plans/2026-10-22-milestone-9-animation.md | done |`,
  the "Animation (v2)" section moved under it; README features line; `AGENTS.md`: drop "animation
  playback (v2: spec "Animation")" from "Out of scope for v1".
- [ ] **Step 4: Commit** `docs: animation done after manual QA`
