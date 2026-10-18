# Featherview v1 — Milestone 4 Implementation Plan (Batch complete)

> **Milestone 4** in `docs/roadmap.md`. Builds on milestone 1's batch (`BatchJob`, `BatchPlanner`,
> `BatchConverter`, `RenamePattern`) and milestone 3's output formats (`OutputFormat`,
> `FormatOptions`, `ImageEncoder`, `ImageSaver`, `FormatOptionsView`, `FormatSettings`). Don't add
> anything from other milestones here (languages are milestone 6).

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. In this repo, run it wave by wave with the `plan-wave` workflow.

**Goal:** The batch window does everything spec "Batch window (B, ⌘B)" lists: three modes, a full
input list, rename with `{date}`/`{folder}` and a counter that advances only on success, every
per-image operation in spec order, presets, the safety options, Stop / Pause / Copy Log, HDR kept
for HEIC/AVIF output, in the three-column window the maintainer accepted.

**Architecture:** All settings live in one `Codable` value, `BatchSettings` (Task 1), which the
window edits, presets store, and the converter reads. Every per-image operation is a pure function
`CIImage → CIImage` in `FeatherviewCore` (Tasks 2–5); `ImagePipeline` (Task 8) chains them in spec
order and renders once at the end through one shared `CIContext`, so a 12 MP image is processed in
tiles without an extra full-size copy per step. Reducing colour depth is the only step on raw pixels
(after the render). The live preview in the window runs the same pipeline on a small decode with a
`scale` factor, so pixel-valued settings (crop offsets, border widths) look right at preview size.
The converter (Task 8) processes files in parallel into memory, then commits them in list order: a
file's output name (and its rename counter) is assigned only when every earlier file has finished,
so numbers follow the list and skip failures without gaps. HDR output (Task 9) swaps the render for
an extended-range one when the input has HDR data and the output is HEIC or AVIF.

**Tech Stack:** Swift 6 (strict concurrency), SwiftPM, Core Image (`CIFilter` built-ins, `CIContext`),
Core Text + Core Graphics (text overlay), ImageIO, SwiftUI + AppKit (window, font panel, open/save
panels), Swift Testing.

**Spec:** `docs/spec.md` "Batch window (B, ⌘B)" (all of it: Window, Mode and inputs, Output,
Per-image operations, Safety and options, Running) and "Formats" (HDR output); `docs/parity.md`
"Batch". Mockups the maintainer accepted: https://claude.ai/artifact/U715UXnB6dky8ZCaeSmcoA
(private; the spec's "Window" section says the same in words). Rules, budgets and commands:
`AGENTS.md`. Read the spec section and AGENTS.md first.

**Checked while planning (facts, not committed code):**

- Core Image's coordinate origin is the bottom-left corner: an image "top" is high `y`. Every anchor
  computation (crop, canvas, text, watermark) must flip: for an image of height `H`, a rectangle
  `h` high at distance `d` from the image's top has `y = H − d − h`.
- A `CIImage` from a `CGImage` has extent origin (0, 0); after crop or transforms the extent may move.
  Every step returns an image whose extent origin is (0, 0) again
  (`image.transformed(by: .init(translationX: -extent.minX, y: -extent.minY))`), so the next step can
  rely on it.
- Blur-like filters (`CIGaussianBlur`, `CIUnsharpMask`, `CINoiseReduction`) read outside the extent
  and darken the edges unless the input is `clampedToExtent()` first and the result cropped back to
  the original extent.
- `CIContext` is thread-safe and expensive to create: one `static let` shared by all workers
  (`nonisolated(unsafe)` is not needed: `CIContext` is `Sendable` in the macOS 14 SDK; if the compiler
  disagrees, wrap it in a `final class … : @unchecked Sendable` with a one-line comment why).
- Colour arithmetic must act on the values the user sees (like the reference viewer), so the 8-bit
  render context uses `workingColorSpace = sRGB` (not Core Image's default linear space) and
  `workingFormat = .RGBAh`. HDR uses an extended linear working space (Task 9).
- `MetadataReader.taken(_:)` already parses EXIF `DateTimeOriginal`; Task 7 adds a `Date`-returning
  sibling instead of re-parsing.
- The app isn't sandboxed: a watermark image is stored as a plain path.

## Global Constraints

- macOS 14.0 minimum; Swift 6 language mode, strict concurrency.
- No new dependency: Apple frameworks only (Core Image, Core Text, ImageIO, AppKit/SwiftUI in the app).
- `FeatherviewCore` never imports SwiftUI or AppKit. Text drawing in Core uses Core Text.
- Never lose data (AGENTS.md): outputs are written to a hidden temp file and moved in without
  replacing; "Replace existing files" moves the old file to the Trash first, never deletes it, and
  never replaces any input of the same batch; "Move originals to Trash" only after that file's output
  is written; a failed or stopped file leaves no partial output.
- One bad file never stops the batch; its log line is a short sentence naming the file
  ("Can't open broken.jpg", "Can't write broken.jpg as GIF"), never a raw error.
- No work on the main thread that reads or decodes a file: the preview, thumbnails, folder adds,
  list loading and names preview all run off it, and typing in a field never waits for them.
- User-facing text is translatable: SwiftUI literals, else `String(localized:)`; never build
  sentences by concatenation (use one localized format string with arguments).
- Layout uses leading/trailing, never left/right. Image positions (corners of the picture) are not
  layout: they don't mirror.
- TDD for `FeatherviewCore` (Swift Testing, images from `Fixtures` or built in tests, never committed
  binaries). The app target is checked by hand (Task 12).
- Commit messages: conventional commits, no AI attribution lines, no dates in docs or comments.
- Keep `shortcut:` comments for known limits, in the form `shortcut: <limit>, <when to upgrade>`.

## Review Focus

- Name clashes across a run with parallel workers: two inputs `a.jpg` and `A.png` → `a.jpg`,
  `a 2.jpg`; a file that appears in the output folder while the batch runs is never replaced; an
  output name equal to a later input's path never trashes that input, even with "Replace existing
  files" on. Pinned in Task 7 (`clashesAreCaseInsensitive`, `neverReplacesAnInput`) and Task 8
  (`replaceExistingNeverTouchesInputs`, `fileAppearingDuringRunIsKept`).
- Counter with failures and parallel completion: inputs 1–5 where 2 fails and 4 finishes first →
  names 001, 002, 003, 004 for inputs 1, 3, 4, 5 in that order. Pinned in Task 8
  (`counterFollowsListOrderAndSkipsFailures`, with a convert seam that finishes out of order).
- Stop and Pause while files are in flight: in-flight files finish and are written, nothing new
  starts, the summary counts the rest as not converted; Resume continues with the next file. Pinned
  in Task 8 (`stopFinishesInFlightAndStartsNoMore`, `pauseHoldsThenResumes`).
- Settings that make no image (crop rectangle outside the picture, resize to 0 %, canvas with a
  negative border wider than the image, a 1 × 1 input): a clear per-file error or the original
  size, never a crash or an empty file. Pinned in Tasks 2 and 4 (`cropOutsideImageKeepsImage`,
  `resizeNeverBelowOnePixel`, `negativeBorderLargerThanImageFails`).
- A big batch (1,000 × 24 MP JPEG) keeps memory bounded: at most `workers + workers` encoded
  outputs wait for their turn to commit, and each worker holds one image. Pinned in Task 8
  (`commitWindowIsBounded`).

---

## Wave plan

| Wave | Tasks | Why |
|---|---|---|
| A | 1 | `BatchSettings`, `BatchInput`, presets, the shared render: every later task uses them |
| B | 2, 3, 4, 5, 6, 7 | independent Core pieces, each in its own files |
| C | 8 | pipeline + converter: chains 2–5, uses 6–7 |
| D | 9, 10 | HDR output (Core) and the window shell (app), independent |
| E | 11 | step settings views and live preview (inside the shell from 10) |
| F | 12 | manual QA, docs, roadmap (needs the screen: ask the maintainer first) |

---

### Task 1: BatchSettings, BatchInput, presets and the shared render

**Files:**
- Create: `Sources/FeatherviewCore/BatchSettings.swift`
- Create: `Sources/FeatherviewCore/BatchPresets.swift`
- Create: `Sources/FeatherviewCore/PipelineRender.swift`
- Test: `Tests/FeatherviewCoreTests/BatchSettingsTests.swift`, `Tests/FeatherviewCoreTests/PipelineRenderTests.swift`
- Create: `Tests/FeatherviewCoreTests/PipelineFixtures.swift` (test helpers, used by Tasks 2–5, 8, 9)

**Interfaces:**
- Consumes: `FormatOptions`, `FormatRegistry`, `OutputFormat` (`OutputFormat.swift`), `RGBAImage`.
- Produces (all `public`, all value types `Codable, Equatable, Sendable`; every numeric range below is
  the valid range, values outside are clamped where used, never trusted):
  ```swift
  public enum BatchMode: String, Codable, Sendable, CaseIterable { case convert, rename, convertAndRename }
  /// A position in the picture (not in the UI: it never mirrors).
  public enum ImageAnchor: String, Codable, Sendable, CaseIterable {
      case topLeft, top, topRight, left, center, right, bottomLeft, bottom, bottomRight
  }
  public struct RGBAColor: Codable, Equatable, Sendable {  // sRGB, 0…1
      public var red, green, blue, alpha: Double
      public static let black, white, clear: RGBAColor
      public var cgColor: CGColor { get }
  }
  public struct CropSettings { isOn = false; x = 0; y = 0; width = 0; height = 0  // Int, pixels; 0 = to the edge
                               anchor: ImageAnchor = .topLeft }
  public enum ResizeMode: String, Codable, Sendable, CaseIterable { case widthHeight, longestSide, shortestSide, megapixels, percent }
  public struct ResizeSettings { isOn = false; mode: ResizeMode = .longestSide
                                 width: Int? = nil; height: Int? = nil; side = 1920; megapixels = 12.0
                                 percentWidth = 50.0; percentHeight = 50.0
                                 keepAspect = true; dontEnlarge = true; dontShrink = false; dpi: Int? = nil }
  public enum QuarterTurn: String, Codable, Sendable { case none, left, right }
  public struct OrientationSettings { rotate: QuarterTurn = .none; flipHorizontal = false; flipVertical = false
                                      var isOn: Bool { get } }  // any of the three set
  public struct ColourSettings { isOn = false; greyscale = false; negative = false; autoAdjust = false
                                 brightness = 0 /* −255…255 */; contrast = 0 /* −127…127 */; gamma = 1.0 /* 0.01…6.99 */
                                 saturation = 0 /* −255…255 */; balanceRed = 0; balanceGreen = 0; balanceBlue = 0 /* −255…255 */
                                 sharpen = 0 /* 0…99 */; blur = 0 /* 0…99 */; reduceColours: Int? = nil /* 2…256 */; dither = true }
  public struct FilterSettings { isOn = false; unsharpMask = 0; noiseReduction = 0; sepia = 0 /* 0…100, 0 = off */
                                 colourTemperature = 0 /* −100…100, + = warmer, 0 = off */; autoLevels = false }
  public enum CanvasMethod: String, Codable, Sendable, CaseIterable { case perSide, totalSize, aspectRatio }
  public struct CanvasSettings { isOn = false; autoCropBorders = false; method: CanvasMethod = .perSide
                                 left = 10; right = 10; top = 10; bottom = 10   // Int pixels, may be negative
                                 width = 1920; height = 1080                    // Int pixels, 0 = keep that side
                                 ratioWidth = 1.0; ratioHeight = 1.0; anchor: ImageAnchor = .center; colour: RGBAColor = .black }
  public struct BorderSettings { isOn = false; outerWidth = 10; outerColour: RGBAColor = .white
                                 innerWidth = 0; innerColour: RGBAColor = .black }  // Int pixels; inner 0 = one border
  public enum TextPlacement: String, Codable, Sendable, CaseIterable { case inImage, stripBelow, stripAbove }
  public struct TextSettings { isOn = false; text = "{name}"; fontName = "Helvetica-Bold"  // PostScript name
                               sizePercent = 3.0 /* of the shorter side, 0.5…50 */; colour: RGBAColor = .white
                               position: ImageAnchor = .bottomRight; marginPercent = 2.0 /* 0…25 */
                               placement: TextPlacement = .inImage; opacity = 1.0 /* 0…1 */
                               shadow = true; backgroundBox = false; boxColour = RGBAColor(red: 0, green: 0, blue: 0, alpha: 0.5) }
  public struct WatermarkSettings { isOn = false; path = ""; position: ImageAnchor = .bottomRight
                                    marginPercent = 2.0; widthPercent = 20.0 /* of the output's width, 1…100 */; opacity = 0.33 }
  public struct SafetySettings { replaceExisting = false; trashOriginals = false; keepDates = false; recreateSubfolders = false }
  public struct BatchSettings {
      public var mode: BatchMode = .convert
      public var formatID = "jpg"
      public var options = FormatOptions()
      public var outputFolder = ""          // a path; may contain {folder}
      public var renamePattern = "{name}"
      public var crop = CropSettings(), resize = ResizeSettings(), orientation = OrientationSettings()
      public var colour = ColourSettings(), filters = FilterSettings(), canvas = CanvasSettings()
      public var border = BorderSettings(), text = TextSettings(), watermark = WatermarkSettings()
      public var safety = SafetySettings()
      public init()
      public var format: OutputFormat { get }   // FormatRegistry.format(id:) ?? .jpeg
      /// True when no operation is on: the converter may take the fast path.
      public var hasOperations: Bool { get }
  }
  public struct BatchInput: Hashable, Sendable {
      public let url: URL
      /// The folder the user added (with or without subfolders); nil for files added one by one.
      /// "Recreate subfolders" and `{folder}` use it.
      public let root: URL?
      public init(url: URL, root: URL? = nil)
  }
  public enum BatchPresets {
      public static func names(in defaults: UserDefaults = .standard) -> [String]   // sorted, Finder order
      public static func load(_ name: String, in defaults: UserDefaults = .standard) -> BatchSettings?
      public static func save(_ name: String, _ settings: BatchSettings, in defaults: UserDefaults = .standard)
      public static func delete(_ name: String, in defaults: UserDefaults = .standard)
      /// The window's own settings between launches.
      public static func current(in defaults: UserDefaults = .standard) -> BatchSettings
      public static func saveCurrent(_ settings: BatchSettings, in defaults: UserDefaults = .standard)
  }
  public enum PipelineRender {
      /// 8-bit sRGB, straight alpha, extent origin (0, 0). Throws `EncodeError.failed` for an
      /// empty or infinite extent.
      public static func cgImage(_ image: CIImage) throws -> CGImage
      /// The shared context (sRGB working space, RGBAh), for steps that must measure the image
      /// (auto levels, auto-crop).
      public static let context: CIContext
  }
  ```
  Test helpers (`PipelineFixtures.swift`, internal to the test target):
  `static func solid(_ c: RGBAColor, width: Int, height: Int) -> CIImage`,
  `static func quadrants(width: Int, height: Int) -> CIImage` (top-left red, top-right green,
  bottom-left blue, bottom-right white, in picture terms: top = first rows of `RGBAImage`),
  `static func pixels(_ image: CIImage) throws -> RGBAImage` (through `PipelineRender.cgImage`),
  `static func fromRGBA(_ image: RGBAImage) -> CIImage`.

Facts to pin:

- Decoding must tolerate missing keys: `JSONDecoder().decode(BatchSettings.self, from: "{}")` gives
  `BatchSettings()`, and a preset saved by this version with one key removed loads with that key at
  its default (presets outlive app versions). Write `init(from:)` with `decodeIfPresent` per key for
  `BatchSettings` and every nested struct; an unknown `formatID` falls back to JPEG in `format`.
- Presets are stored as one JSON dictionary `[String: Data]` under the `UserDefaults` key
  `batchPresets`; the current settings under `batchSettings`. A preset that fails to decode is
  skipped (`load` returns nil), never a crash.
- `quadrants` and every test reason in picture terms (row 0 = top). `pixels` returns rows top first
  (`RGBAImage(CGImage)` already does).

- [x] **Step 1: Write the failing tests** — `BatchSettingsTests`: `defaultsMatchTheSpec` (resize keeps
  aspect and doesn't enlarge, nothing on, mode convert, pattern `{name}`), `emptyJSONDecodesToDefaults`,
  `roundTripsEveryField` (set every field to a non-default, encode, decode, equal),
  `missingNestedKeyKeepsDefault`, `unknownFormatFallsBackToJPEG`, `hasOperationsOnlyWhenAStepIsOn`,
  `presetsSaveLoadDeleteAndList` (in a `UserDefaults(suiteName:)` removed afterwards),
  `corruptPresetIsSkipped`. `PipelineRenderTests`: `solidRendersItsColour` (±1 per channel),
  `quadrantsAreTopFirst`, `halfTransparentStaysStraightAlpha` (red at alpha 0.5 → (255, 0, 0, 128) ±1),
  `infiniteExtentThrows`.
- [x] **Step 2: Run them to see them fail.** `swift test --filter "BatchSettingsTests|PipelineRenderTests"`
- [x] **Step 3: Implement** the types, presets and render to the interfaces above.
- [x] **Step 4: Run the tests, then the full suite.** `swift test`
- [x] **Step 5: Commit.** `feat: batch settings, presets and the shared render`

---

### Task 2: Geometry steps — crop, resize, rotate and flip

**Files:**
- Create: `Sources/FeatherviewCore/GeometrySteps.swift`
- Test: `Tests/FeatherviewCoreTests/GeometryStepsTests.swift`

**Interfaces:**
- Consumes (Task 1): `CropSettings`, `ResizeSettings`, `OrientationSettings`, `ImageAnchor`,
  `PipelineFixtures`, `PipelineRender`.
- Produces:
  ```swift
  public enum CropStep {
      /// `scale` multiplies every pixel value (1 for output, < 1 for the preview).
      public static func apply(_ image: CIImage, _ s: CropSettings, scale: Double) -> CIImage
  }
  public enum ResizeStep {
      /// The output size for an image of `size` (the preview passes its own size and `scale`).
      public static func targetSize(for size: CGSize, _ s: ResizeSettings, scale: Double) -> CGSize
      public static func apply(_ image: CIImage, _ s: ResizeSettings, scale: Double) -> CIImage
      /// The largest pixel size a decode may be limited to before the pipeline runs, or nil when
      /// the full image is needed (crop on, or a mode that isn't a plain downscale). Used by Task 8
      /// to keep the old fast path (decode at the target size) for the common "longest side" case.
      public static func decodeLimit(_ settings: BatchSettings, originalSize: CGSize) -> Int?
  }
  public enum OrientationStep {
      public static func apply(_ image: CIImage, _ s: OrientationSettings) -> CIImage
  }
  ```
  Every `apply` returns an image whose extent origin is (0, 0); an `isOn == false` setting returns
  the input unchanged (same object is fine).

Behaviour to pin:

- Crop: `x`/`y` are offsets from the anchor towards the picture's inside (from `topLeft`: right and
  down; from `bottomRight`: left and up; from `center`: the rectangle is centred, then moved by `x`
  right and `y` down; edge anchors centre along their edge). `width`/`height` 0 = up to the far edge.
  The rectangle is clipped to the picture; if nothing is left, the image is returned unchanged
  (`cropOutsideImageKeepsImage`).
- Resize, with `w × h` the input size and all results rounded to the nearest pixel, at least 1:
  - `widthHeight`: only `width` → height follows the aspect (if `keepAspect`) or stays; only
    `height` likewise; both with `keepAspect` → the largest size that fits inside `width × height`;
    both without → exactly that size; neither → unchanged.
  - `longestSide` / `shortestSide`: that side becomes `side`, the other follows the aspect.
  - `megapixels`: factor `sqrt(megapixels × 1_000_000 / (w × h))` on both sides.
  - `percent`: `w × percentWidth / 100`, `h × percentHeight / 100`; with `keepAspect`,
    `percentWidth` for both.
  - Pixel values (`width`, `height`, `side`) are multiplied by `scale`; megapixels by `scale²`;
    percentages aren't.
  - `dontEnlarge`: if the target is wider or taller than the input, keep the input size.
    `dontShrink`: if the target is narrower or shorter, keep it. Both off: always resize.
  - Resample with `CILanczosScaleTransform` (`scale` = target height / h, `aspectRatio` =
    (target width / w) / (target height / h)), then crop to exactly the target size (Lanczos can
    leave a fractional row).
  - `dpi` isn't applied here; the encoder writes it (Task 8).
- Rotate `left` = 90° counter-clockwise, `right` = 90° clockwise, then flip horizontal, then flip
  vertical (`quadrants` pins each: after `right`, top-left is blue).

- [x] **Step 1: Write the failing tests** — crop: `cropFromEachAnchor` (a 10 × 8 `quadrants`, 4 × 4
  from each of the 9 anchors with `x = 1, y = 1`; check size and the corner pixel's colour),
  `zeroWidthCropsToTheEdge`, `cropIsClippedToThePicture`, `cropOutsideImageKeepsImage`,
  `cropScalesWithPreview` (`scale: 0.5` halves the rectangle). Resize: a table test
  `targetSizeTable` over every mode with `keepAspect` on and off, `dontEnlarge`/`dontShrink`
  combinations, on 4000 × 3000 and 3000 × 4000 inputs (write each expected size in the table by
  hand); `resizeNeverBelowOnePixel` (1 % of 10 × 10 → 1 × 1), `percentIgnoresScale`,
  `applyGivesExactTargetSize` (3000 × 2000 → longest 1000 → exactly 1000 × 667),
  `decodeLimitOnlyForPlainDownscale` (longest side with `dontEnlarge` → the side; crop on → nil;
  percent → nil). Orientation: `rotateLeftMovesTopLeftToBottomLeft`, `rotateRightMovesTopLeftToTopRight`,
  `flipsMirrorTheRightAxis`, `rotateThenFlipOrder`, `offIsIdentity`.
- [x] **Step 2: Run them to see them fail.** `swift test --filter GeometryStepsTests`
- [x] **Step 3: Implement** to the interfaces and behaviour above.
- [x] **Step 4: Run the tests, then the full suite.** `swift test`
- [x] **Step 5: Commit.** `feat: batch crop, resize, rotate and flip steps`

---

### Task 3: Colour steps, filters and colour reduction

**Files:**
- Create: `Sources/FeatherviewCore/ColourSteps.swift`
- Create: `Sources/FeatherviewCore/ColourQuantizer.swift`
- Test: `Tests/FeatherviewCoreTests/ColourStepsTests.swift`, `Tests/FeatherviewCoreTests/ColourQuantizerTests.swift`

**Interfaces:**
- Consumes (Task 1): `ColourSettings`, `FilterSettings`, `RGBAColor`, `PipelineRender.context`,
  `PipelineFixtures`; `RGBAImage`.
- Produces:
  ```swift
  public enum ColourStep {
      public static func apply(_ image: CIImage, _ s: ColourSettings, scale: Double) -> CIImage
  }
  public enum FilterStep {
      public static func apply(_ image: CIImage, _ s: FilterSettings, scale: Double) -> CIImage
  }
  public enum ColourQuantizer {
      /// At most `colours` distinct colours (2…256, clamped). 2 = black and white by luminance.
      /// Alpha is kept as it is. Floyd–Steinberg error diffusion when `dither`.
      public static func reduce(_ image: RGBAImage, colours: Int, dither: Bool) -> RGBAImage
  }
  ```

Behaviour to pin (values act on sRGB-encoded 0…1 values, as the render context works in sRGB;
alpha never changes):

- `ColourStep` order: auto-adjust, greyscale, negative, brightness, contrast, gamma, saturation,
  balance, sharpen, blur. `reduceColours` is not applied here (pixels step in Task 8).
  - auto-adjust: `image.autoAdjustmentFilters(options: [.redEye: false])` applied in order.
  - greyscale: Rec. 709 luminance (0.2126 R + 0.7152 G + 0.0722 B) into all three channels
    (`CIColorMatrix`).
  - negative: `1 − c` per colour channel (`CIColorInvert`).
  - brightness `b`: `c + b / 255`; contrast `k`: `(c − 0.5) × (1 + k / 127) + 0.5`; gamma `g`:
    `c^(1 / g)` (`g > 1` brightens); saturation `s`: `CIColorControls` saturation `1 + s / 255`;
    balance: `c + v / 255` for that channel. Results clamped to 0…1.
  - sharpen `n` (1…99): `CISharpenLuminance` sharpness `n / 25`, radius `1.5 × scale`.
  - blur `n` (1…99): `CIGaussianBlur` radius `n / 4 × scale` pixels on the clamped-to-extent image,
    cropped back.
- `FilterStep` order: auto levels, noise reduction, unsharp mask, colour temperature, sepia.
  - auto levels: per colour channel, the 0.5 % and 99.5 % points of a 256-bin histogram
    (`CIAreaHistogram`, rendered with `PipelineRender.context`) are stretched to 0 and 1
    (`CIColorMatrix` scale and bias). A flat channel (low = high) is left alone.
  - noise reduction `n`: `CINoiseReduction` noise level `n / 1000`, sharpness 0.4.
  - unsharp mask `n`: `CIUnsharpMask` radius `2.5 × scale`, intensity `n / 50`.
  - colour temperature `t`: `CITemperatureAndTint` from neutral (6500, 0) to (6500 − 30 t, 0) or
    whichever sign makes a mid-grey redder for `t > 0` and bluer for `t < 0`; the test decides.
  - sepia `n`: `CISepiaTone` intensity `n / 100`.
- `ColourQuantizer`: median cut on the opaque pixels' colours to `colours` boxes, each box's mean
  as its colour, nearest-colour mapping; 2 colours → luminance threshold at 128 (dithered when
  `dither`). Must handle a 24 MP image in well under a second in release (histogram on 5-bit-per-
  channel buckets, not a sort of every pixel).

- [x] **Step 1: Write the failing tests** — `ColourStepsTests`: `offIsIdentity`,
  `greyscaleUsesRec709` (pure green → 0.7152 × 255 ± 1 in every channel), `negativeKeepsAlpha`,
  `brightnessAddsToEncodedValues` (128 + 51 → 179 ± 1), `contrastMinusMaxIsFlatGrey`,
  `gammaTwoBrightens` (64 → 128 ± 1), `saturationMinusMaxIsGrey`, `balanceMovesOneChannel`,
  `blurKeepsEdgesBright` (a white image blurred stays white at the corners), `blurScalesWithPreview`
  (radius at `scale: 0.5` is half), `orderIsSpecOrder` (negative then brightness ≠ brightness then
  negative; pin the spec's result). `FilterStepsTests` (same file): `autoLevelsStretchesAGreyRamp`
  (a ramp 64…191 → 0…255 ± 2), `autoLevelsLeavesAFlatImage`, `warmerIsRedder`, `coolerIsBluer`,
  `sepiaFullTurnsGreyBrownish` (R > G > B), `unsharpMaskKeepsAFlatImage`. `ColourQuantizerTests`:
  `atMostNColours` (a 64 × 64 gradient to 16 → ≤ 16 distinct RGB), `twoColoursIsBlackAndWhite`,
  `alphaUntouched`, `fewerColoursThanAskedIsUnchanged`, `clampsCount` (1 → 2, 1000 → 256).
- [x] **Step 2: Run them to see them fail.** `swift test --filter "ColourStepsTests|ColourQuantizerTests"`
- [x] **Step 3: Implement** to the interfaces and behaviour above.
- [x] **Step 4: Run the tests, then the full suite.** `swift test`
- [x] **Step 5: Commit.** `feat: batch colour steps, filters and colour reduction`

---

### Task 4: Auto-crop, canvas and border

**Files:**
- Create: `Sources/FeatherviewCore/CanvasSteps.swift`
- Test: `Tests/FeatherviewCoreTests/CanvasStepsTests.swift`

**Interfaces:**
- Consumes (Task 1): `CanvasSettings`, `BorderSettings`, `ImageAnchor`, `RGBAColor`,
  `PipelineRender.context`, `PipelineFixtures`.
- Produces:
  ```swift
  public enum CanvasError: Error, Equatable { case nothingLeft }  // shown as "… leaves no image"
  public enum AutoCropStep {
      /// Removes uniform borders: rows/columns at each edge whose every pixel is within 8/255 per
      /// channel of that edge's corner colour. A uniform image is left whole.
      public static func apply(_ image: CIImage) -> CIImage
  }
  public enum CanvasStep {
      /// Runs auto-crop first when `s.autoCropBorders`.
      public static func apply(_ image: CIImage, _ s: CanvasSettings, scale: Double) throws -> CIImage
  }
  public enum BorderStep {
      public static func apply(_ image: CIImage, _ s: BorderSettings, scale: Double) -> CIImage
  }
  ```

Behaviour to pin:

- `perSide`: the new size is `w + left + right` × `h + top + bottom` (each × `scale`, rounded); the
  picture sits `left` from the left and `top` from the top. Negative values cut into the picture
  instead. A result with no pixels throws `.nothingLeft` (`negativeBorderLargerThanImageFails`).
- `totalSize`: the canvas is `width × height` (0 keeps that side); the picture placed at `anchor`.
  A canvas smaller than the picture crops it (the anchor decides which part stays).
- `aspectRatio`: the smallest canvas that contains the picture and has `ratioWidth : ratioHeight`
  (ratio ≤ 0 → unchanged), picture at `anchor`.
- New area: `colour` (a clear colour gives transparent pixels; whether they survive depends on the
  output format, the encoder decides).
- Auto-crop reads the pixels (render with `PipelineRender.context`, at most a 1024-pixel-long copy
  to find the edges, mapped back to full size so it stays fast on 24 MP).
- Border: an `outerWidth` frame of `outerColour` around an `innerWidth` frame of `innerColour`
  around the picture; widths × `scale`, rounded; 0-width frames are skipped. The picture grows by
  both widths on every side.

- [x] **Step 1: Write the failing tests** — `perSideAddsAndPlaces` (10 × 10 + left 2, right 3, top 4,
  bottom 1 → 15 × 15, the picture's top-left pixel at (2, 4)), `negativeSideCutsIn`,
  `negativeBorderLargerThanImageFails`, `totalSizeAtEachAnchor` (9 anchors, picture corner position),
  `totalSizeZeroKeepsThatSide`, `totalSizeSmallerCrops`, `aspectRatioSixteenNine` (1000 × 1000 →
  1778 × 1000 ± 1), `aspectRatioPortrait`, `clearColourIsTransparent`, `canvasScalesWithPreview`,
  `autoCropRemovesUniformBorders` (a red 20 × 20 picture in a white 40 × 30 canvas → 20 × 20),
  `autoCropKeepsUniformImage`, `autoCropToleratesJPEGNoise` (borders off by ±5 still removed),
  `borderTwoFramesNested` (colours at the expected offsets), `borderZeroWidthSkipped`, `offIsIdentity`.
- [x] **Step 2: Run them to see them fail.** `swift test --filter CanvasStepsTests`
- [x] **Step 3: Implement** to the interfaces and behaviour above.
- [x] **Step 4: Run the tests, then the full suite.** `swift test`
- [x] **Step 5: Commit.** `feat: batch auto-crop, canvas and border steps`

---

### Task 5: Text overlay and watermark

**Files:**
- Create: `Sources/FeatherviewCore/OverlaySteps.swift`
- Test: `Tests/FeatherviewCoreTests/OverlayStepsTests.swift`

**Interfaces:**
- Consumes (Task 1): `TextSettings`, `WatermarkSettings`, `ImageAnchor`, `RGBAColor`,
  `PipelineFixtures`; `Fixtures.writeImage` (a PNG watermark file in a temp folder).
- Produces:
  ```swift
  public struct TextValues: Sendable, Equatable {  // what {name} {folder} {date} {n} become
      public var name, folder, date: String; public var index: Int
      public init(name: String, folder: String, date: String, index: Int)
  }
  public enum TextStep {
      public static func render(_ template: String, _ v: TextValues) -> String
      public static func apply(_ image: CIImage, _ s: TextSettings, values: TextValues, scale: Double) -> CIImage
  }
  public enum WatermarkError: Error, Equatable { case unreadable(String) }  // the watermark file's name
  public enum WatermarkStep {
      /// Loads the watermark once per batch (Task 8 caches it); throws when the file can't be read.
      public static func load(_ path: String) throws -> CIImage
      public static func apply(_ image: CIImage, watermark: CIImage, _ s: WatermarkSettings) -> CIImage
  }
  ```

Behaviour to pin:

- `render`: one pass, `{name}` `{folder}` `{date}` `{n}` (and `{n:3}` zero-padded, as in
  `RenamePattern`); unknown placeholders stay as typed; a value containing `{date}` is not replaced
  again (same rule as `OverlayTemplate.render`).
- Text is drawn with Core Text into a transparent `CGContext` the size of the text block, then
  composited over the image (`composited(over:)`). Font: `CTFontCreateWithName(fontName, size)`; an
  unknown name falls back to the system font (Core Text does this). Size in points =
  `sizePercent / 100 × shorter side` of the image being drawn on (so the preview scales itself).
  Lines are aligned to the position's side (left positions → leading-aligned in picture terms,
  centre → centred, right → right-aligned). Margin = `marginPercent / 100 × shorter side`.
- `opacity` multiplies the text (and box) alpha. `shadow`: offset (1, −1) × size / 20, blur
  size / 15, black at 60 %. `backgroundBox`: a `boxColour` rectangle behind the text block padded by
  size / 4.
- `stripBelow` / `stripAbove`: the image grows by a strip of height `text block + 2 × margin`,
  filled with `boxColour` (made opaque) when `backgroundBox` is on, else black; the text sits in the
  strip at the position's horizontal side (its vertical part is ignored).
- Watermark: scaled to `widthPercent / 100 × image width` (aspect kept), placed at `position` with
  the margin, `opacity` multiplies its alpha, composited over. Not resized by `scale` (it is a
  share of the image width already).
- Empty text after rendering → image unchanged. An empty watermark path with the step on →
  `load` throws `.unreadable("")`; Task 8 reports it once per file as "Can't read the watermark
  image <name>".

- [x] **Step 1: Write the failing tests** — `renderPlaceholders`, `renderKeepsUnknown`,
  `renderDoesNotReplaceTwice`, `renderPadsCounter`; `textChangesPixelsOnlyNearItsCorner` (white
  text bottom-right on a black 400 × 300 image: changed pixels all in the bottom-right quarter),
  `textAtEachAnchorLandsInThatRegion` (9 anchors), `textOpacityZeroChangesNothing`,
  `textSizeFollowsShorterSide` (the changed area's height scales with the image),
  `stripBelowGrowsTheImage` (height grows, original pixels unchanged at the top),
  `stripAboveShiftsTheImageDown`, `emptyTextIsIdentity`; watermark: `watermarkAtBottomRight`,
  `watermarkWidthIsAShareOfTheImage`, `watermarkOpacity` (a red watermark at 0.5 on black → ≈128 red),
  `missingWatermarkFileThrows`, `watermarkKeepsTransparency` (a PNG with a transparent hole leaves the
  image visible there).
- [x] **Step 2: Run them to see them fail.** `swift test --filter OverlayStepsTests`
- [x] **Step 3: Implement** to the interfaces and behaviour above.
- [x] **Step 4: Run the tests, then the full suite.** `swift test`
- [x] **Step 5: Commit.** `feat: batch text overlay and watermark steps`

---

### Task 6: Input list

**Files:**
- Create: `Sources/FeatherviewCore/BatchInputList.swift`
- Test: `Tests/FeatherviewCoreTests/BatchInputListTests.swift`

**Interfaces:**
- Consumes (Task 1): `BatchInput`. Existing: `FolderScanner.inFinderOrder(_:)`,
  `ImageFormats.isDecodable(_:)`, `pathKey`, `Fixtures.makeTempDir`, `Fixtures.writeImage`.
- Produces:
  ```swift
  public struct BatchInputList: Equatable, Sendable {
      public private(set) var items: [BatchInput]
      public init(_ items: [BatchInput] = [])
      /// Appends in Finder order; skips files already in the list (same resolved path) and
      /// anything that isn't a decodable image.
      public mutating func add(files: [URL])
      /// Lists `folder` (and, with `subfolders`, every folder below it, skipping hidden ones and
      /// packages) off the caller's thread: call it from a background task. Hidden and non-image
      /// files are skipped. Each folder's files in Finder order, folders depth-first in Finder
      /// order. Every item gets `root: folder`.
      public static func scan(folder: URL, subfolders: Bool) throws -> [BatchInput]
      public mutating func append(_ inputs: [BatchInput])   // same de-duplication as add(files:)
      public mutating func remove(at offsets: IndexSet)
      public mutating func removeAll()
      public mutating func sortByName()        // Finder order of the file names, stable
      public mutating func move(_ offsets: IndexSet, by delta: Int)  // up = −1, down = +1, clamped
      /// One absolute path per line, UTF-8, "\n" line ends.
      public func listText() -> String
      /// Paths from a saved list (blank lines, "#" comments and missing files skipped); returns how
      /// many lines named files that no longer exist.
      public mutating func load(listText: String) -> (added: Int, missing: Int)
  }
  ```

Behaviour to pin:

- De-duplication by `pathKey` of the resolved URL (symlink to a listed file is the same file).
- `scan` never opens file contents (extension check only, like `FolderScanner`); a folder that
  can't be listed throws; an unreadable subfolder is skipped, not fatal; symlinked folders are not
  followed (no loops).
- `move` of several selected rows keeps their relative order; moving past either end clamps.

- [x] **Step 1: Write the failing tests** — `addAppendsInFinderOrder` (img10, img2 → img2, img10
  after existing items), `addSkipsDuplicatesAndSymlinks`, `addSkipsNonImages`, `scanSkipsHiddenAndNonImages`,
  `scanWithSubfoldersIsDepthFirstInFinderOrder`, `scanDoesNotFollowSymlinkLoops`, `scanSetsRoot`,
  `removeAndRemoveAll`, `sortByNameIsFinderOrder`, `moveUpAndDownKeepsSelectionOrder`, `moveClamps`,
  `listTextRoundTrips`, `loadSkipsMissingAndComments` (counts missing), `loadHandlesCRLF`.
- [x] **Step 2: Run them to see them fail.** `swift test --filter BatchInputListTests`
- [x] **Step 3: Implement** to the interface above.
- [x] **Step 4: Run the tests, then the full suite.** `swift test`
- [x] **Step 5: Commit.** `feat: batch input list with folders, sort, move and saved lists`

---

### Task 7: Output naming, rename-only copy and dates

**Files:**
- Create: `Sources/FeatherviewCore/BatchNamer.swift`
- Modify: `Sources/FeatherviewCore/RenamePattern.swift` (add `{date}`), `Sources/FeatherviewCore/MetadataReader.swift` (add `dateTaken`)
- Test: `Tests/FeatherviewCoreTests/BatchNamerTests.swift`; extend `Tests/FeatherviewCoreTests/MetadataReaderTests.swift`

**Interfaces:**
- Consumes (Task 1): `BatchInput`, `BatchSettings`, `SafetySettings`. Existing: `RenamePattern`,
  `pathKey`, `BatchPlanner` (its 255-byte trimming and " 2" suffix logic move here).
- Produces:
  ```swift
  extension RenamePattern {
      /// `{date}` = `date` as YYYY-MM-DD (UTC-independent: the date as shot, local calendar).
      public func baseName(original: String, index: Int, date: Date?) -> String
  }
  extension MetadataReader {
      /// EXIF DateTimeOriginal as a local date, else the file's modification date, else nil.
      public static func dateTaken(of url: URL) -> Date?
  }
  public struct BatchNamer: Sendable {
      /// `inputs` are reserved (never chosen as an output, never replaced).
      public init(settings: BatchSettings, inputs: [BatchInput],
                  fileExists: @escaping @Sendable (URL) -> Bool = { /* lstat-based, like BatchPlanner */ })
      /// The folder `input`'s output goes to: `outputFolder` with `{folder}` = the input's parent
      /// folder name, plus the input's subfolder path below its `root` when `recreateSubfolders`.
      public func folder(for input: BatchInput) -> URL
      /// The next output URL for a file that succeeded. Advances the counter. Extension: the
      /// output format's, or in `.rename` mode the input's own, as it is.
      /// Without `replaceExisting`: never an existing file, an input, or a name given earlier in
      /// this run (case-insensitive) — " 2", " 3", … appended. With it: an existing non-input file
      /// may be returned (the caller trashes it first); inputs and names given in this run still
      /// get suffixes.
      public mutating func next(for input: BatchInput, date: Date?) -> URL
  }
  public enum BatchCopy {
      /// Rename mode: copies `input`'s bytes to a hidden temp file in `output`'s folder, then moves
      /// it in without replacing (`BatchConverter.moveExclusive`). Returns the final URL (a " 2"
      /// suffix if the name was taken meanwhile).
      public static func copy(_ input: URL, to output: URL) throws -> URL
  }
  ```

Behaviour to pin:

- The counter starts at 1 and advances only on `next` (called only for files that succeeded).
- Without a rename (mode `.convert`, or an empty pattern) the base name is the input's own.
  `RenamePattern` is used in `.rename` and `.convertAndRename`; in `.convert` the pattern is ignored.
- `{folder}` is replaced only in `outputFolder` (spec "Output"), not in the rename pattern. For an
  input directly in `/` it becomes "-".
- 255-byte name limit as in `BatchPlanner` (decomposed UTF-8, whole characters).
- `BatchPlanner` and its tests are deleted in Task 8, not here (the old converter still uses it).

- [x] **Step 1: Write the failing tests** — `RenamePattern`: `dateIsISODay`, `nilDateIsEmpty` (the
  caller passes the file date when EXIF has none; `nil` only when both are missing).
  `MetadataReaderTests.dateTakenPrefersExif` (a JPEG written with `DateTimeOriginal` via
  `Fixtures.writeImage` properties), `dateTakenFallsBackToModificationDate`. `BatchNamerTests`:
  `counterAdvancesOnlyOnNext`, `convertModeKeepsNames`, `renameModeKeepsExtension`,
  `clashesAreCaseInsensitive`, `existingFileGetsSuffix`, `neverReplacesAnInput` (also with
  `replaceExisting`), `replaceExistingReturnsTheExistingName`, `folderPlaceholder`,
  `recreateSubfoldersAddsRelativePath`, `filesWithoutRootIgnoreRecreate`, `longNamesAreTrimmedTo255Bytes`.
  `BatchCopyTests` (same file): `copyKeepsBytes`, `copyNeverReplaces`.
- [x] **Step 2: Run them to see them fail.** `swift test --filter "BatchNamerTests|MetadataReaderTests|RenamePattern"`
- [x] **Step 3: Implement** to the interface above (keep `RenamePattern.baseName(original:index:)`
  working for the old converter until Task 8).
- [x] **Step 4: Run the tests, then the full suite.** `swift test`
- [x] **Step 5: Commit.** `feat: batch output naming with dates, folders and rename-only copies`

---

### Task 8: Pipeline and converter

**Files:**
- Create: `Sources/FeatherviewCore/ImagePipeline.swift`
- Modify: `Sources/FeatherviewCore/BatchJob.swift` (replace with the new job; delete `BatchPlanner`),
  `Sources/FeatherviewCore/BatchConverter.swift` (rewrite `run` and `convert`),
  `Sources/FeatherviewCore/ImageEncoder.swift` (DPI property), `Sources/FeatherviewCore/ImageSaver.swift`
  (pages with the pipeline)
- Modify: `Sources/Featherview/BatchView.swift` only as far as needed to compile with the new job
  (the window is rebuilt in Tasks 10–11)
- Test: `Tests/FeatherviewCoreTests/ImagePipelineTests.swift`, rewrite `BatchConverterTests.swift`,
  delete `BatchPlannerTests.swift` (its cases move to `BatchNamerTests` in Task 7 and here)

**Interfaces:**
- Consumes: Tasks 1–7 (all step `apply` functions, `PipelineRender`, `ColourQuantizer`,
  `BatchNamer`, `BatchCopy`), `ImageSaver.pages`, `ImageEncoder.encode`,
  `ImageDecoder`, `Sidecars.files(for:)`, `MetadataReader.dateTaken`.
- Produces:
  ```swift
  public struct PipelineContext: Sendable {
      public var values: TextValues
      public var scale: Double = 1
      public var originalSize: CGSize?      // set when decoded smaller (ResizeStep.decodeLimit)
      public var watermark: CIImage?        // loaded once per batch
  }
  public enum ImagePipeline {
      /// Spec order: crop, resize, rotate/flip, colour, filters, canvas (auto-crop first), border,
      /// text, watermark; renders once; reduces colours last when set.
      public static func apply(_ image: CGImage, _ settings: BatchSettings, context: PipelineContext) throws -> CGImage
  }
  public struct BatchJob: Sendable {
      public var inputs: [BatchInput]
      public var settings: BatchSettings
      public init(inputs: [BatchInput], settings: BatchSettings)
  }
  public enum BatchStatus: Sendable, Equatable { case converted, failed, notStarted }
  public struct BatchResult: Sendable, Equatable {
      public let input: URL
      public let output: URL?               // nil when failed or not started
      public let status: BatchStatus
      public let message: String?           // error sentence, or "page 1 of 3"
      public var logLine: String { get }     // "IMG_1.jpg → Holiday 001.heic", "Can't open broken.jpg", "… · page 1 of 3"
  }
  /// Stop / Pause / Resume, shared between the window and the running batch.
  public final class BatchControl: Sendable {   // Mutex-protected state + a continuation for resume
      public init()
      public func pause(); public func resume(); public func stop()
      public var isPaused: Bool { get }; public var isStopped: Bool { get }
  }
  public enum BatchConverter {
      /// Calls `onResult` once per input, in list order, as each is committed (off the main thread).
      /// Returns every result (not-started ones after a Stop).
      public static func run(_ job: BatchJob, control: BatchControl = BatchControl(),
                             onResult: @escaping @Sendable (BatchResult) -> Void = { _ in }) async -> [BatchResult]
  }
  public enum BatchLog {
      /// One line per result, then "N converted, M failed" (and ", K not converted" after a Stop).
      public static func text(_ results: [BatchResult]) -> String
  }
  ```

Behaviour to pin:

- Workers: `max(1, activeProcessorCount − 1)`, blocking work on GCD (keep `offPool`). Each worker:
  decode (all pages the format needs, `ImageSaver.pages`; with `ResizeStep.decodeLimit` as
  `maxPixelSize` when it isn't nil, and then the upright original size passed on through
  `PipelineContext.originalSize: CGSize?` to `ResizeStep.apply(…, originalSize:)`, so the output
  keeps the exact target size), run the pipeline per page, encode to `Data`. Rename mode skips
  decode/encode entirely.
- Commit stage (one at a time, list order): for a succeeded file take `namer.next`, create the
  folder (`recreateSubfolders` / `{folder}`), with `replaceExisting` trash an existing non-input
  file of that name first, write temp + `moveExclusive` (keep milestone 1's code), then
  `keepDates` (`setAttributes([.modificationDate: input's])`), then `trashOriginals` (the input and
  its `Sidecars.files`, only after the move succeeded). A worker may run ahead of the commit by at
  most `2 × workers` files; then it waits (`commitWindowIsBounded`).
- Stop: no new file starts; in-flight ones finish and commit; the rest get `.notStarted`. Pause:
  no new file starts until Resume; in-flight ones finish.
- Multi-page input written to a single-page format: `message = "page 1 of N"` (localized format
  string), still `.converted`.
- Errors (localized format strings, the file's name): decode → "Can't open %@"; pipeline
  `CanvasError.nothingLeft` → "%@: the canvas settings leave no image"; watermark unreadable → "Can't
  read the watermark image %@" (every file fails with it; the batch still runs to the end so the log
  is complete); encode → "Can't write %@ as %@"; write → "Can't save %@".
- DPI: `ImageEncoder.encode` gains `dpi: Int? = nil`, written as `kCGImagePropertyDPIWidth/Height`
  for ImageIO formats (PNG/JPEG/TIFF/HEIC read it back).
- Text values: `{name}` input base name, `{folder}` its parent folder's name, `{date}` from
  `MetadataReader.dateTaken` as YYYY-MM-DD, `{n}` the 1-based place in the list.
- Fast path: `!settings.hasOperations` → no Core Image at all (pages go straight to the encoder, as
  in milestone 1), so a plain conversion is not slower than before.
- `ImageSaver.save` (Save As) is unchanged in behaviour.

- [x] **Step 1: Write the failing tests** — `ImagePipelineTests`: `noOperationsKeepsPixels`,
  `specOrderCropThenResize` (crop 100 × 100 from a 400 × 400 `quadrants` then resize to 50 → one
  colour), `rotateAfterResize` (resize width 200 on 400 × 100, then rotate → 50 × 200),
  `canvasThenBorderThenText` (sizes add up), `reduceColoursIsLast`, `scaleShrinksPixelSettings`.
  `BatchConverterTests` (rewrite, keep milestone 1's still-valid cases: corrupt file continues,
  never overwrites, temp files cleaned, `moveExclusive` fallbacks):
  `counterFollowsListOrderAndSkipsFailures` (a convert seam where input 2 fails and input 4 finishes
  first), `renameModeCopiesBytes`, `convertAndRenameUsesPattern`, `multiPageNotesPageOneOfN`
  (`Fixtures.writeMultiPageTIFF` → JPEG), `keepAllPagesTIFFHasNoNote`, `replaceExistingTrashesOldFile`
  (the old file is in the Trash or, where the test can't use the Trash, a `trash:` seam was called),
  `replaceExistingNeverTouchesInputs`, `fileAppearingDuringRunIsKept`, `trashOriginalsOnlyAfterWrite`
  (a failing write keeps the original), `trashOriginalsTakesSidecars`, `keepDatesCopiesModificationDate`,
  `recreateSubfolders`, `stopFinishesInFlightAndStartsNoMore`, `pauseHoldsThenResumes`,
  `commitWindowIsBounded` (a seam that counts finished-but-uncommitted files never above 2 × workers),
  `watermarkMissingFailsEveryFileOnce`, `dpiIsWritten`, `logTextSummary`.
- [x] **Step 2: Run them to see them fail.** `swift test --filter "ImagePipelineTests|BatchConverterTests"`
- [x] **Step 3: Implement.** Add a `trash: @Sendable (URL) throws -> Void` seam
  (`FileManager.default.trashItem`) so tests don't fill the real Trash. Update `BatchModel.run()` to
  build a `BatchJob(inputs:settings:)` from its current fields so the app still compiles and works.
- [x] **Step 4: Run the tests, then the full suite.** `swift test`, then `scripts/bundle.sh debug`
  (the app must still build).
- [x] **Step 5: Commit.** `feat: batch pipeline and converter with ordered commits, stop, pause and safety options`

---

### Task 9: HDR kept for HEIC and AVIF output

**Files:**
- Modify: `Sources/FeatherviewCore/PipelineRender.swift`, `Sources/FeatherviewCore/ImagePipeline.swift`,
  `Sources/FeatherviewCore/BatchConverter.swift`, `Sources/FeatherviewCore/ImageEncoder.swift`
- Test: `Tests/FeatherviewCoreTests/HDROutputTests.swift`

**Interfaces:**
- Consumes: Task 8 (`ImagePipeline`, converter), `ImageDecoder.decode(_:maxPixelSize:page:hdr:)`,
  `ImageDecoder.supportsHDR`, `Fixtures.writeHDRGainMap`.
- Produces: `PipelineRender.cgImage(_ image: CIImage, hdr: Bool) throws -> CGImage` (the old
  one-argument call stays, meaning `hdr: false`); `ImagePipeline.apply(…, hdr: Bool = false)`.
  No new public types.

Behaviour to pin:

- Only when all hold: macOS 15+ (`supportsHDR`), output format id `heic` or `avif`, the decoded
  input is HDR (the decoder's `hdr: true` path returns an image with an HDR colour space). Else
  everything stays 8-bit SDR as before.
- HDR render: working space extended linear sRGB, `RGBAh`, output a 16-bit-float CGImage in
  `CGColorSpace(name: .itur_2100_PQ)` (or extended linear Display P3, whichever ImageIO writes as a
  gain map / HDR HEIC on macOS 15+; the test decides). Colour steps act on linear values here:
  `// shortcut: colour steps on HDR act on linear light, not the encoded values the SDR path uses; match them if anyone compares.`
- Encode: for HDR images pass the macOS 15 encode request that keeps HDR (an HDR CGImage written to
  HEIC/AVIF with `kCGImageDestinationEncodeRequest` = `kCGImageDestinationEncodeToISOGainmap` or
  the plain HDR write; pin whichever reads back as HDR).
- `ColourQuantizer` (8-bit) is skipped for HDR output, i.e. reducing colours forces SDR.

- [x] **Step 1: Write the failing tests** (each `@Test(.enabled(if: ImageDecoder.supportsHDR))`):
  `hdrHEICStaysHDR` (`writeHDRGainMap` → batch to HEIC → decoding the output with `hdr: true` gives
  an HDR colour space and values above 1.0 somewhere), `hdrToAVIFStaysHDR`, `hdrToJPEGIsSDR`,
  `sdrToHEICIsSDR`, `hdrWithOperationsStaysHDR` (resize + border), `reduceColoursForcesSDR`.
- [x] **Step 2: Run them to see them fail.** `swift test --filter HDROutputTests`
- [x] **Step 3: Implement.**
- [x] **Step 4: Run the tests, then the full suite.** `swift test`
- [x] **Step 5: Commit.** `feat: keep HDR when batch-converting HDR photos to HEIC or AVIF`

---

### Task 10: Batch window shell, images column, toolbar and running view

**Files:**
- Create: `Sources/Featherview/BatchModel.swift` (move `BatchModel` out of `BatchView.swift` and grow it)
- Create: `Sources/Featherview/BatchImagesColumn.swift`, `Sources/Featherview/BatchRunView.swift`
- Modify: `Sources/Featherview/BatchView.swift` (the three-column window), `Sources/Featherview/FeatherviewApp.swift` (window size, title "Batch")

**Interfaces:**
- Consumes: `BatchSettings`, `BatchPresets`, `BatchInputList`, `BatchJob`, `BatchConverter`,
  `BatchControl`, `BatchResult`, `BatchLog`, `ViewerModel.lastActive`.
- Produces (for Task 11):
  ```swift
  enum BatchStep: String, CaseIterable, Identifiable {
      case output, rename, crop, resize, orientation, colour, filters, canvas, border, text, watermark, safety
      var title: LocalizedStringKey { get }
  }
  @MainActor @Observable final class BatchModel {
      var settings: BatchSettings          // saved with BatchPresets.saveCurrent on every change (debounced)
      var inputs: BatchInputList
      var selection: Set<BatchInput>        // in the images column
      var step: BatchStep                   // selected step
      var isRunning: Bool { get }; var isPaused: Bool { get }
      var results: [BatchResult] { get }    // in list order, grows while running
      func summary(of step: BatchStep) -> String   // "HEIC", "2048", "on", "" (for the steps column)
      func isOn(_ step: BatchStep) -> Bool
      func isUsed(_ step: BatchStep) -> Bool       // false = dimmed (e.g. operations in Rename mode)
      func start(); func pause(); func resume(); func stop()
      func copyLog()
      var presetName: String?                // nil = unsaved changes since the last load/save
  }
  /// Task 11 fills this in; Task 10 ships it showing the step's title only.
  struct BatchStepDetail: View { let step: BatchStep; @Bindable var model: BatchModel }
  ```

Behaviour (spec "Window"):

- Toolbar: mode as a segmented picker, a presets menu (presets by name, Save Preset…, Delete
  Preset, a checkmark on the loaded one, "(edited)" after a change), Start (default action, disabled
  without inputs or output folder in convert modes); while running: Pause/Resume and Stop instead.
- Images column: rows with a 36-pt thumbnail (decoded off the main thread with
  `ImageDecoder.decode(maxPixelSize: 72)`, cached per URL in an `NSCache`, never blocking scrolling),
  name, `w × h · size` (and "· N pages"); count and total size in the header; multi-select;
  delete key removes; drop files and folders (folders add with subfolders); bottom bar: add menu
  (Add Files…, Add Folder…, Add Folder with Subfolders…, Use Viewer's Folder), remove, Sort ▾ (by
  name), a ⋯ menu with Move Up, Move Down, Save List…, Load List…. Folder scans and list loading
  run in a background task with a small spinner in the header.
- Steps column: `List` with sections Output (output, rename), Operations (crop … watermark), Files
  (safety); each row the title and `summary`, dimmed when `!isUsed`.
- Running view replaces the steps and detail columns: progress (n of N, time left after 3 files),
  the log (`results` lines, monospaced, selectable, scrolls to the newest), Copy Log; each image row
  shows its state. When finished, the summary line stays at the top until the settings are changed
  or Start is pressed again; the settings columns come back.
- `AppDelegate.isBusy` keeps working (quitting during a run asks first).
- Window: min 960 × 600, restores its size.

- [x] **Step 1:** Build the model and views to the description above (no Core logic in the app:
  anything testable goes into Core with a test).
- [ ] **Step 2:** `swift build`, `scripts/bundle.sh debug`, open it and check by hand: add files,
  folder with subfolders, drop, sort, move, save/load list, presets save/load/delete, start, pause,
  resume, stop, copy log, quit during a run.
- [x] **Step 3: Commit.** `feat: three-column batch window with input list, presets and run view`

---

### Task 11: Step settings and live preview

**Files:**
- Create: `Sources/Featherview/BatchStepViews.swift` (one view per step, and `BatchStepDetail`)
- Create: `Sources/Featherview/BatchPreview.swift`
- Modify: `Sources/Featherview/BatchView.swift` only to place the preview under the detail

**Interfaces:**
- Consumes: Task 10's `BatchModel`, `BatchStep`, `BatchStepDetail`; Core: every `*Settings`,
  `ImagePipeline.apply(…, context:)` with `scale`, `BatchNamer`, `FormatOptionsView`,
  `FormatSettings` (profiles), `NSFontPanel`/`NSFontManager` for the text font.
- Produces: nothing other tasks use.

Behaviour (spec "Window", "Output", "Per-image operations", "Safety and options"):

- One form per step, labels trailing-aligned in a grid like the mockups, each operation with an
  On switch in its header. Output: format picker + "Options…" button opening `FormatOptionsView`
  in a sheet (the spec's "Options…" button; remove the inline options milestone 3 left in batch),
  output folder field + Choose… + "Use the input's folder", the `{folder}` hint. Rename: pattern
  field, placeholder buttons (`{name}` `{n}` `{n:3}` `{date}`), hint that the counter skips failures.
  Crop: x, y, width, height, a 3 × 3 anchor picker (shared `AnchorPicker` view, also used by
  canvas, text, watermark; each cell an accessible button named for its position). Resize: mode
  picker with the fields of that mode, the three checkboxes, DPI. Rotate & Flip: segmented rotate,
  two checkboxes. Colour: checkboxes and sliders with number fields and the reference ranges,
  reduce colours (2–256) with dither. Filters: five sliders/switch. Canvas: method picker and its
  fields, anchor, colour well, auto-crop checkbox. Border: two width + colour rows. Text: text
  editor, placeholder buttons, font button (opens the font panel; shows "name, size %"), colour
  well, anchor + margin, placement picker, opacity slider, shadow and box checkboxes. Watermark:
  Choose… image, anchor + margin, width %, opacity slider. Safety: the four checkboxes.
- Live preview (below the detail): the selected input (or the first) decoded at most 400 px long
  off the main thread, `ImagePipeline.apply` with `scale = preview size / original size`, shown
  next to the original with both sizes ("Original 4032 × 3024", "Output 2048 × 1536"). Recomputed
  150 ms after the last settings change, the previous computation cancelled (`LatestWins` exists
  in Core for this), never blocking typing. Errors show as a short line instead of the image.
- Output names list: the first five names from a `BatchNamer` with the current settings (as if
  every file succeeds), computed off the main thread, then "… N more · into <folder>".
- All text through SwiftUI literals; colour wells via `ColorPicker` bound to `RGBAColor`.

- [ ] **Step 1:** Build the views and preview.
- [ ] **Step 2:** `swift build`, `scripts/bundle.sh debug`, check by hand that every control
  changes the preview or names as expected and that typing quickly in the resize field stays smooth
  with a 24 MP input selected.
- [ ] **Step 3: Commit.** `feat: batch step settings and live preview`

---

### Task 12: Manual QA, docs and roadmap

Needs the screen: ask the maintainer before driving the GUI.

- [ ] **Step 1:** Release build (`scripts/bundle.sh`), batch of the real-world files (session
  scratchpad / `research/` samples) through every mode: convert to JPEG/HEIC/PNG/WebP/TIFF with
  keep-all-pages/PDF; rename only; convert and rename with `{date}` and `{n:3}` and a corrupt file in
  the middle (no gap); every operation once with the preview compared to the output; presets;
  replace existing (old file in the Trash), trash originals (with an `.xmp` sidecar), keep dates,
  recreate subfolders; stop and pause mid-run; copy log; an HDR iPhone HEIC to HEIC (still HDR in
  the viewer) and to JPEG (SDR).
- [ ] **Step 2:** Measure: 100 × 12 MP JPEG → JPEG with no operations, before (main before this
  milestone) and after: not slower. Same with resize + text: note the time.
- [ ] **Step 3:** Update `README.md` if it lists batch features, `docs/roadmap.md` (milestone 4
  done), `docs/parity.md` rows for batch that change status, tick this plan.
- [ ] **Step 4: Commit.** `docs: milestone 4 done after manual QA`
