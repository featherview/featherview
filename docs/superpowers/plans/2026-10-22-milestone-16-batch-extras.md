# Milestone 16: Batch extras — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. In this repo, code tasks run with the `plan-wave` workflow; tasks marked "main session" need the screen and run in the main session after the maintainer's go.

**Goal:** The batch can write every frame or page of a file, cut each output into tiles, and set or
shift the date taken; the viewer can adjust the date taken of the image it shows, in place and
losslessly.

**Architecture:** Three new batch steps in the existing card model: **Frames and Pages** (first:
one decoded image per frame or page, each through the whole pipeline), **Tiles** (last: the
finished image cut into columns × rows) and **Date Taken** (metadata only). The converter stays
one job per input; an input that yields several outputs writes each part to a hidden temp file in
its output folder as it is made, and the serial commit names and moves them in, so memory stays
bounded and the `{n}` counter still counts inputs. Names get a new `{part}` placeholder (appended
as `-{part}` when the pattern lacks it). Date changes go through a new Core `DateTaken` that uses
ImageIO's lossless `CGImageDestinationCopyImageSource` with `kCGImageDestinationDateTime`.

**Tech Stack:** Swift 6, ImageIO, SwiftUI + AppKit (macOS 14+), Swift Testing. No new dependency.

**Spec:** `docs/spec.md` "Batch window", "Output", "Per-image operations", "Safety and options",
"Menu commands"; `docs/roadmap.md` "Batch extras (v2)"; `docs/parity.md` "Batch extras" and
"Batch" (Multi-page input). Rules: `AGENTS.md`. Task 7 writes the decisions below into the spec.

## Decisions (the spec leaves these to the plan; accepted by the maintainer)

1. **Where the features live.** Frames, pages and tiles are **batch only**; the viewer gets only
   **Image › Adjust Date Taken…** (an in-place metadata change, like lossless rotate). One file
   from the viewer reaches the batch with B and Add Files, or the M13 grid's B on its selection.
2. **Frames and Pages step** (Add Step menu, first in processing order). On: every frame of an
   animation (`Animation.read(url) != nil`: GIF, APNG, WebP, HEICS, AVIS, ANI) or every page of a
   multi-page file (`ImageDecoder.pageCount(of:) > 1`: TIFF, PDF, DCX) becomes its own output, each
   through the whole pipeline, each a single-page file (TIFF "keep all pages" and PDF output then
   write one page). All frames, no range. Frames come in order from one kept source (M9's frame
   reader, full size, composited); pages from `ImageDecoder.decode(url, page:)`. A still gives one
   output, named as without the step. HDR is kept only for single-part inputs.
3. **Tiles step** (Add Step menu, last in processing order, after watermark): columns 1–100 and
   rows 1–100 (default 2 × 2), overlap in pixels (default 0; negative leaves gaps). What the
   preview shows is what gets cut. All tiles have the same size: `w = min(W, ceil((W + (c − 1)·o) / c))`
   (under 1 px the input fails); tile *i*'s `x = round(i·(W − w) / (c − 1))` (0 for c = 1); the same for rows.
   So the first tile starts at 0, the last ends at W, and neighbours share about `o` pixels. Tiles
   of a multi-page input without Frames and Pages: page 1 only, with the existing "page 1 of 3"
   note. With both steps: tiles of every frame.
4. **Naming parts — `{part}`.** One new placeholder: frames and pages give their number, 1-based,
   zero-padded to the digits of the count (`01` … `12`); tiles give `row-column`, each 1-based and
   padded to the digits of rows / columns (`1-2`, `01-10`), rows top to bottom, columns left to
   right in the picture (never mirrored); both steps give `frame-row-column` (`03-1-2`). A pattern
   without `{part}` gets `-{part}` appended when an input yields more than one output
   (`holiday-01.png`); a single-output input never gets it, and an explicit `{part}` then becomes
   `1`. `{n}` counts inputs: every part of one input shares it, and it advances only when the input
   succeeds. Clashes get " 2", " 3" per part as today (`holiday-01 2.png`); "Replace existing files"
   applies per part.
5. **One input, many outputs = one unit.** Each part is encoded and written to a hidden
   `.featherview-<uuid>.tmp` in the output folder as soon as it is made (one frame in memory per
   worker). If any part fails, the input fails with one sentence and its temps are removed; if
   moving a part in fails at commit, the parts already moved for that input are removed again (they
   are this run's own new files). Stop finishes inputs in flight, as now.
6. **Date Taken step**: "Set to" one date and time, or "Shift" later / earlier by days, hours,
   minutes, seconds. It rewrites the outputs' date, never the originals'. Re-encoded outputs get
   EXIF `DateTimeOriginal`, `DateTimeDigitized` and TIFF `DateTime` in the encode properties (also
   with the format's "keep metadata" off: the step asked for it); with Change format off and no
   pixel step the output is the original's bytes with only the date changed (lossless), and a file
   whose type can't be changed that way fails with "Can't change the date taken of IMG_0412.gif".
   `{date}` in the pattern and in the text overlay use the new date. The output's file dates
   (modified and created) follow the new date taken and win over "Keep file dates".
7. **Shift without a date taken** starts from the file's modification date (as `{date}` already
   falls back), so the output gains an EXIF date. Dates are wall times as EXIF stores them; shifting
   is plain arithmetic on the wall time (no time zone, so no daylight-saving jumps). The file date
   is that wall time at the EXIF `OffsetTimeOriginal` when present, else in the Mac's time zone.
8. **Adjust Date Taken… in the viewer** (Image menu, no key; enabled as Rotate is): a sheet shows
   "Original" (the date taken, or "None, file date …") and "Adjusted" (a date-and-time picker with
   seconds, starting at the original). Adjust changes the file in place: lossless rewrite to a temp
   file next to it, swapped in (a symlink's target is changed), then its modified and created dates
   follow. Only JPEG, HEIC, TIFF and PSD (by content type, like rotate); others show "The date taken
   can be changed in JPEG, HEIC, TIFF and PSD files only". The info panel refreshes. If M13's grid is
   in main when Task 6 runs, the same item acts on the grid's selection the way Photos does: the
   first selected file gets the adjusted date, the others shift by the same amount; one failure never
   stops the rest.
9. **Preview and report for many outputs.** The output caption reads "Output 800 × 450 · 4 files"
   (the size of each part; the first frame's for frames); with Tiles on, the output picture shows the
   tile edges as thin lines. The names list shows each input's parts in order (the first five names
   in all, as now). The log line for a multi-output input reads
   "loop.gif → loop-01.png … loop-12.png (12 files)"; the done sentence becomes "47 of 48 images
   converted into 530 files in …" whenever outputs outnumber converted inputs; "MB out" and Show in
   Finder count every part. A row's done state shows the first output's name.

## Spike facts (macOS 27, own test files; don't re-measure)

- `CGImageDestinationCopyImageSource(dest, source, [kCGImageDestinationDateTime: "yyyy:MM:dd HH:mm:ss"])`
  sets EXIF `DateTimeOriginal` and `DateTimeDigitized`, TIFF `DateTime`, XMP `xmp:CreateDate`,
  `photoshop:DateCreated` and `xmp:ModifyDate` in one go, creating them when missing, for **JPEG,
  HEIC, TIFF and PSD**. Decoded pixels are bit-identical afterwards (JPEG and HEIC too, so no
  re-encode); orientation, GPS, lens and other EXIF stay; a 12 MP JPEG takes 1 ms, HEIC 4 ms,
  a 48 MB TIFF 21 ms. Works with `CGImageDestinationCreateWithData` too.
- Pass the date as that string, not a `CFDate`: a `CFDate` is written as UTC (`+00:00` in XMP, the
  EXIF wall time in UTC).
- `kCGImageDestinationDateTime` can't be combined with `kCGImageDestinationMetadata` (OSStatus 4).
  Merging an EXIF date through `kCGImageDestinationMetadata` instead is unreliable: HEIC keeps its old
  EXIF date with merge on, TIFF changes only some fields, and it writes EXIF-style strings into XMP.
- TIFF loses EXIF `OffsetTimeOriginal` and `SubsecTimeOriginal` in any lossless rewrite (all variants
  tried); JPEG, HEIC and PSD keep them. Multi-page TIFF: page 1's date changes, all pages stay.
- Refused for lossless metadata change ("not supported for lossless metadata modification"): AVIF,
  JPEG 2000, GIF, BMP, TGA, OpenEXR, HEICS. Camera RAW and DNG aren't writable at all.
- PNG accepts the call but whether EXIF changes depends on how the file stores it (an `eXIf` chunk
  with GPS: unchanged by either method; XMP-only: changed). So PNG is not offered.
- Animated PNG keeps all frames through `CopyImageSource`.

## Global Constraints

- macOS 14.0 minimum; Swift 6 strict concurrency; no new dependency.
- Never lose user data: never overwrite existing files in batch output (" 2" suffix rule, per part);
  in-place date change writes a temp file and swaps it in; one bad file never stops a batch; a failed
  input leaves no output and no temp file.
- Performance budgets in `AGENTS.md` hold; nothing here touches browsing. Batch memory stays bounded
  (Decision 5).
- Colours, sizes, durations only from `Theme.swift`; leading/trailing, never left/right.
- Every user-facing string translatable, whole sentences with placeholders, plural variations for
  counts; new strings get all 30 languages (`scripts/strings.sh`, then the shared steps in
  `docs/superpowers/plans/2026-10-18-milestone-6-languages.md` "Translation tasks (5–10)").
- User-facing errors are short sentences naming the file.
- Test images come from `Fixtures`, never committed binaries.
- Conventional commits, no AI attribution, no dates in docs or comments; `shortcut:` comments as
  `shortcut: <limit>, <when to upgrade>`.

## Review Focus

- A second run into the same folder (or two inputs `a.gif` and `a.tif`) must never overwrite an
  earlier part: `a-01.png` exists → `a-01 2.png`. Pinned in Task 2 (`partsClashGetSuffixes`) and
  Task 4 (`secondRunNeverOverwritesParts`).
- A frame that fails half-way (truncated GIF, frame 5 of 9 unreadable): no part of that input stays
  in the folder, no hidden temp either, and the counter goes to the next input. Pinned in Task 4
  (`failedPartLeavesNothing`, `commitFailureRemovesMovedParts`).
- Shifting by +1 hour across the spring daylight-saving change, or −1 day from 1 March of a leap
  year: plain wall-time arithmetic (`2026:03:29 01:30:00` + 1 h = `02:30:00` in Europe/Berlin).
  Pinned in Task 3 (`shiftIgnoresDaylightSaving`, `shiftAcrossLeapDay`).
- Adjusting the date of a PNG, a GIF, a read-only JPEG or a symlink: the original stays
  byte-identical except for the symlink case (its target changes, the link stays a link). Pinned in
  Task 3 (`unsupportedLeavesFileUntouched`, `readOnlyLeavesFileUntouched`, `symlinkChangesTarget`).
- A 300-page PDF or a 500-frame GIF: one part in memory per worker, parts on disk. Pinned in Task 4
  (`partsAreOnDiskBeforeCommit`: `Prepared` holds temp URLs, not data), measured in Task 7.

---

## Wave plan

| Wave | Tasks | Why |
|---|---|---|
| A | 1, 2, 3 | independent Core pieces: settings and cards; tiles, parts and names; `DateTaken` |
| B | 4, 6 | the converter (uses 1, 2, 3); the viewer's Adjust Date Taken (uses 3) |
| C | 5 | the batch window (uses 1, 2, 4) |
| D | 7 (main session) | screen check, measurements, spec / parity / roadmap / README |

---

### Task 1: Settings and cards for the three steps

**Files:**
- Modify: `Sources/FeatherviewCore/Batch/BatchSettings.swift`, `Sources/FeatherviewCore/Batch/BatchSteps.swift`
- Test: `Tests/FeatherviewCoreTests/Batch/BatchSettingsTests.swift`, `Tests/FeatherviewCoreTests/Batch/BatchStepsTests.swift`

**Interfaces:**
- Produces:
  - `public struct FramesSettings: Codable, Equatable, Sendable { public var isOn = false }`
  - `public struct TilesSettings: Codable, Equatable, Sendable { isOn = false; columns = 2; rows = 2; overlap = 0 }`
    (columns, rows 1…100; overlap pixels, may be negative)
  - `public enum DateTakenMode: String, Codable, Sendable, CaseIterable { case set, shift }`
  - `public struct DateTakenSettings: Codable, Equatable, Sendable { isOn = false; mode = DateTakenMode.shift;
    setTo = "" /* "yyyy:MM:dd HH:mm:ss" wall time, empty = not chosen */; shiftSeconds = 0 /* signed */ }`
  - `BatchSettings.frames`, `.tiles`, `.dateTaken`; `public var splits: Bool { frames.isOn || tiles.isOn }`;
    `copiesUnchanged` becomes `!changeFormat && !hasOperations && !splits` (`hasOperations` unchanged:
    it means "pixels change"). Tolerant decoding for all three, like the other settings.
  - `BatchCard` cases `.frames`, `.tiles`, `.dateTaken`; `extras` = `[.frames, .crop, .orientation,
    .colour, .filters, .canvas, .border, .text, .watermark, .tiles, .dateTaken]`; processing order
    `[.frames, .crop, .size, …, .watermark, .tiles, .dateTaken]`.
  - Titles: "Frames and Pages", "Tiles", "Date Taken". Summaries: "Every frame or page";
    "\(columns) × \(rows)" or "\(columns) × \(rows), overlap \(overlap) px"; "Set to \(date)" (the
    wall time formatted `.abbreviated` date, `.shortened` time, time zone GMT) or "Choose a date"
    when `setTo` is empty; "Later by \(duration)" / "Earlier by \(duration)" (`Duration.formatted(.units(allowed:
    [.days, .hours, .minutes, .seconds], width: .abbreviated))`), "No shift" for 0. Applied-line
    names: "frames and pages", "tiles", "date taken".

- [ ] **Step 1: Write the failing tests:** `BatchSettingsTests.newStepsDefaultOff`;
  `oldPresetLoadsWithStepsOff` (a stored settings JSON without the keys decodes with defaults);
  `wrongTypedTilesFallBack` (`"columns": "x"` → 2); `splitsAreNotCopies` (Change format off,
  frames on → `copiesUnchanged == false`; date taken on alone → still `true`, Task 4 rewrites the
  date losslessly). `BatchStepsTests.extrasOrder` (menu order above);
  `appliedLineOrder` (frames, crop, tiles, date on → "Applied: frames and pages → crop → tiles → date taken");
  `tilesSummary` ("3 × 2", "3 × 2, overlap 20 px"); `dateSummaries` (`setTo` "2024:07:01 18:30:00" →
  contains "2024"; shift −5400 → starts with "Earlier by"; 0 → "No shift"); `addAndRemove`
  (`setAdded` toggles each `isOn`).
- [ ] **Step 2: Run** `swift test --filter "BatchSettingsTests|BatchStepsTests"` → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `swift test --filter "BatchSettingsTests|BatchStepsTests"` → PASS.
- [ ] **Step 5: Commit** `feat: batch settings and cards for frames, tiles and date taken`

---

### Task 2: Tile geometry, part labels and `{part}` names

**Files:**
- Create: `Sources/FeatherviewCore/Batch/SplitSteps.swift`
- Modify: `Sources/FeatherviewCore/Batch/RenamePattern.swift`, `Sources/FeatherviewCore/Batch/BatchNamer.swift`
- Test: `Tests/FeatherviewCoreTests/Batch/SplitStepsTests.swift`, `BatchNamerTests.swift`

**Interfaces:**
- Produces:
  - `public enum TileStep` — `static func rects(width: Int, height: Int, columns: Int, rows: Int,
    overlap: Int) throws -> [CGRect]` (row-major, top row first, origin top-left in pixel space,
    Decision 3; columns and rows clamped to 1…100; throws `TileError.nothingLeft` when a tile would be
    under 1 px); `static func cut(_ image: CGImage, columns: Int, rows: Int, overlap: Int) throws -> [CGImage]`
    (`CGImage.cropping(to:)`).
  - `public enum TileError: Error { case nothingLeft }`
  - `public enum PartLabels` — `static func frames(_ count: Int) -> [String]` (`["1"]` … padded,
    Decision 4); `static func tiles(rows: Int, columns: Int) -> [String]`;
    `static func combined(frames: Int, rows: Int, columns: Int) -> [String]` (frame-major; frames
    count 1 → tile labels alone; 1 × 1 tiles → frame labels alone; both 1 → `[]`).
  - `RenamePattern.baseName(original:index:date:part:)` — `part: String?` (default nil): replaces
    `{part}`; nil replaces it with `1`. Appending `-{part}` is the namer's job, not the pattern's.
  - `public static func BatchNamer.folder(for input: BatchInput, settings: BatchSettings) -> URL`
    (the instance method calls it; prepare needs the folder without a namer).
  - `public mutating func BatchNamer.names(for input: BatchInput, date: Date?, parts: [String]) -> [URL]` —
    one counter step for the input; `parts` empty → one URL exactly as `next` gives today (`next`
    calls it); else one URL per part, `-{part}` appended to the base when the pattern lacks
    `{part}`; each name goes through today's clash rules and `taken` set.

- [ ] **Step 1: Write the failing tests:**
  - `evenTiles` (1600 × 900, 2 × 2, 0 → four 800 × 450 rects at x 0/800, y 0/450);
  - `oddWidthEqualTiles` (1601 wide, 2 columns → both 801 wide, x 0 and 800, the last ends at 1601);
  - `overlapShared` (1000 wide, 3 columns, overlap 50 → w 367, x 0, 317, 633 (`rounded()`); last ends at 1000);
  - `negativeOverlapLeavesGaps` (1000, 2 columns, −100 → w 450, x 0 and 550);
  - `tooMuchNegativeOverlapThrows` (100 wide, 4 columns, −40 → `nothingLeft`);
  - `oneByOneIsWholeImage`; `cutTopLeftIsTopLeft` (an image whose top-left quarter is red → tile 0's
    pixels red, tile 3's not);
  - `frameLabelsPad` (9 → "1"…"9"; 12 → "01"…"12"; 120 → "001"); `tileLabels` (2 × 3 →
    ["1-1","1-2","1-3","2-1","2-2","2-3"]; 12 columns → "1-01"); `combinedLabels` (3 frames × 2 × 1 →
    ["1-1-1","1-2-1",…]).
  - `BatchNamerTests.partsAppendedWhenPatternLacksPart` (`{name}`, parts ["01","02"] → `a-01.jpg`,
    `a-02.jpg`); `explicitPartPlaceholder` (`{part}_{name}` → `01_a.jpg`); `singleOutputHasNoSuffix`
    (parts [] → `a.jpg`; pattern `{name}_{part}` → `a_1.jpg`); `counterCountsInputs`
    (`{n}` with inputs a (2 parts), b → `1-01`, `1-02`, `2`); `partsClashGetSuffixes` (`a-01.jpg` exists
    → `a-01 2.jpg`, `a-02.jpg`; inputs `a.gif` and `a.tif` both with parts into one folder → the second's
    become `a-01 2.jpg`, `a-02 2.jpg`); `staticFolderMatchesInstance`.
- [ ] **Step 2: Run** `swift test --filter "SplitStepsTests|BatchNamerTests"` → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the same filter → PASS.
- [ ] **Step 5: Commit** `feat: tile geometry, part labels and {part} in output names`

---

### Task 3: `DateTaken` — read, shift, rewrite losslessly, apply in place

**Files:**
- Create: `Sources/FeatherviewCore/Imaging/DateTaken.swift`
- Modify: `Sources/FeatherviewCore/Imaging/ImageEncoder.swift` (`dateTaken:` parameter)
- Test: `Tests/FeatherviewCoreTests/Imaging/DateTakenTests.swift`, `ImageEncoder` cases in
  `Tests/FeatherviewCoreTests/Imaging/OutputFormatTests.swift` (where `ImageEncoder.encode` is tested today)

**Interfaces:**
- Produces:
  - `public enum DateTakenError: Error, Equatable { case unsupportedFormat, unreadable, writeFailed }`
  - `public enum DateTaken`:
    - `static let supported: [UTType]` = `.jpeg`, `.heic`, `.tiff`, `com.adobe.photoshop-image`
      (content type via `CGImageSourceGetType`; `public.heics` does not conform to `.heic`).
    - `public static func original(of url: URL) -> String?` — EXIF `DateTimeOriginal` as stored,
      nil when missing or a placeholder (`MetadataReader.exifDate` decides).
    - `public static func current(of url: URL) -> String?` — `original` ?? the modification date's wall
      time in the Mac's time zone (Decision 7); nil when neither.
    - `public static func wallTime(_ exif: String) -> Date?` / `public static func exif(_ wallTime: Date) -> String`
      — a wall time held as a `Date` in GMT (what the date picker shows with `\.timeZone` = GMT).
    - `public static func shifted(_ exif: String, by seconds: Int) -> String?`
    - `public static func instant(_ exif: String, offset: String?) -> Date?` — for file dates (Decision 7).
    - `public static func rewritten(_ url: URL, date: String) throws -> Data` — `CopyImageSource` into
      a data destination with `kCGImageDestinationDateTime: date`; then reads `DateTimeOriginal` back
      from the data and throws `.unsupportedFormat` unless it equals `date` (never claim a change that
      didn't happen). Not in `supported`, no destination, or `CopyImageSource` false → `.unsupportedFormat`;
      no source → `.unreadable`.
    - `public static func apply(_ link: URL, date: String) throws` — resolves symlinks, `rewritten`,
      writes `.featherview-<uuid>.<ext>` next to it, `replaceItemAt` (as `OrientationRotator.rotate`),
      then sets `.creationDate` and `.modificationDate` to `instant(date, offset: OffsetTimeOriginal)`.
      Any failure leaves the original untouched (`.writeFailed`).
    - `public static func setFileDates(_ url: URL, date: String, offset: String?)` — used by `apply` and
      the converter's commit.
  - `ImageEncoder.encode(…, dateTaken: String? = nil)` — when set, the ImageIO path puts `date` into
    EXIF `DateTimeOriginal`, `DateTimeDigitized` and TIFF `DateTime` of the properties, also with "keep
    metadata" off (Decision 6). Own encoders (WebP, QOI, PCX, Netpbm) and PDF ignore it.

- [ ] **Step 1: Write the failing tests** (fixtures via `Fixtures.writeImage(…, properties:)` with an
  EXIF dictionary; pixels compared by decoding both into the same RGBA buffer):
  - `rewriteKeepsPixelsAndMetadata` for JPEG, HEIC, TIFF, PSD: new `DateTimeOriginal` and
    `DateTimeDigitized`, decoded pixels identical, orientation 6 and GPS kept;
  - `rewriteCreatesMissingDate` (JPEG without EXIF date → has it);
  - `heicSequenceAndOthersRefused` (APNG, HEICS, GIF, PNG, AVIF, BMP → `.unsupportedFormat`);
  - `pngNamedJpgRefused` (content, not extension);
  - `shiftIgnoresDaylightSaving` (with `TimeZone` Europe/Berlin set for the test's formatting:
    `shifted("2026:03:29 01:30:00", by: 3600) == "2026:03:29 02:30:00"`);
    `shiftAcrossLeapDay` (`"2024:03:01 10:00:00"`, −86400 → `"2024:02:29 10:00:00"`);
    `shiftAcrossYear` (`"2025:12:31 23:59:59"`, +1 → `"2026:01:01 00:00:00"`);
  - `wallTimeRoundTrips` (`exif(wallTime(s)!) == s`);
  - `instantUsesOffset` (`instant("2024:07:01 12:00:00", offset: "+02:00")` == 10:00 UTC);
    `instantWithoutOffsetUsesLocalZone`;
  - `currentFallsBackToFileDate` (no EXIF, modification date set → its local wall time);
  - `applyChangesInPlaceAndFileDates` (JPEG: new date read back, modification and creation date == `instant`);
  - `unsupportedLeavesFileUntouched` (PNG and GIF: bytes and modification date unchanged, throws);
  - `readOnlyLeavesFileUntouched` (folder made read-only: throws `.writeFailed`, bytes unchanged);
  - `symlinkChangesTarget` (link → JPEG: the target's date changes, the link is still a link);
  - `encodeWritesDateTaken` (JPEG and PNG output with `dateTaken`, `keepMetadata` off → the date reads back).
- [ ] **Step 2: Run** `swift test --filter "DateTakenTests|OutputFormatTests"` → FAIL.
- [ ] **Step 3: Implement.** Add a `shortcut:` comment on the TIFF rewrite: TIFF drops
  `OffsetTimeOriginal` and `SubsecTimeOriginal` (ImageIO), upgrade when ImageIO keeps them or someone asks.
- [ ] **Step 4: Run** `swift test --filter "DateTakenTests|OutputFormatTests|MetadataReaderTests|OrientationRotatorTests"` → PASS.
- [ ] **Step 5: Commit** `feat: set and shift the date taken losslessly`

---

### Task 4: The converter writes many outputs per input and the date

**Files:**
- Modify: `Sources/FeatherviewCore/Batch/BatchConverter.swift`, `Sources/FeatherviewCore/Batch/BatchJob.swift`
  (`BatchResult.outputs`, `logLine`), `Sources/FeatherviewCore/Batch/BatchReport.swift`,
  `Sources/FeatherviewCore/Batch/BatchSteps.swift` (`rowState`),
  `Sources/FeatherviewCore/Imaging/FrameSource.swift` (sync reader, below)
- Test: `Tests/FeatherviewCoreTests/Batch/BatchConverterTests.swift`, `BatchReportTests.swift`,
  `Tests/FeatherviewCoreTests/Imaging/FrameSourceTests.swift` (unchanged, must pass)

**Interfaces:**
- Consumes: `FramesSettings`, `TilesSettings`, `DateTakenSettings`, `splits` (Task 1); `TileStep.cut`,
  `TileError`, `PartLabels`, `BatchNamer.names(for:date:parts:)`, `BatchNamer.folder(for:settings:)` (Task 2);
  `DateTaken.current`, `.shifted`, `.rewritten`, `.setFileDates`, `ImageEncoder.encode(…dateTaken:)` (Task 3);
  `Animation.read`, `FrameSource` (M9).
- Produces:
  - `public final class FrameReader` (not `Sendable`; one thread) — `init(url: URL, target: DecodeTarget,
    colorSpace: CGColorSpace?) throws`, `func frame(_ index: Int) throws -> CGImage`: `FrameSource`'s
    current body moved here; `FrameSource` keeps its API and holds one (`frame` forwards). The batch
    uses `FrameReader(url:, target: .full, colorSpace: nil)` from its sync worker.
  - `BatchResult.outputs: [URL]` (stored; in order); `output` becomes `outputs.first`; the existing
    `init(input:output:status:message:)` stays, plus `init(input:outputs:status:message:)`.
  - `BatchResult.logLine` for `outputs.count > 1`: "\(name) → \(first) … \(last) (\(count) files)", with
    " · \(message)" as today when there is a message.
  - `BatchReport.summary(results:seconds:bytesIn:bytesOut:folder:)` uses the "converted into \(files)
    files" sentences (both folder variants) when the outputs outnumber converted inputs.
  - `BatchProgress.rowState`: `.done(first output's name)`.

Rules in `prepare` (all names via Decision 4; nothing here writes a final name):
- `let parts`: frames on and `Animation.read(url)` non-nil → frame indices via one `FrameReader`;
  frames on and `pageCount > 1` → page indices via `ImageDecoder.decode(url, maxPixelSize: limit, page:)`;
  else today's `pages` (page 1, or all pages for TIFF-keep-all / PDF when frames is off).
- The own-format check ("Can't save … in its own format") drops its page-count condition when frames
  is on (each output is one page).
- Each part: pipeline as today (`TextValues.index` is still the list place), then tiles when on
  (`TileError.nothingLeft` → "\(name): the tile settings leave no image"), then encode with
  `dateTaken`, then `write` to `.featherview-<uuid>.tmp` in `BatchNamer.folder(for:settings:)`
  (created if missing). `Prepared.parts: [(file: URL, label: String)]` replaces `data` when the
  input gives more than one output; one output keeps today's `data` path, so single-file runs
  don't change. On any error: remove the temps written so far and return the error.
- Date step: `new` = set → `setTo` (empty → the input fails with "Choose a date for the Date Taken
  step"), shift → `DateTaken.shifted(DateTaken.current(of: url), by:)`; `Prepared.date` (for `{date}`)
  = `MetadataReader.exifDate(new)`; text overlay `{date}` uses it too. `copiesUnchanged` with the date
  step: `data = try DateTaken.rewritten(url, date: new)`, failure → "Can't change the date taken of \(name)".
- `commit`: `namer.names(for:date:parts:)`; per part today's replace-existing trash and
  `moveExclusive` loop (factor today's `write` into "move this temp file in without replacing");
  a failure removes the parts already moved for this input, restores the namer and fails the input.
  `keepDates` per output; the date step's `DateTaken.setFileDates` instead when on.

- [ ] **Step 1: Write the failing tests** (`run` with the real `prepare`, temp folders; GIF fixtures
  from `Fixtures.writeAnimatedGIF`, TIFF from `writeMultiPageTIFF`):
  - `framesOfGIF` (3 frames → `a-1.png`, `a-2.png`, `a-3.png`, each the frame's colour, full size);
  - `pagesOfTIFFToJPEG` (3 pages → 3 JPEGs, no "page 1 of 3" note); `pdfOutputGetsOnePagePerFile`;
  - `stillWithFramesStepIsOneOutput` (`a.jpg`, no suffix);
  - `tilesOfStill` (1600 × 900 → 4 files 800 × 450 named `a-1-1` … `a-2-2`, top-left tile red);
  - `tilesOfMultiPageKeepNote` (frames off → tiles of page 1, message "page 1 of 3");
  - `framesAndTiles` (2 frames × 2 × 1 → 4 files `a-1-1-1` … in order);
  - `counterSharedByParts` (`img-{n}` with a 2-frame and a still input → `img-1-1`, `img-1-2`, `img-2`);
  - `failedPartLeavesNothing` (GIF cut after frame 2 of 4 → failed, folder holds no file of it and no
    `.featherview-*.tmp`; the next input gets `{n}` = 1);
  - `commitFailureRemovesMovedParts` (`moveExclusive` seam fails on the second part → the first part
    is gone, result failed);
  - `secondRunNeverOverwritesParts` (run twice → second run's files `a-1 2.png` …, first run's bytes unchanged);
  - `partsAreOnDiskBeforeCommit` (a `prepare` result for a 3-frame input has 3 temp files and `data == nil`);
  - `keepFormatSplitsPDF` (Change format off, frames on, 2-page PDF → two one-page PDFs);
  - `dateSetOnReencode` (JPEG → PNG, set "2020:02:03 04:05:06" → read back; file modification date ==
    `DateTaken.instant`; with "Keep file dates" on too, the date step wins);
  - `dateShiftLosslessCopy` (Change format off, no step, shift +3600 → pixels identical to the input,
    date +1 h, input untouched);
  - `dateOnGIFCopyFails` ("Can't change the date taken of a.gif", batch goes on);
  - `dateRenamesByNewDate` (pattern `{date}`, set 2020-02-03 → `2020-02-03.jpg`);
  - `BatchReportTests.summaryCountsFiles` ("2 of 2 images converted into 5 files in …");
    `logLineForManyOutputs`; `rowStateShowsFirstOutput`.
- [ ] **Step 2: Run** `swift test --filter "BatchConverterTests|BatchReportTests|BatchStepsTests"` → FAIL.
- [ ] **Step 3: Implement**, then `scripts/strings.sh`; new strings in all 30 languages (shared
  translation steps; the "(\(count) files)" and "converted into \(files) files" keys get plural variations).
- [ ] **Step 4: Run** `swift test` → all PASS (FrameSourceTests and every batch suite unchanged).
- [ ] **Step 5: Commit** `feat: batch writes every frame, page or tile, and sets the date taken`

---

### Task 5: The batch window — cards, preview, report

**Files:**
- Modify: `Sources/Featherview/Batch/BatchStepViews.swift` (three card bodies; `{part}` placeholder button),
  `Sources/Featherview/Batch/BatchCards.swift` (adding Date Taken seeds `setTo`),
  `Sources/Featherview/Batch/BatchPreview.swift` (names with parts, caption, tile lines),
  `Sources/Featherview/Batch/BatchModel.swift` (bytes out and last written over all `outputs`),
  `Sources/Featherview/Design/Theme.swift` (`tileLine` stroke colour and width, if no existing token fits)

**Interfaces:**
- Consumes: Task 1's settings and `BatchCard` cases; `PartLabels`, `TileStep.rects`, `BatchNamer.names` (2);
  `BatchResult.outputs` (4); `DateTaken.current`, `.wallTime`, `.exif` (3); `Animation.read`,
  `ImageDecoder.pageCount`.

UI (grouped form rows like the other cards, labels leading, controls trailing):
- **Frames and Pages:** one line of secondary text: "Each frame of an animation and each page of a
  document becomes its own file." No controls.
- **Tiles:** Columns and Rows (integer field + stepper, 1…100), Overlap (integer field, "px" suffix,
  −9999…9999, help "Negative values leave gaps"). Order of tiles is not configurable.
- **Date Taken:** segmented Picker "Set to" / "Shift"; set: `DatePicker` (`[.date, .hourMinuteAndSecond]`)
  bound through `DateTaken.wallTime` / `.exif`, with `.environment(\.timeZone, GMT)`; shift: Picker
  "Later" / "Earlier" and four integer fields Days (0…3650), Hours, Minutes, Seconds (0…59 / 0…23),
  stored as signed `shiftSeconds`. Help line: "Changes the converted files, not the originals."
- Adding Date Taken from the menu with `setTo` empty seeds it with `DateTaken.current` of the selected
  (or first) input, off the main thread, else now.
- Name card: the `{part}` placeholder button appears while `settings.splits`.
- Preview (Decision 9): `NamesKey` names computed with each input's labels (`PartLabels.combined` from
  `Animation.read(url)?.frameCount ?? pageCount(of:)` when frames is on, and tiles' rows / columns),
  still the first five names in all, "… N more" counting names; the output caption
  "Output \(w) × \(h) · \(n) files" (plural) when an input yields more than one; with Tiles on, the
  output picture draws `TileStep.rects` of the output size, scaled to the shown picture, as 1-pt lines
  in a Theme colour; a `TileError` shows "The tile settings leave no image" in place of the pictures,
  as the canvas error does.
- Run and done views: unchanged code paths; `bytesOut` sums every output, `lastWritten` is the last
  output of the last converted result.

- [ ] **Step 1:** Implement; `swift build`; `scripts/bundle.sh debug`.
- [ ] **Step 2:** `scripts/strings.sh`; the new strings in all 30 languages (shared translation steps;
  the caption's file count with plural variations).
- [ ] **Step 3:** `swift test` → all PASS.
- [ ] **Step 4: Commit** `feat: batch window cards and preview for frames, tiles and date taken`

---

### Task 6: Adjust Date Taken… in the viewer

**Files:**
- Create: `Sources/Featherview/Viewer/AdjustDateSheet.swift`
- Modify: `Sources/Featherview/Viewer/ViewerModel.swift` (`adjustDateTaken`), `Sources/Featherview/Viewer/ViewerView.swift`
  (Image menu item after "Rotate Left  (L)"; `ImageContextMenu` item after "Rotate Right"; the sheet)

**Interfaces:**
- Consumes: `DateTaken.original`, `.current`, `.wallTime`, `.exif`, `.apply`, `DateTakenError` (Task 3).
- Produces: `ViewerModel.adjustDateTaken(to date: String)`; `ViewerModel.dateSheet: DateSheetState?`
  (`url`, `original: String?`, `fileDate: String?`) set by `showAdjustDate()`, read off the main thread.

Rules (Decision 8):
- Menu "Adjust Date Taken…", disabled when `availability.canChangeFile` is false; same item in the
  context menu after Rotate Right.
- Sheet: title "Adjust Date Taken"; "Original" row: the original formatted (`.abbreviated`, `.standard`
  time, GMT) or "None, file date \(date)"; "Adjusted" `DatePicker([.date, .hourMinuteAndSecond])` in GMT,
  starting at `current`; line "The file's date changes too."; Cancel (Esc) and **Adjust** (Return,
  default; disabled while unchanged).
- `adjustDateTaken` runs `DateTaken.apply` detached; then `knownInfo[url] = nil`, `fileRevision += 1`
  (the info panel and the status bar date refresh); no image reload. Errors: `.unsupportedFormat` →
  "The date taken can be changed in JPEG, HEIC, TIFF and PSD files only"; else "Can't change the date
  taken of \(name)".
- M13 grid: run `ls Sources/Featherview/Grid 2>/dev/null`. If it exists, the item is also enabled while
  the grid shows with a selection: the sheet starts from the first selected file, the "Original" row
  adds "and \(count − 1) more" (plural), and Adjust applies the adjusted date to the first and
  `DateTaken.shifted(current(other), by: delta)` to each other file (delta in seconds between adjusted
  and the first's current); failures collected into one message naming the file when one failed, else
  "\(count) files couldn't be changed". If it doesn't exist, skip this rule.

- [ ] **Step 1:** Implement; `swift build`; `scripts/bundle.sh debug`.
- [ ] **Step 2:** `scripts/strings.sh`; new strings in all 30 languages (shared translation steps).
- [ ] **Step 3:** `swift test` → all PASS.
- [ ] **Step 4: Commit** `feat: adjust the date taken of the viewed image`

---

### Task 7: Screen check, measurements, docs (main session, screen)

Needs the maintainer's go (screen bursts). Sample folder in the scratchpad: Task 4's fixtures
written by a small script, plus a 60-frame 1600 × 1200 GIF, a 300-page PDF (`cupsfilter` or
`/System/Library/Printers/Libraries/convert` from a long text file), 20 12 MP JPEGs with EXIF dates,
a 4:1 panorama JPEG.

- [ ] **Step 1: Check by hand** (release build): each card's controls, summaries, Add Step order and
  removal; the preview's names, "· 4 files" caption and tile lines while changing columns, rows and
  overlap (negative too); a run with frames of the GIF and the PDF, tiles of the panorama, both
  together; a second run into the same folder (" 2" names, nothing overwritten); Stop during the
  300-page PDF (it finishes, no `.featherview-*.tmp` left: `ls -a`); the log lines and done sentence;
  Show in Finder; Date Taken set and shift on JPEG → PNG and on a keep-format run (lossless: compare
  `shasum` of the decoded pixels with `sips -s format bmp`); the viewer's Adjust Date Taken… on a
  JPEG, a HEIC and a PNG (message), info panel refresh, Finder's dates; right-to-left (Arabic) layout
  of the three cards and the sheet; the grid's selection if Task 6 wired it.
- [ ] **Step 2: Measure:** memory (Activity Monitor) during the 300-page PDF and the 60-frame GIF
  runs: stays near a normal batch's; time for 20 JPEGs' lossless date shift.
- [ ] **Step 3: Docs:** spec "Batch window" (Add Step menu lists eleven steps), "Output" (replace "No
  file per page." with the Frames and Pages step and the `{part}` naming of Decision 4), "Per-image
  operations" (frames first, tiles and date taken last; Decisions 2, 3, 6, 7), "Safety and options"
  (one input's outputs are one unit, Decision 5), "Menu commands" (Adjust Date Taken…, Decision 8),
  "Window" (preview and report wording, Decision 9); `docs/parity.md` "Batch extras" rows: Extract
  frames, Split into tiles, Date taken → `v2` with our behaviour in the Featherview column; roadmap row
  16 → this plan, `done`; README features line.
- [ ] **Step 4: Commit** `docs: batch extras done after manual QA`
