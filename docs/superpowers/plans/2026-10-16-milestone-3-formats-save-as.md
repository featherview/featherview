# Featherview v1 — Milestone 3 Implementation Plan (formats and Save As)

> **Milestone 3** in `docs/roadmap.md`. Builds on milestone 2 (`2026-10-16-milestone-2-viewer-complete.md`,
> done). WebP output is milestone 5, the full batch window milestone 4, layered app formats
> milestone 7, Finder previews milestone 8, the "own look" design pass later (roadmap). Don't add them here.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. In this repo, run it wave by wave with the `plan-wave` workflow.

**Goal:** Read every format the spec lists (own decoders, SVG, PDF pages), write every format the
spec lists with its options, Save As from the viewer, the About window, HDR display, a status bar,
Liquid Glass panels, a toolbar fast enough for the 16 ms swap budget, and Finder's Open With for
every readable format.

**Architecture:** Formats live in `FeatherviewCore`. Reading: an `OwnDecoders` registry of
`OwnFormat`s (pure-Swift decoders plus PDF pages through Core Graphics) that `ImageFormats` and
`ImageDecoder` consult before ImageIO, so own formats go through the same cache, prefetch, page
and batch paths. Writing: `FormatRegistry` builds `OutputFormat`s at runtime from
`CGImageDestinationCopyTypeIdentifiers()` plus our encoders; `ImageEncoder` turns upright pages
into bytes with `FormatOptions`; `ImageSaver` (Save As) and `BatchConverter` share it;
`FormatSettings` remembers options and profiles per format. The app gets one shared
`FormatOptionsView` (Save As accessory, batch window, Settings › Formats), an About window, a status
bar, the SVG decoder (AppKit, registered at launch), HDR layer flags and `Info.plist` type
declarations.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI + AppKit, ImageIO, Core Graphics (PDF),
Swift Testing, SwiftPM. No third-party dependencies.

**Spec:** `docs/spec.md` sections "Formats", "Format options", "Viewer" (status bar, Liquid Glass,
window title), "Menu commands" (Save As), "About window", "Settings" (Formats tab), "Batch window"
(Output format only). Rules, budgets and commands: `AGENTS.md`. Observed behaviour behind the
decisions: `docs/parity.md` ("Formats and options", "Display"). Read all three first.

## Global Constraints

- macOS 14.0 minimum. APIs newer than 14 need `if #available` and a 14 fallback (Liquid Glass: 26;
  `CALayer.preferredDynamicRange`: 26; HDR decode for display: 15 per spec).
- Bundle ID and log subsystem `net.mynetx.featherview`. Never rename a `UserDefaults` key or an
  `OutputFormat.id` once shipped (ids are stored).
- No third-party dependencies. No `.xcodeproj`. `FeatherviewCore` never imports SwiftUI or AppKit
  (SVG therefore lives in the app target).
- Clean room (`AGENTS.md`): decoders and encoders from public format specifications only; our own
  UI text, SF Symbols only, no layouts copied from the reference viewer.
- Never lose data: Save As replaces a file only after the save panel asked and only once the new
  file is completely written; batch never overwrites; one bad file never stops browsing or a batch.
- Decoders never trap on hostile input: every read is bounds-checked (`ByteReader`), sizes go
  through `checkedSize` (at most 65,536 px a side, 256 MP), errors are `OwnDecodeError`, surfaced
  as `DecodeError.unreadable` → "Can't open <name>".
- Decode and encode off the main thread. Folder scans decide by extension only and never open files.
- User-facing text is a SwiftUI literal or `String(localized:)`, never concatenated pieces.
  Layout uses leading/trailing.
- Performance budgets in `AGENTS.md` stay met; this milestone must bring the prefetched swap back
  under 16 ms (Task 15) and Task 16 measures every budget again.
- Commits: conventional commits, no AI attribution lines.

## ImageIO facts (tested on macOS 27, 2026-10-16) — don't rediscover them

- `CGImageDestinationCopyTypeIdentifiers()` lists: jpeg, png, gif, tiff, jpeg-2000, atx, ktx, ktx2,
  astc, dds, heic, heics, avif, ico, bmp, icns, psd, pdf, tga, exr, pbm, pvr. Hidden by decision:
  atx, ktx, ktx2, astc, dds, pvr, heics.
- JPEG: progressive works (`kCGImagePropertyJFIFIsProgressive`). No way to turn chroma subsampling
  off (4:4:4 only at quality 1.0) — option dropped from the spec.
- HEIC at quality 1.0 is not lossless (max pixel diff 2). **AVIF fails to finalize at quality 1.0**;
  0.99 works — cap AVIF at 0.99.
- JPEG 2000 at quality 1.0 is exactly lossless.
- PNG: interlace works (`kCGImagePropertyPNGInterlaceType: 1`); no zlib level exists.
- TIFF compression 1 / 5 / 7 / 8 / 32773 (none, LZW, JPEG, ZIP, PackBits) all write and read back.
- GIF: no interlace key exists.
- ImageIO's PDF ignores quality (always DCT). Write PDF with a `CGContext` PDF context and draw a
  `CGImage(jpegDataProviderSource:)` — Core Graphics embeds the JPEG bytes as is (`/DCTDecode`).
- ICO accepts only squares up to 256 px; ICNS only squares of 16, 32, 128, 256 or 512 px.
- `NSImage(contentsOf:)` renders SVG (`_NSSVGImageRep`) off the main thread fine.
- `CGPDFPage.getDrawingTransform` never scales a page **up** — build the transform yourself.
- HDR: `kCGImageSourceDecodeRequest: kCGImageSourceDecodeToHDR` (macOS 14+ in the SDK) works with
  `CGImageSourceCreateThumbnailAtIndex`. A gain-map JPEG/HEIC comes back 10 bits per component in
  `kCGColorSpaceITUR_2100_PQ`; an SDR JPEG with the same request stays 8 bits. So the request can
  be passed for every image without costing SDR images memory. A gain-map fixture is written by
  encoding a 16-bit float `extendedLinearDisplayP3` image with
  `kCGImageDestinationEncodeRequest: kCGImageDestinationEncodeToISOGainmap` (macOS 15+); it then
  has `kCGImageAuxiliaryDataTypeISOGainMap` auxiliary data.
- `CALayer.wantsExtendedDynamicRangeContent` is macOS 14–25 (deprecated in 26);
  `CALayer.preferredDynamicRange` is macOS 26+.

## Verified draft code

Tasks 1–5 and 7 have a **draft that compiled warning-free and passed** (219 tests, whole suite) on
the local branch `m3-draft` (worktree in the planning session's scratchpad; the branch is in this
repo). Start from it: `git show m3-draft:<path> > <path>`. TDD still applies — bring the test file
first, run it, see it fail, then bring the source. The reviewers still review it like new code:
the draft was tested only on files built byte by byte in tests, never on real-world files.

Known draft behaviours the reviewers should judge, not assume right:
- ILBM / Sun Raster: image data shorter than the image throws `.truncated` (no partial image).
- PCX mono ignores a 2-colour header palette (0 black, 1 white).
- XPM `cpp` limited to 1–8; `grayNN` rounds as (NN·255 + 50) / 100.
- XBM is X10 (16-bit words) if `short` appears before `{`.
- `OwnDecoders.builtIn` in the draft lists every decoder at once; in this plan Task 1 starts it
  empty and each decoder task adds its own entries (see "Merging").

## Merging

Tasks 2–5 each add entries to `OwnDecoders.builtIn` in `Sources/FeatherviewCore/OwnDecoders.swift`.
Each adds one line in its own slot, in this fixed order, so the integrate step's merge is a
trivial union:

```swift
    static let builtIn: [OwnFormat] = [
        // Task 2
        // Task 3
        // Task 4
        // Task 5
    ]
```

Task 1 writes exactly those four comment lines; Task n replaces `// Task n` with its formats
(e.g. `QOICodec.format, PCXCodec.pcx, PCXCodec.dcx,`). Leave the other comments alone.

## Review Focus

1. **Hostile and odd files in the new decoders** — truncated, zero-size, absurd dimensions (0, 70,000,
   width × height overflowing), RLE runs past the buffer, palettes shorter than indices, a `.pcx`
   that is really a JPEG. Expected: "Can't open <name>", no crash, no gigabyte allocation, browsing
   continues. Pinned by each decoder suite's truncated/corrupt tests (Tasks 2–5) and
   `OwnDecodersTests.truncatedFileThrowsUnreadable` (Task 1).
2. **Save As over an existing file, over the source itself, or failing half-way** (disk full,
   unreadable source, read-only folder). Expected: the existing file is replaced only once the new
   one is fully written; a failure leaves it as it was; no temp file left behind. Pinned by
   `ImageSaverTests.replacesOnlyOnceTheNewFileIsWritten` and `savingOverTheSourceWorks` (Task 7);
   read-only folder: Task 13 step.
3. **Option combinations ImageIO rejects** — AVIF at 100, ICO/ICNS of a non-square photo, JPEG
   target size nothing can reach, PDF of a transparent PNG. Expected: a file is still written with
   the nearest allowed result. Pinned by `ImageEncoderTests.avifAtQuality100StillWrites`,
   `iconsFitAnAllowedSquare`, `jpegTargetSizeFitsAndUsesTheHighestQualityThatDoes`,
   `pdfEmbedsJPEGUnlessLosslessOrTransparent` (Task 7).
4. **Stored settings from an older or newer build** — options JSON missing a key, with an unknown
   key, or garbage; a saved format id this Mac can't write (e.g. a format a newer macOS added).
   Expected: defaults for what's missing, the rest kept; an unknown format id falls back to JPEG.
   Pinned by `FormatSettingsTests.damagedOrOldStoredOptionsFallBackToDefaults` (Task 7) and
   `FormatSettingsTests.unknownLastFormatFallsBackToJPEG` (Task 7).
5. **PDFs and DCX in the viewer** — a 300-page PDF, a page past the end, a rotated page, a PDF with
   a password. Expected: opens on page 1 quickly, ⌥→ stops at the last page, rotated pages upright,
   an encrypted PDF shows "Can't open <name>". Pinned by `PDFPagesTests` (Task 5) incl.
   `encryptedPDFIsUnreadable`; big PDF: Task 16 QA.

## Execution order (for plan-wave)

| Wave | Tasks (parallel within a wave) | Needs |
|---|---|---|
| A | 1 | milestone 2 merged |
| B | 2, 3, 4, 5, 6, 8 | wave A |
| C | 7 | tasks 2, 3 (it calls their encoders) |
| D | 9, 10, 11, 12 | 9: 1, 5 · 10: 7 · 11: 7, 8 · 12: 6 |
| E | 13, 14, 15 | 13: 7, 8, 10 · 14: 7, 10 · 15: 8 |
| F | 16 | everything |

---

### Task 1: Own-decoder registry

Spec "Formats": own decoders go through the same paths as ImageIO's (folder listing by
extension, downsampled decode, pages, batch input, info panel).

**Files:**
- Create: `Sources/FeatherviewCore/RGBAImage.swift` (RGBAImage, OwnDecodeError, ByteReader, checkedSize)
- Create: `Sources/FeatherviewCore/OwnDecoders.swift` (OwnFormat, OwnDecoders)
- Modify: `Sources/FeatherviewCore/ImageFormats.swift` (`isDecodable`, `mayHavePages` consult the registry)
- Modify: `Sources/FeatherviewCore/ImageDecoder.swift` (`pageCount`, `displaySize`, `decode` consult it; `scaled`)
- Test: `Tests/FeatherviewCoreTests/OwnDecodersTests.swift`

Draft: commit `74d7972` on `m3-draft` (`git show 74d7972:<path>`). `builtIn` must be the four
comment slots from "Merging", not `[]`.

**Interfaces:**
- Produces:
  - `public struct RGBAImage: Equatable, Sendable { width, height, pixels: [UInt8] /* RGBA, straight alpha, top row first */; init(width:height:pixels:); init(width:height:) /* opaque black */; init?(_ image: CGImage); subscript(x:y:) -> (r,g,b,a); var isOpaque; func makeCGImage() -> CGImage? }`
  - `public enum OwnDecodeError: Error, Equatable { case notThisFormat, truncated, corrupt, unsupported }`
  - `struct ByteReader { init(_ bytes: [UInt8]); init(_ data: Data); var remaining; var isAtEnd; mutating u8(), u16le(), u16be(), u32le(), u32be() throws -> Int/UInt8; take(_:) throws -> ArraySlice<UInt8>; skip(_:) throws }`
  - `func checkedSize(_ width: Int, _ height: Int) throws -> (Int, Int)` (≤ 65,536 a side, ≤ 2²⁸ pixels, > 0)
  - `public struct OwnFormat: Sendable { name, extensions /* lowercase */, hasPages, size: (Data, Int) -> CGSize?, pageCount: (Data) -> Int, decode: (Data, page: Int, maxPixelSize: Int?) throws -> CGImage; static func raster(name:extensions:hasPages:size:pageCount:decode:) -> OwnFormat }` — `raster`'s `decode` returns `RGBAImage`.
  - `public enum OwnDecoders { static let builtIn: [OwnFormat]; public static var all; public static func register(_:) /* replaces a format sharing an extension */; public static func format(for url: URL) -> OwnFormat? /* by extension, case-insensitive */ }`
  - `ImageDecoder.scaled(_ image: CGImage, longestSide: Int) -> CGImage?` (nil if already that small)
- Behaviour: an own format decodes full size, then `ImageDecoder.decode` scales it to `maxPixelSize`
  exactly (no halving steps: those exist for JPEG speed only). Files are read with
  `Data(contentsOf:options: .mappedIfSafe)` so a header read touches only the first pages.

- [ ] **Step 1: Bring the test file, see it fail**

`git show 74d7972:Tests/FeatherviewCoreTests/OwnDecodersTests.swift > Tests/FeatherviewCoreTests/OwnDecodersTests.swift`.
It registers a toy format (`.fvtoy`) and checks: listed and decodable (`a.FVTOY`, extension case
ignored), pages from the format, downsampling to exactly 50 px with `halvingSteps: true`, never
upscaling, truncated file → `DecodeError.unreadable`, registering twice keeps one, `RGBAImage`
round trip through `CGImage` with half alpha, `ByteReader` throws `.truncated` past the end.

Run: `swift test --filter OwnDecodersTests` — Expected: FAIL (types missing).

- [ ] **Step 2: Bring the sources** (`RGBAImage.swift`, `OwnDecoders.swift` with the slot comments,
  and the `ImageFormats` / `ImageDecoder` changes from `74d7972`).

- [ ] **Step 3: Run** `swift test` — Expected: PASS, whole suite.

- [ ] **Step 4: Commit** `feat: own-decoder registry consulted before ImageIO`

---

### Task 2: QOI and PCX/DCX codecs

Spec "Formats": own decoders QOI, PCX (and multi-page DCX); own encoders QOI, PCX.

**Files:**
- Create: `Sources/FeatherviewCore/QOICodec.swift`, `Sources/FeatherviewCore/PCXCodec.swift`
- Modify: `Sources/FeatherviewCore/OwnDecoders.swift` (slot `// Task 2` → `QOICodec.format, PCXCodec.pcx, PCXCodec.dcx,`)
- Test: `Tests/FeatherviewCoreTests/QOICodecTests.swift`, `Tests/FeatherviewCoreTests/PCXCodecTests.swift`

Draft: `adb0150` (QOI), `12ddd32` (PCX/DCX).

**Interfaces:**
- Consumes: Task 1.
- Produces: `QOICodec.format`, `QOICodec.encode(_ image: RGBAImage) -> Data` (public; 4 channels,
  colorspace 0, op order as the spec's reference encoder); `PCXCodec.pcx`, `PCXCodec.dcx`
  (`hasPages: true`), `PCXCodec.encode(_:) throws -> Data` (public; `.unsupported` past 65534 × 65536; version 5, 8 bits, 3 planes, RLE,
  even bytes per line, literal ≥ 0xC0 written as 0xC1 + byte).
- Decoder coverage: QOI 3/4 channels, missing end marker tolerated if every pixel decoded; PCX
  1-bit 1–4 planes, 4-bit 1 plane, 8-bit palette (0x0C 769 bytes from the end, grey without it),
  8-bit 3 planes (RGB), 8-bit 4 planes (RGBA), RLE runs crossing lines and planes, uncompressed
  (encoding 0); DCX page table (≤ 1023 LE offsets, 0-terminated).

- [ ] **Step 1:** Bring both test files from the draft; run `swift test --filter "QOICodecTests|PCXCodecTests"` — FAIL.
- [ ] **Step 2:** Add tests the draft lacks: PCX 8-bit 4-plane (RGBA) and 4-bit 1-plane golden
  pixels; QOI a DIFF op that wraps (e.g. 255 → 0 is +1). Run — FAIL.
- [ ] **Step 3:** Bring both sources; fill slot `// Task 2`. Run `swift test` — PASS.
- [ ] **Step 4: Commit** `feat: QOI and PCX/DCX decoders and encoders`

---

### Task 3: XBM, XPM, WBMP decoders and PGM/PPM encoders

Spec "Formats": own decoders XBM, XPM, WBMP; own encoders PGM, PPM.

**Files:**
- Create: `Sources/FeatherviewCore/XBMDecoder.swift`, `XPMDecoder.swift`, `WBMPDecoder.swift`, `NetpbmEncoder.swift`
- Modify: `Sources/FeatherviewCore/OwnDecoders.swift` (slot `// Task 3` → `XBMDecoder.format, XPMDecoder.format, WBMPDecoder.format,`)
- Test: `Tests/FeatherviewCoreTests/XBMDecoderTests.swift`, `XPMDecoderTests.swift`, `WBMPDecoderTests.swift`, `NetpbmEncoderTests.swift`

Draft: `13ede92`.

**Interfaces:**
- Consumes: Task 1.
- Produces: `XBMDecoder.format` ("XBM", `xbm`), `XPMDecoder.format` ("XPM", `xpm`),
  `WBMPDecoder.format` ("WBMP", `wbmp`), `NetpbmEncoder.pgm(_:) -> Data` and `.ppm(_:) -> Data`
  (public; binary P5/P6, header `"P5\n<w> <h>\n255\n"`, PGM luma `(299r + 587g + 114b + 500) / 1000`).
- XBM: bit 1 black, LSB first, rows padded to bytes; X10 16-bit words. XPM3: `c` key preferred,
  `#RGB` / `#RRGGBB` / `#RRRRGGGGBBBB`, `None` transparent, a small X11 name table (unknown → black).
  WBMP type 0: 1 white, 0 black, MSB first.

- [ ] **Step 1:** Bring the four test files; run — FAIL.
- [ ] **Step 2:** Bring the sources; fill slot `// Task 3`. Run `swift test` — PASS.
- [ ] **Step 3: Commit** `feat: XBM, XPM and WBMP decoders, PGM and PPM encoders`

---

### Task 4: Sun Raster and IFF/ILBM decoders

Spec "Formats": own decoders Sun Raster (RAS), IFF/LBM (ILBM, incl. HAM and EHB).

**Files:**
- Create: `Sources/FeatherviewCore/SunRasterDecoder.swift`, `Sources/FeatherviewCore/ILBMDecoder.swift`
- Modify: `Sources/FeatherviewCore/OwnDecoders.swift` (slot `// Task 4` → `SunRasterDecoder.format, ILBMDecoder.format,`)
- Test: `Tests/FeatherviewCoreTests/SunRasterDecoderTests.swift`, `ILBMDecoderTests.swift`

Draft: `c26402b`.

**Interfaces:**
- Consumes: Task 1.
- Produces: `SunRasterDecoder.format` ("Sun Raster", `ras`, `sun`), `ILBMDecoder.format`
  ("IFF ILBM", `iff`, `lbm`, `ilbm`).
- RAS: depths 1, 8 (RGB planar colormap or grey), 24 (BGR; type 3 RGB), 32 (XBGR / XRGB), rows
  padded to 16 bits, type 2 RLE with the `0x80 0x00` literal escape.
- ILBM: BMHD, CMAP, CAMG (HAM 0x800, EHB 0x80), BODY; 1–8 and 24 planes, ByteRun1, mask plane
  (masking 1) and transparent colour (masking 2) → alpha; HAM6/HAM8; FORM PBM chunky.

- [ ] **Step 1:** Bring both test files; run — FAIL.
- [ ] **Step 2:** Bring the sources; fill slot `// Task 4`. Run `swift test` — PASS.
- [ ] **Step 3: Commit** `feat: Sun Raster and IFF ILBM decoders`

---

### Task 5: PDF pages

Spec "Formats" (decided 2026-10-16): a PDF is browsed like a multi-page image, Core Graphics
renders each page on white at 144 dpi (A4 → 1190 × 1684), fit renders straight at the window's
size, opens on page 1; ⌥← / ⌥→ step pages.

**Files:**
- Create: `Sources/FeatherviewCore/PDFPages.swift`
- Modify: `Sources/FeatherviewCore/OwnDecoders.swift` (slot `// Task 5` → `PDFPages.format,`)
- Modify: `Sources/FeatherviewCore/ImageFormats.swift` (comment only: PDF comes from the registry)
- Modify: `Tests/FeatherviewCoreTests/FolderScannerTests.swift` (`ImageFormatsTests`: `a.pdf` moves from not-decodable to decodable, add `a.PDF`)
- Test: `Tests/FeatherviewCoreTests/PDFPagesTests.swift`

Draft: `40cf706`.

**Interfaces:**
- Consumes: Task 1.
- Produces: `PDFPages.format` (name "PDF", `pdf`, `hasPages: true`); size = crop box in points × 2,
  `/Rotate` applied; `render(_ data: Data, page: Int, maxPixelSize: Int?) throws -> CGImage` renders
  directly at `min(2, maxPixelSize / longest side in points)` per point, opaque, white background.
- Transform: **not** `getDrawingTransform` (never scales up). Scale, then rotate by `/Rotate`
  clockwise (90: translate (0, W), rotate −π/2; 180: translate (W, H), rotate π; 270: translate
  (H, 0), rotate π/2; W/H = crop box width/height), translate by −cropBox.origin, clip to the crop box.

- [ ] **Step 1:** Bring `PDFPagesTests.swift` from the draft and add:

```swift
    @Test func encryptedPDFIsUnreadable() throws {
        let url = try Fixtures.makeTempDir().appendingPathComponent("locked.pdf")
        var box = CGRect(x: 0, y: 0, width: 100, height: 100)
        let info: [CFString: Any] = [kCGPDFContextUserPassword: "secret", kCGPDFContextOwnerPassword: "owner"]
        let context = try #require(CGContext(url as CFURL, mediaBox: &box, info as CFDictionary))
        context.beginPDFPage(nil); context.endPDFPage(); context.closePDF()
        #expect(throws: DecodeError.unreadable(url)) { try ImageDecoder.decode(url) }
    }
```

  Run `swift test --filter "PDFPagesTests|ImageFormatsTests"` — FAIL.
- [ ] **Step 2:** Bring the source; in `render`, throw `.unsupported` when
  `document.isEncrypted && !document.isUnlocked`. Fill slot `// Task 5`. Run `swift test` — PASS.
- [ ] **Step 3: Commit** `feat: PDFs browse like multi-page images`

---

### Task 6: HDR decode

Spec "Formats" (HDR display): images with HDR data show their extra brightness on macOS 15+;
only those decode at more than 8 bits. Facts: see "ImageIO facts" — the decode request costs SDR
images nothing.

**Files:**
- Modify: `Sources/FeatherviewCore/ImageDecoder.swift` (`decode(_:maxPixelSize:halvingSteps:page:hdr:)`)
- Modify: `Sources/FeatherviewCore/ImageCache.swift` (`init(capacity:hdr:)`, passes it to `decode`)
- Modify: `Tests/FeatherviewCoreTests/Fixtures.swift` (`writeHDRGainMap(to:)`)
- Test: `Tests/FeatherviewCoreTests/ImageDecoderTests.swift`

**Interfaces:**
- Consumes: main (no dependency on Tasks 2–5).
- Produces: `ImageDecoder.decode(_ url: URL, maxPixelSize: Int? = nil, halvingSteps: Bool = false, page: Int = 0, hdr: Bool = false) throws -> CGImage`;
  `ImageCache(capacity: Int = 8, hdr: Bool = false)`;
  `public static var supportsHDR: Bool { if #available(macOS 15, *) { true } else { false } }` on `ImageDecoder`.
  `hdr` is ignored (SDR decode) when `supportsHDR` is false, and for own formats.

- [ ] **Step 1: Fixture and failing tests**

```swift
    // Fixtures.swift
    /// A gain-map image: left half 4× SDR white, right half a dark colour. macOS 15+ only.
    @available(macOS 15, *)
    @discardableResult
    static func writeHDRGainMap(to url: URL, type: UTType = .heic) throws -> URL {
        let space = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)!
        let context = CGContext(data: nil, width: 64, height: 48, bitsPerComponent: 16, bytesPerRow: 0, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                                    | CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder16Little.rawValue)!
        context.setFillColor(CGColor(colorSpace: space, components: [4, 4, 4, 1])!)
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 48))
        context.setFillColor(CGColor(colorSpace: space, components: [0.5, 0.2, 0.1, 1])!)
        context.fill(CGRect(x: 32, y: 0, width: 32, height: 48))
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(dest, context.makeImage()!,
                                   [kCGImageDestinationEncodeRequest: kCGImageDestinationEncodeToISOGainmap] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
        return url
    }
```

```swift
    // ImageDecoderTests.swift
    @Test func hdrImagesDecodeDeeperOnlyWhenAsked() throws {
        guard #available(macOS 15, *) else { return }
        let dir = try Fixtures.makeTempDir()
        let hdr = try Fixtures.writeHDRGainMap(to: dir.appendingPathComponent("gm.heic"))
        #expect(try ImageDecoder.decode(hdr, maxPixelSize: 64, halvingSteps: true, hdr: true).bitsPerComponent > 8)
        #expect(try ImageDecoder.decode(hdr, maxPixelSize: 64, halvingSteps: true).bitsPerComponent == 8)
    }

    @Test func sdrImagesStayEightBitWithTheHDRRequest() throws {
        let dir = try Fixtures.makeTempDir()
        let sdr = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 64, height: 48)
        #expect(try ImageDecoder.decode(sdr, maxPixelSize: 64, halvingSteps: true, hdr: true).bitsPerComponent == 8)
    }
```

Run `swift test --filter ImageDecoderTests` — FAIL (no `hdr:` parameter).

- [ ] **Step 2: Implement.** In `decode`, when `hdr && supportsHDR`, add
  `kCGImageSourceDecodeRequest: kCGImageSourceDecodeToHDR` to the thumbnail options. `ImageCache`
  stores `hdr` and passes it. Run `swift test` — PASS.
- [ ] **Step 3: Measure** (note in the commit body): decode time and `bitsPerComponent × width ×
  height` of a 12 MP SDR JPEG with and without `hdr: true` (must be equal), and of the HDR
  fixture scaled up to 4032 × 3024 (re-encode a larger fixture locally, don't commit it).
- [ ] **Step 4: Commit** `feat: decode HDR images with their extra range on macOS 15+`

---

### Task 7: Output formats, options, encoder, Save As core, batch on the registry

Spec "Formats" (write lists, hidden texture formats), "Format options" (the table and the
2026-10-16 decisions), "Menu commands" (Save As never overwrites without the Mac prompt),
"Batch window › Output" (every writable format with its options).

**Files:**
- Create: `Sources/FeatherviewCore/OutputFormat.swift` (OutputFormat, FormatOption, TIFFCompression, FormatOptions, FormatRegistry)
- Create: `Sources/FeatherviewCore/ImageEncoder.swift`, `Sources/FeatherviewCore/FormatSettings.swift`, `Sources/FeatherviewCore/ImageSaver.swift`
- Modify: `Sources/FeatherviewCore/BatchJob.swift` (remove the old `OutputFormat` enum; `options` replaces `quality`)
- Modify: `Sources/FeatherviewCore/BatchConverter.swift` (encode through `ImageSaver.pages` + `ImageEncoder`; metadata moves to `ImageEncoder.metadataProperties`)
- Modify: `Sources/Featherview/BatchView.swift` (minimal: picker over `FormatRegistry.writable`, quality slider removed; Task 14 builds the real UI)
- Modify: `Tests/FeatherviewCoreTests/BatchConverterTests.swift`, `BatchPlannerTests.swift`
- Test: `Tests/FeatherviewCoreTests/OutputFormatTests.swift`, `Tests/FeatherviewCoreTests/OwnDecodersTests.swift` (one added test)

Draft: `8671c0e` (sources), `b226caf` (tests), `98fd3ed` (BatchPlannerTests change).

**Interfaces:**
- Consumes: `QOICodec.encode`, `PCXCodec.encode` (Task 2), `NetpbmEncoder.pgm/ppm` (Task 3), `RGBAImage` (Task 1).
- Produces:
  - `public struct OutputFormat: Hashable, Sendable, Identifiable { id /* stored: "jpg", "png", "heic", "avif", "tiff", "gif", "jp2", "pdf", "psd", "tga", "ico", "icns", "exr", "pbm", "bmp", "pgm", "ppm", "qoi", "pcx"; an unknown future ImageIO type: its preferred extension */; name; fileExtension; writer: Writer; optionFields: [FormatOption]; defaultOptions: FormatOptions; var type: UTType? }` — equality and hash by `id`; `static let jpeg, png, heic, tiff`.
  - `OutputFormat.Writer { case imageIO(String), pdf, pgm, ppm, qoi, pcx }`
  - `public enum FormatOption: String, CaseIterable { quality, lossless, progressive, keepMetadata, targetSize, interlaced, tiffCompression, keepAllPages }`
  - `public enum TIFFCompression: Int, Codable, CaseIterable { none = 1, lzw = 5, packBits = 32773, jpeg = 7, zip = 8 }`
  - `public struct FormatOptions: Codable, Equatable, Sendable { quality = 80, lossless = false, progressive = false, keepMetadata = true, targetSizeKB: Int? = nil, interlaced = false, tiffCompression = .lzw, keepAllPages = true }` — decoding tolerates missing keys (each falls back to its default).
  - Options per format: JPEG quality, progressive, keepMetadata, targetSize; HEIC/AVIF quality, keepMetadata; PNG interlaced; TIFF tiffCompression, keepAllPages; JPEG 2000 lossless, quality (default lossless, 90); PDF lossless, quality (default lossy, 95); every other format none.
  - `public enum FormatRegistry { static let writable: [OutputFormat] /* sorted by name, hidden types left out */; static func format(id:) -> OutputFormat?; static var readableNames: (macOS: [String], own: [String]) }`
  - `public enum ImageEncoder { static func encode(_ pages: [CGImage], as: OutputFormat, options: FormatOptions, metadataFrom source: URL? = nil) throws -> Data }` — `EncodeError.failed`.
  - `public enum FormatSettings { static let lastSaveFormat: Setting<String> /* "saveAsFormat", "jpg" */; static func options(for:in:) -> FormatOptions; save(_:for:in:); profiles(for:in:) -> [(name, options)] /* Finder order */; saveProfile(_:_:for:in:) /* blank ignored, same name replaces */; deleteProfile(_:for:in:); static func lastFormat(in:) -> OutputFormat /* unknown id → .jpeg */ }`
  - `public enum ImageSaver { static func pages(of:page:for:options:maxPixelSize:) throws -> [CGImage]; static func save(_ source: URL, page: Int, to: URL, as: OutputFormat, options: FormatOptions) throws }`
  - `BatchJob(inputs:outputFolder:format:options: FormatOptions? = nil /* nil = format's defaults */, maxDimension:rename:)`
- Encoder rules (from the facts): quality clamped 1…100, lossless → 1.0, AVIF ≤ 0.99; JPEG
  target size: binary search on quality for the highest that fits, quality 1 if none does; ICO /
  ICNS: fit into the smallest allowed square that holds the image, else the largest, centred on
  transparency, never enlarged; PDF: one page per image at 1 px = 1 pt, JPEG at the quality unless
  lossless or the page has alpha; pages: every page for PDF and for TIFF with keep-all-pages,
  else the current page only; metadata (TIFF make/model, EXIF minus pixel size, GPS, IPTC) only
  when `keepMetadata`; orientation always 1.

- [ ] **Step 1:** Bring `OutputFormatTests.swift` from `b226caf`; apply the `BatchConverterTests`
  (`@Test(arguments: [OutputFormat.jpeg, .png, .heic, .tiff])`) and `BatchPlannerTests`
  (`optionsDefaultToTheFormats`) changes from the draft. Add to `FormatSettingsTests`:

```swift
    @Test func unknownLastFormatFallsBackToJPEG() {
        defaults.set("no-such-format", forKey: FormatSettings.lastSaveFormat.key)
        #expect(FormatSettings.lastFormat(in: defaults) == .jpeg)
        defaults.set("png", forKey: FormatSettings.lastSaveFormat.key)
        #expect(FormatSettings.lastFormat(in: defaults) == .png)
    }
```

  and to `OwnDecodersTests` (every decoder of Tasks 2–5 is registered):

```swift
    @Test func builtInDecodersCoverTheSpec() {
        let extensions = Set(OwnDecoders.builtIn.flatMap(\.extensions))
        for ext in ["qoi", "pcx", "dcx", "xbm", "xpm", "wbmp", "ras", "iff", "lbm", "pdf"] {
            #expect(extensions.contains(ext), "\(ext)")
        }
    }
```

  Run `swift test` — FAIL (types missing).
- [ ] **Step 2:** Bring the sources from `8671c0e`; add `FormatSettings.lastFormat(in:)`. Apply the
  minimal `BatchView` change. Run `swift build && swift test` — PASS.
- [ ] **Step 3: Commit** `feat: write every spec format with its options; Save As core; batch uses the registry`

---

### Task 8: Viewer keys and status-line text (core)

Spec "Keys": S Save As…, A About (milestone 3). Spec "Viewer" status bar: pixel size, zoom %,
file size, position N / M, modification date (page too for multi-page files). Spec "About
window": Copy button text.

**Files:**
- Modify: `Sources/FeatherviewCore/ViewerKey.swift` (`.saveAs` on "s", `.about` on "a")
- Create: `Sources/FeatherviewCore/StatusLine.swift`
- Create: `Sources/FeatherviewCore/AboutInfo.swift`
- Test: `Tests/FeatherviewCoreTests/ViewerKeyTests.swift`, `Tests/FeatherviewCoreTests/StatusLineTests.swift`, `Tests/FeatherviewCoreTests/AboutInfoTests.swift`

**Interfaces:**
- Produces:
  - `ViewerKey.saveAs`, `ViewerKey.about` (single lowercase key, like the others; Shift+S is not it).
  - `public struct StatusLine: Equatable { public var fields: [String] }` and
    `public static func make(pixelSize: CGSize?, zoomPercent: Int?, fileBytes: Int?, index: Int, count: Int, page: Int, pageCount: Int, modified: Date?) -> StatusLine` — fields in that order, missing values left out (never blanks): `"4000 × 3000"`, `"46 %"`, file size via `ByteCountFormatter(.file)`, `"3 / 120"`, `"page 2 / 3"` only when `pageCount > 1`, date `.abbreviated` + `.shortened`. Numbers use `formatted()` so they follow the locale.
  - `public enum AboutInfo { static func reportText(version: String, build: String, macOS: String, model: String) -> String }` → `"Featherview 0.1.0 (1)\nmacOS 27.0.1 (26A434)\nMac14,6"`; `static func modelIdentifier() -> String` (sysctl `hw.model`).

- [ ] **Step 1: Failing tests**

```swift
// ViewerKeyTests.swift — add
    @Test func saveAsAndAbout() {
        #expect(ViewerKey.action(characters: "s", shift: false) == .saveAs)
        #expect(ViewerKey.action(characters: "a", shift: false) == .about)
        #expect(ViewerKey.action(characters: "S", shift: true) == nil)
    }
```

```swift
// StatusLineTests.swift
import CoreGraphics
import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct StatusLineTests {
    @Test func fieldsInOrderLeavingOutWhatIsUnknown() {
        let line = StatusLine.make(pixelSize: CGSize(width: 4000, height: 3000), zoomPercent: 46, fileBytes: nil,
                                   index: 2, count: 120, page: 0, pageCount: 1, modified: nil)
        #expect(line.fields == ["\(4000.formatted()) × \(3000.formatted())", "46 %", "3 / 120"])
    }

    @Test func pageOnlyForMultiPageFiles() {
        let line = StatusLine.make(pixelSize: nil, zoomPercent: nil, fileBytes: nil, index: 0, count: 1,
                                   page: 1, pageCount: 3, modified: nil)
        #expect(line.fields == ["1 / 1", "page 2 / 3"])
    }

    @Test func fileSizeAndDateAreFormatted() {
        let date = Date(timeIntervalSince1970: 0)
        let line = StatusLine.make(pixelSize: nil, zoomPercent: nil, fileBytes: 333_509, index: 0, count: 1,
                                   page: 0, pageCount: 1, modified: date)
        #expect(line.fields.contains(ByteCountFormatter.string(fromByteCount: 333_509, countStyle: .file)))
        #expect(line.fields.contains(date.formatted(date: .abbreviated, time: .shortened)))
    }
}
```

```swift
// AboutInfoTests.swift
import Testing
@testable import FeatherviewCore

@Suite struct AboutInfoTests {
    @Test func reportTextForBugReports() {
        #expect(AboutInfo.reportText(version: "0.1.0", build: "1", macOS: "27.0.1 (26A434)", model: "Mac14,6")
                == "Featherview 0.1.0 (1)\nmacOS 27.0.1 (26A434)\nMac14,6")
    }

    @Test func modelIdentifierIsReadable() {
        #expect(AboutInfo.modelIdentifier().hasPrefix("Mac") || AboutInfo.modelIdentifier().contains(","))
    }
}
```

Run `swift test --filter "ViewerKeyTests|StatusLineTests|AboutInfoTests"` — FAIL.

- [ ] **Step 2: Implement** (`"page \(page + 1) / \(pageCount)"` via `String(localized:)`;
  `modelIdentifier` with `sysctlbyname("hw.model", …)`). Add the two cases to the app's
  `ViewerView.handle` switch as `break` so the app compiles (Tasks 11 and 13 wire them). Run
  `swift build && swift test` — PASS.
- [ ] **Step 3: Commit** `feat: S and A keys, status-line and About text`

---

### Task 9: SVG and Finder's Open With

Spec "Formats": SVG through AppKit, rasterised at the size shown. Roadmap §3: Featherview listed
in Open With for every format it reads, rank Alternate.

**Files:**
- Create: `Sources/Featherview/SVGFormat.swift`
- Modify: `Sources/Featherview/FeatherviewApp.swift` (`AppDelegate.applicationWillFinishLaunching` registers `SVGFormat.format` before the open-documents handler)
- Modify: `Resources/Info.plist` (`CFBundleDocumentTypes`, `UTImportedTypeDeclarations`)

**Interfaces:**
- Consumes: Task 1 (`OwnFormat`, `OwnDecoders.register`), Task 5 (PDF in the registry).
- Produces: `enum SVGFormat { static let format: OwnFormat }` — name "SVG", `svg`; `size` = the
  `NSImage`'s size in points × 2 (as PDF); `decode` renders with `NSImage(data:)` into an sRGB
  `CGContext` of exactly the target size (`maxPixelSize` or size × 2), **transparent** background,
  via `NSGraphicsContext(cgContext:flipped:)` + `image.draw(in:)`. Not `cgImage(forProposedRect:)`:
  it adds the screen's backing scale.

```swift
import AppKit
import FeatherviewCore

/// SVG through AppKit (spec "Formats"); here, not in FeatherviewCore, because it needs NSImage.
enum SVGFormat {
    static let format = OwnFormat(
        name: "SVG", extensions: ["svg"],
        size: { data, _ in NSImage(data: data).map { CGSize(width: $0.size.width * 2, height: $0.size.height * 2) } },
        decode: { data, _, maxPixelSize in
            guard let image = NSImage(data: data), image.size.width >= 1, image.size.height >= 1 else {
                throw OwnDecodeError.corrupt
            }
            var scale = 2.0
            if let maxPixelSize { scale = min(scale, Double(maxPixelSize) / max(image.size.width, image.size.height)) }
            let width = max(1, Int((image.size.width * scale).rounded()))
            let height = max(1, Int((image.size.height * scale).rounded()))
            guard width <= 16384, height <= 16384,
                  let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { throw OwnDecodeError.corrupt }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
            NSGraphicsContext.restoreGraphicsState()
            guard let rendered = context.makeImage() else { throw OwnDecodeError.corrupt }
            return rendered
        })
}
```

- `Info.plist`: keep the `public.image` document type (Viewer, Alternate); add one document type
  for `com.adobe.pdf` (Viewer, Alternate) and one listing the own types below (Viewer, Alternate).
  `UTImportedTypeDeclarations` (conforming to `public.image` and `public.data`) for types macOS
  doesn't declare: check each with `mdls`-free `swift -e 'import UniformTypeIdentifiers; print(UTType(filenameExtension: "qoi") as Any)'`
  first and import only the ones that come back dynamic (`dyn.`). Our identifiers:
  `net.mynetx.featherview.qoi` (qoi), `.pcx` (pcx), `.dcx` (dcx), `.xbm` (xbm), `.xpm` (xpm),
  `.wbmp` (wbmp), `.sun-raster` (ras, sun), `.ilbm` (iff, lbm, ilbm); SVG is `public.svg-image`.

- [ ] **Step 1:** Write `SVGFormat.swift`, register it, edit `Info.plist`. `swift build`.
- [ ] **Step 2: Check by hand** (record results in the commit body): `scripts/bundle.sh debug`;
  open a hand-written `.svg` (a 120 × 80 rect + circle) — sharp in fit and at 100 %; a broken
  `.svg` → "Can't open"; `lsregister -f build/Featherview.app` then Finder › Open With on a `.qoi`,
  `.pcx`, `.pdf`, `.svg` and `.jpg` lists Featherview, and no default handler changed.
- [ ] **Step 3: Commit** `feat: SVG via AppKit; Featherview in Open With for every readable format`

---

### Task 10: Format options view and Settings › Formats

Spec "Settings": Formats tab with per-format defaults and saved profiles. Spec "Batch window ›
Output": "the same options appear when saving from the viewer". One view for all three places.

**Files:**
- Create: `Sources/Featherview/FormatOptionsView.swift`
- Modify: `Sources/Featherview/SettingsView.swift` (new tab "Formats"; doc comment no longer says "except Formats")

**Interfaces:**
- Consumes: Task 7 (`OutputFormat`, `FormatOptions`, `FormatOption`, `FormatSettings`, `FormatRegistry`).
- Produces: `struct FormatOptionsView: View { let format: OutputFormat; @Binding var options: FormatOptions }` —
  shows only `format.optionFields`, in that order: quality slider 1–100 with its number (disabled
  while lossless is on), lossless toggle, progressive toggle, keep-metadata toggle ("Keep camera
  data, location and keywords"), target size (toggle + KB field, ≥ 1), interlaced toggle, TIFF
  compression picker (None, LZW, PackBits, JPEG, ZIP), keep-all-pages toggle. A format without
  options shows "No options for <name>" in secondary text. Below: a "Profiles" menu (each profile
  applies its options; "Save as Profile…" asks for a name in a small sheet; "Delete Profile" submenu).
  Profile actions call `FormatSettings`; the view never writes `options` to `UserDefaults` itself —
  the owner decides when (Settings: on every change; Save As and batch: on use).
- Settings › Formats: a format picker (all `FormatRegistry.writable`) and `FormatOptionsView` bound
  to `FormatSettings.options(for:)`, saved on every change.

- [ ] **Step 1:** Implement both; `swift build`.
- [ ] **Step 2: Check by hand:** each format shows exactly its spec options; JPEG quality 55 in
  Settings is still 55 after quitting and relaunching; a profile saved for PNG doesn't appear for
  JPEG; deleting it removes it; German text (`-AppleLanguages "(de)"`) doesn't clip in the tab.
- [ ] **Step 3: Commit** `feat: format options view and the Formats settings tab`

---

### Task 11: About window

Spec "About window" (all of it). No acknowledgements yet: no bundled library until milestone 5,
so the Acknowledgements button appears only when `Resources/Acknowledgements.txt` exists in the
bundle (milestone 5 adds it).

**Files:**
- Create: `Sources/Featherview/AboutView.swift`
- Modify: `Sources/Featherview/FeatherviewApp.swift` (`Window("About Featherview", id: "about")`, `.windowResizability(.contentSize)`)
- Modify: `Sources/Featherview/ViewerView.swift` (`.about` key opens it; `CommandGroup(replacing: .appInfo)` "About Featherview" opens it)
- Modify: `scripts/bundle.sh` (copy `LICENSE` to `Contents/Resources/LICENSE`)

**Interfaces:**
- Consumes: Task 7 (`FormatRegistry.readableNames`, `.writable`), Task 8 (`AboutInfo`, `ViewerKey.about`).
- Content, top to bottom: app icon (`NSApp.applicationIconImage`, 96 pt), "Featherview", version
  and build from the bundle (`0.1.0 (1)`), the one-line description ("A fast, keyboard-driven
  image viewer with batch conversion"), three link buttons (Website
  `https://featherview.github.io`, Source Code `https://github.com/mynetx/featherview`, Report a
  Problem `https://github.com/mynetx/featherview/issues/new`), a "Supported Formats" disclosure
  with two lists — Read: "macOS <version>: <names>" and "Featherview: <own names>"; Write: the
  writable names — then "MIT License" (sheet with the bundled `LICENSE` text, scrollable,
  selectable), copyright "© 2026 Joachim Rütter", and "Copy" (puts `AboutInfo.reportText` on the
  pasteboard; macOS version from `ProcessInfo.processInfo.operatingSystemVersionString`).

- [ ] **Step 1:** Implement; `swift build`; `scripts/bundle.sh debug`.
- [ ] **Step 2: Check by hand:** A and the app menu open it (one window, not two); Copy pastes the
  three lines; links open the browser; the licence sheet scrolls; window not resizable; dark mode readable.
- [ ] **Step 3: Commit** `feat: About window with formats, licence and bug-report text`

---

### Task 12: HDR display

Spec "Formats" (HDR display). Facts: see "ImageIO facts".

**Files:**
- Modify: `Sources/Featherview/ViewerModel.swift` (both caches `ImageCache(capacity:hdr: ImageDecoder.supportsHDR)`; page decodes and ⌘C's decode pass `hdr:` too — ⌘C keeps SDR: pass `false`)
- Modify: `Sources/Featherview/ImageCanvas.swift` (`ImageLayerView.show`: HDR flag on the layer)

**Interfaces:**
- Consumes: Task 6.
- In `ImageLayerView.show`, per image: `let isHDR = image.bitsPerComponent > 8` (our decodes are 8-bit
  unless HDR). macOS 26+: `imageLayer.preferredDynamicRange = isHDR ? .high : .standard`; 14–25:
  `imageLayer.wantsExtendedDynamicRangeContent = isHDR`. Set it in the same `CATransaction` as
  `contents`, so an SDR image after an HDR one never flashes bright.

- [ ] **Step 1:** Implement; `swift build`.
- [ ] **Step 2: Check by hand** on the MacBook's XDR screen with an iPhone HDR photo (maintainer
  provides one, not committed) and the gain-map fixture: brighter highlights than Preview's SDR
  rendering, matching Photos; switching to an SDR JPEG and back shows no flash; external SDR
  screen shows it as SDR; log line timings of 20 HDR swaps vs 20 SDR swaps in the commit body.
- [ ] **Step 3: Commit** `feat: HDR photos show their extra brightness`

---

### Task 13: Save As

Spec "Menu commands": ⇧⌘S Save As… (any writable format with its options, orientation applied,
never overwriting without the standard Mac replace prompt; afterwards the window shows the saved
file in its folder; if Featherview can't read that format, it stays on the original). Spec
"Keys": S. Parity: the format list remembers the last format.

**Files:**
- Create: `Sources/Featherview/SavePanel.swift`
- Modify: `Sources/Featherview/ViewerModel.swift` (`saveAs()`)
- Modify: `Sources/Featherview/ViewerView.swift` (`.saveAs` key; File menu "Save As…  (S)" with ⇧⌘S, disabled without an image or while held)

**Interfaces:**
- Consumes: Task 7 (`ImageSaver`, `FormatSettings`, `FormatRegistry`), Task 8 (`ViewerKey.saveAs`), Task 10 (`FormatOptionsView`).
- `SavePanel.run(for url: URL, window: NSWindow?) -> (url: URL, format: OutputFormat, options: FormatOptions)?`:
  `NSSavePanel` as a sheet on the viewer window (`beginSheetModal`, awaited), name field = base
  name, directory = the image's folder, `canCreateDirectories`, accessory view = `NSHostingView`
  of a small SwiftUI view: format `Picker` over `FormatRegistry.writable` (initial
  `FormatSettings.lastFormat()`) + `FormatOptionsView` for it (initial `FormatSettings.options(for:)`).
  Changing the format sets `panel.allowedContentTypes = [format.type]` when `type` is non-nil
  (macOS then fixes the extension) and swaps the options. On OK: save the options and
  `lastSaveFormat`, return. The panel's own replace prompt is the only overwrite confirmation.
- `ViewerModel.saveAs()`: guard current image and `!list.isHolding`; run the panel; then, off the
  main thread and queued behind `rotateTask` like Trash and moves, `ImageSaver.save(url, page: page, …)`;
  on success, if `ImageFormats.isDecodable(target)` → `open(target)` (the cache must not serve a
  stale image when the target replaced a listed file: `cache.remove(target)` first); else stay.
  On failure: `errorMessage = String(localized: "Couldn't save \(target.lastPathComponent)")`.

- [ ] **Step 1:** Implement; `swift build`; `scripts/bundle.sh debug`.
- [ ] **Step 2: Check by hand:** S and ⇧⌘S open the sheet with the last format; JPEG → PNG changes
  the extension in the name field; save a rotated (EXIF 6) JPEG as PNG → upright; save as PDF → the
  window shows the PDF; save over an existing file → the Mac replace prompt, and Cancel there keeps
  it; save over the shown image itself (same name, same format) → the new image shows, no stale
  cached one; a read-only folder → "Couldn't save <name>", nothing left behind; target size 50 KB
  on a 12 MP photo → file ≤ 50 KB; a multi-page TIFF as TIFF keeps its pages, as PNG writes the
  shown page.
- [ ] **Step 3: Commit** `feat: Save As with every writable format and its options`

---

### Task 14: Batch output on the registry

Spec "Batch window › Output": every writable format, each with its options (same view as Save
As). The rest of the batch window is milestone 4.

**Files:**
- Modify: `Sources/Featherview/BatchView.swift` (`BatchModel.format` remembered under its own key; `options` from `FormatSettings.options(for:)` on format change; `FormatOptionsView` under the picker; options saved with `FormatSettings.save` when Convert is pressed)

**Interfaces:**
- Consumes: Task 7, Task 10.
- `BatchModel` gets `var options: FormatOptions` (replaced when `format` changes) and remembers the
  batch's format under its own key `batchFormat` (default "jpg"; unknown id → JPEG), so Save As
  and batch don't change each other's format.

- [ ] **Step 1:** Implement; `swift build`.
- [ ] **Step 2: Check by hand:** convert 20 mixed files (incl. a `.qoi`, `.pcx`, `.pdf`, `.svg`)
  to each of JPEG, PNG, TIFF (ZIP), JPEG 2000 (lossless), PDF, ICO, QOI, PCX, PGM — every output
  opens in Featherview and in Preview where Preview reads the format; one corrupt input fails alone.
- [ ] **Step 3: Commit** `feat: batch writes every format with its options`

---

### Task 15: Status bar, faster toolbar, Liquid Glass

Spec "Viewer": status bar (on by default, View › Hide Status Bar remembered, hidden in full
screen) and Liquid Glass on macOS 26+ (chooser, F7/F8 panel, on-image messages; earlier systems
keep the material). Roadmap §3: the prefetched swap takes ≈20 ms (budget 16 ms) because every
title change re-lays out the SwiftUI toolbar items.

**Files:**
- Create: `Sources/Featherview/StatusBar.swift`
- Modify: `Sources/Featherview/ViewerView.swift` (status bar inset, View menu item, title handling, `messageBox()` glass)
- Modify: `Sources/Featherview/ViewerModel.swift` (file size in `fileValues`; zoom percent)
- Modify: `Sources/Featherview/FolderChooserView.swift`, `Sources/Featherview/DestinationPanel.swift` (glass)
- Modify: `Sources/Featherview/ViewerToolbar.swift` (disabled states; step 3 may change more)

**Interfaces:**
- Consumes: Task 8 (`StatusLine`).
- Status bar: `.safeAreaInset(edge: .bottom)` with one row of `StatusLine.make(…).fields`, separated
  by thin dividers, `.font(.caption)`, `.monospacedDigit()`, secondary colour, leading-aligned,
  bar background `.bar`. Values: pixel size and date from `fileValues` (extend
  `OverlayTemplate.fileValues` or add `fileBytes` beside it — read off the main thread, as now),
  zoom % = actual scale shown (fit: `drawSize.width / (imageFullWidth / displayScale)`, from the
  full pixel size, not the screen-size decode), index/count from the list, page/pageCount.
  `@AppStorage("statusBarHidden")`; View menu "Hide Status Bar" / "Show Status Bar" (⌥⌘S is
  taken by nothing — use no shortcut). Hidden when `model.isFullScreen`.
- Glass helper in `ViewerView.swift`:

```swift
extension View {
    /// Liquid Glass on macOS 26+ (spec "Viewer"); the material before.
    @ViewBuilder func panelBackground(cornerRadius: CGFloat) -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            background(.regularMaterial, in: .rect(cornerRadius: cornerRadius))
        }
    }
}
```

  used by `messageBox()`, `FolderChooserView` and `DestinationPanel` instead of their `.background(.regularMaterial, …)`.
- Toolbar buttons disabled when they can't act (maintainer, 2026-10-16: ‹ › were enabled with no
  file open): previous / next need a non-empty list or a known folder (the chooser still works
  from an empty folder); rotate, zoom, info and Trash need a current image and `!list.isHolding`
  (Trash, rotate) — the same conditions the model's methods already guard on. Menu items follow
  the same rules (`.disabled`), so menu and toolbar agree.
- The "Open an image with ⌘O, or drop one here" hint must sit centred in the window (it showed
  at the bottom trailing corner in the maintainer's screenshot); check every message position.

- [ ] **Step 1: Measure before** (commit body): a folder of 20 12 MP JPEGs, hold → for 5 s, read
  the `show … ms` log lines (`AGENTS.md`: build locally with `log.debug` → `log.notice` and
  `open --env OS_ACTIVITY_DT_MODE=YES`, never commit that). Expected today ≈20 ms.
- [ ] **Step 2:** Status bar, View menu item, glass, disabled toolbar and menu states. `swift build`; check the bar by hand (values
  match the Info panel; zoom % follows +/−/0/1; page shown for a TIFF and a PDF; hidden in full
  screen and after Hide, also after relaunch; Arabic `-AppleLanguages "(ar)"` mirrors it).
- [ ] **Step 3: Make the swap fast.** Measure again (the bar adds work too). Then, smallest first,
  stop as soon as prefetched swaps are < 16 ms: (a) set `window.title` directly from the model
  (via the existing `WindowAccessor` window) instead of `.navigationTitle`, so SwiftUI doesn't
  re-evaluate the toolbar on each image; (b) make `ViewerToolbar` read nothing that changes per
  image (`model.pageCount` → a separate small view, or the page items always present but hidden);
  (c) replace the SwiftUI `.toolbar` with an `NSToolbar` (same identifiers, `autosavesConfiguration`,
  `allowsUserCustomization`) installed through `WindowAccessor`. Keep "Hide Toolbar" remembered.
- [ ] **Step 4: Measure after**; both numbers in the commit body; update the roadmap line on toolbar speed.
- [ ] **Step 5: Commit** `feat: status bar and Liquid Glass panels; swap under 16 ms again`

---

### Task 16: Manual QA, budgets, docs

**Files:**
- Modify: `docs/roadmap.md` (milestone 3 done, plan link), `docs/superpowers/plans/2026-10-16-milestone-3-formats-save-as.md` (tick boxes)
- Modify: `README.md` (supported formats paragraph, if it lists formats)

- [ ] **Step 1:** `scripts/bundle.sh release`; all `AGENTS.md` budgets measured again (cold launch
  with a 12 MP JPEG, prefetched and unprefetched swap, 10,000-file folder, memory while browsing).
  Any regression is a bug: fix before going on.
- [ ] **Step 2:** Real-world files (maintainer provides or exports them; not committed): at least
  one each of QOI, PCX (8-bit and 24-bit), DCX, XBM, XPM, WBMP, RAS, IFF/LBM (incl. a HAM picture),
  SVG, a 300-page PDF, a PDF with rotated pages, an encrypted PDF, an iPhone HDR photo. Each opens
  (or says "Can't open" for the encrypted one), pages step, batch converts it.
- [ ] **Step 3:** Save As round trip for every writable format from a 12 MP photo; open each
  result in Featherview and Preview; note sizes and times in `docs/parity.md` only if something
  differs from the spec.
- [ ] **Step 4:** Open With: Featherview offered for every format in step 2; Finder defaults unchanged.
- [ ] **Step 5:** `swift test` green; commit `docs: milestone 3 done after manual QA`.

---

## Self-review notes

- Spec coverage: Formats read (Tasks 1–5, 9), PDF reading (5), write lists and hidden types (7),
  Format options table and decisions (7, 10), Save As incl. the switch-to-file rule (13), About (11),
  Settings › Formats (10), batch output (7, 14), HDR (6, 12), status bar and Liquid Glass (15),
  toolbar speed (15), Open With (9), budgets (16). Roadmap §3 "own encoders golden-file tests"
  (2, 3). Not here by design: WebP (milestone 5), compact toolbar and zoom % in the title (not
  accepted into the spec), the own-look pass (roadmap).
- `FormatSettings.lastFormat(in:)` is new beyond the draft (Task 7, tested).
- `ImageCache(capacity:hdr:)`: Task 6 adds the parameter with a default, so Task 12 is the only caller change.
