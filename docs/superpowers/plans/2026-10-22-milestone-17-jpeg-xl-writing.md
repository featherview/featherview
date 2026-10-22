# Milestone 17: JPEG XL writing — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. In this repo, code tasks run with the `plan-wave` workflow; tasks marked "main session" need the screen and run in the main session after the maintainer's go.

**Goal:** Save As and batch write JPEG XL (`.jxl`) with lossless, quality, effort and keep-metadata
options, through libjxl built from source.

**Architecture:** ImageIO doesn't write JPEG XL on any macOS we support (Spike facts), so libjxl
0.12.0 with highway, brotli and skcms is vendored as one SwiftPM C/C++ target, `CJPEGXL`, like
`CJPEGXR`. Swift calls libjxl's C API (`jxl/encode.h`); no Swift–C++ interop. A new
`JXLEncoder` in `FeatherviewCore` turns a `CGImage` into JXL bytes in the image's own colour space
(8 or 16 bits, alpha only when present) with the source's metadata as an XMP box. `FormatRegistry`
gets an own `jxl` format (writer `.jxl`); `ImageEncoder` routes to it. Save As, batch and
Settings › Formats pick it up from `FormatRegistry.writable` like WebP did.

**Tech Stack:** Swift 6, SwiftPM C/C++ target (C++17), libjxl 0.12.0 (BSD-3-Clause + patent grant),
highway (Apache-2.0 or BSD-3-Clause), brotli (MIT), skcms (BSD-3-Clause), ImageIO (reads JXL back in
tests), Swift Testing.

**Spec:** `docs/spec.md` "Formats" ("Writing JPEG XL is v2 (needs libjxl, a large C++ build)"),
"Format options" (Task 4 adds the JPEG XL row), `docs/roadmap.md` "JPEG XL writing (v2)". Rules:
`AGENTS.md` (Dependencies row; "Imaging: … JPEG XL encoding in v2").

## Decisions (the spec leaves these to the plan)

1. **libjxl everywhere, never ImageIO.** ImageIO writes no JPEG XL on macOS 27 (nor on 14, which
   added JXL *reading* only). Should a later macOS add a writer, `public.jpeg-xl` is hidden in
   `FormatRegistry` (as `org.webmproject.webp` is), so the options and output stay the same on every
   version.
2. **Vendored, not the `SDWebImage/libjxl-Xcode` package.** That package is at libjxl 0.10.4 (upstream
   is 0.12.0), pulls libjxl's submodules recursively with full history (testdata, libjpeg-turbo,
   libpng, zlib, googletest, sjpeg: 687 MB, about 14 min for a fresh resolve, on every CI and
   worktree), and links highway's `nanobenchmark.cc`, which runs a static initializer at launch.
   Vendoring only what the encoder needs is 9.9 MB of source, builds in 42 s (release) / 30 s (debug)
   from clean, and has one tiny static initializer (`enc_ans.cc`'s lookup tables). Vendored code is
   not edited (as `CJPEGXR`); our own files there are only the four generated headers.
3. **skcms, not lcms2,** as the colour engine (`JPEGXL_ENABLE_SKCMS=1`): one file, BSD, what the
   lossy encoder needs to bring an ICC profile into XYB.
4. **Options:** `lossless` (default off), `quality` 1–100 (default 90, libjxl's default distance 1.0,
   "visually lossless"), `effort` 1–9 (default 7, libjxl's default; 10 needs libjxl's expert mode,
   not offered), `keepMetadata` (default on). Field order `[.lossless, .quality, .effort, .keepMetadata]`
   (lossless first, as JPEG 2000). Quality maps through `JxlEncoderDistanceFromQuality`, but never
   below distance 0.1: libjxl gives 0 at quality 100, which is not lossless and not monotonic with 99 (0.19).
5. **Colour:** an RGB image with an ICC-based colour space is written in that space (its ICC
   profile; plain sRGB as libjxl's sRGB enum, no profile bytes); grey, CMYK, indexed and extended-range
   spaces are converted to sRGB. 8 bits per sample, or 16 when the image has more than 8 (16-bit PNG
   and TIFF saved lossless stay lossless). SDR only: HDR stays a HEIC/AVIF feature (spec "Formats").
6. **Alpha** is written only when the image has it, as premultiplied alpha
   (`alpha_premultiplied = 1`), straight from Core Graphics' premultiplied buffer (ImageIO decodes it
   right, Spike facts); an opaque image goes in as 3 channels.
7. **Metadata:** with "keep metadata", the source's `CGImageMetadata` (ImageIO's XMP view of
   EXIF/TIFF/GPS/IPTC) in the namespaces `tiff`, `exif`, `exifEX`, `aux`, `dc`, `photoshop`,
   `Iptc4xmpCore`, `Iptc4xmpExt`, minus `tiff:Orientation`, `exif:PixelXDimension`,
   `exif:PixelYDimension`, goes into one `xml ` box. No `Exif` box: the only way to get EXIF bytes
   from ImageIO is a 1×1 JPEG whose pixel dimensions are wrong, and the property-dictionary route
   through XMP turns rationals into truncated integers (FNumber 2.8 → 2). The codestream orientation
   is always 1 (pixels are upright). DPI is not written (JXL has no field for it).
8. **Speed and memory:** each encode uses libjxl's thread pool
   (`JxlThreadParallelRunnerDefaultNumWorkerThreads()`), and at most **2 JXL encodes run at once**
   in the process (a `DispatchSemaphore(value: 2)` inside `JXLEncoder`; batch work runs on GCD, not the
   cooperative pool, so blocking there is fine). One 12 MP encode peaks at about 550 MB; 9 parallel
   single-threaded encodes would need about 5 GB for 10 % more throughput.
9. **Lossless JPEG recompression** (JXL's JPEG transcoding, `JxlEncoderAddJPEGFrame`) is not in this
   milestone: it bypasses the pixel pipeline and needs its own UI. `JPEGXL_ENABLE_TRANSCODE_JPEG=0`.

## Spike facts (macOS 27.0.1, Apple Silicon, 10 cores; don't re-measure)

- `CGImageDestinationCopyTypeIdentifiers()` has no JXL type; `CGImageDestinationCreateWithData` for
  `public.jpeg-xl` (the type `UTType(filenameExtension: "jxl")` gives, and the one ImageIO reads)
  returns nil.
- Vendored libjxl 0.12.0 (`a7a9c787`, highway `457c8917`, brotli `028fb5a2`, skcms `96d9171c`) builds
  as one SwiftPM target with tools 6.0, Swift 6 caller, `cxxLanguageStandard: .cxx17`, no source
  edits. Needed: `JPEGXL_INTERNAL_{BASE,CMS,DEC,DEC_BOX,DEC_JPEG,ENC,THREADS}_SOURCES` from
  `lib/jxl_lists.cmake`; highway `hwy/` without tests, `contrib`, `examples`, `nanobenchmark.cc`;
  brotli `c/{common,enc,dec,include}` without `enc/static_init_lazy.cc` (it `#error`s unless
  `BROTLI_STATIC_INIT_LAZY`; brotli's default is no static init); skcms `skcms.cc`, `skcms.h`, `src/`.
  Header paths: `libjxl`, `libjxl/lib`, `highway`, `brotli/include`, `skcms`.
- Output decodes in ImageIO as `public.jpeg-xl`. Lossless 8-bit RGBA round-trips byte-exact. A Display
  P3 ICC profile comes back as "Display P3"; sRGB enum as "sRGB IEC61966-2.1". An `xml ` box built
  from a real iPhone JPEG's `CGImageSourceCopyMetadataAtIndex` gives back FNumber 1.6, ExposureTime
  0.02, DateTimeOriginal, LensModel, TIFF Model, GPS latitude exactly. Premultiplied alpha with the flag
  set decodes to the same premultiplied pixels. RGBA input for an image declared without alpha fails
  ("need 1 extra channel for alpha"): opaque images need 3-channel input.
- 12 MP iPhone photo (Display P3), quality 90 / effort 7: 1.4 s with the thread pool, 7.2 s without;
  quality 80 effort 3: 0.29 s; lossless effort 7: 2.5 s (5.3 MB; source JPEG 2.3 MB). Effort 9 lossy
  (synthetic 12 MP): 28 s single-threaded. Peak footprint of one threaded 12 MP encode: about 680 MB
  for the process (about 550 MB of it libjxl). Nine 12 MP encodes: 12.9 s one at a time, 10.1 s two at
  a time, 9.5 s three, 9.0 s nine single-threaded.
- Size: the encoder linked into an executable adds about 6.3 MB (release, dead-stripped); linking
  libjxl but calling almost nothing adds 240 KB. Process launch of a minimal binary linking libjxl vs
  not: 4.51 vs 4.23 ms median (includes libc++, which AppKit loads anyway).
- `JxlEncoderSetCodestreamLevel` defaults to -1 (picks level 5 or 10 itself), so huge images need
  nothing extra.

## Global Constraints

- macOS 14.0 minimum; Swift 6 strict concurrency.
- Dependency rule (`AGENTS.md`): permissive licence, built from source by SwiftPM (C target, no
  prebuilt binaries), used only when that format is written, no measurable cost to the launch,
  browsing and memory budgets; recorded in README.md with its licence.
- Vendored third-party code is not edited (as `Sources/CJPEGXR/jxrlib`).
- `FeatherviewCore` never imports SwiftUI or AppKit.
- Never rename an `OutputFormat.id` or a stored `FormatOptions` key once shipped. New id: `jxl`; no new
  option keys (`effort` is shared with WebP; each format stores its own options).
- Never lose user data: the encoder only returns bytes; `ImageSaver` and `BatchConverter` already write
  through a temp file and never overwrite in batch.
- User-facing errors are short sentences naming the file; the existing batch and Save As error paths
  cover a failed encode.
- Test images come from `Fixtures` or are generated in tests, never committed binaries.
- Conventional commits, no AI attribution, no dates in docs or comments; `shortcut:` comments as
  `shortcut: <limit>, <when to upgrade>`.

## Review Focus

- A grey or CMYK source (scanned TIFF, print PSD) saved as JPEG XL: converted to sRGB, written, reads
  back with the right size; never a thrown error. Pinned in Task 2 (`greyAndCMYKBecomeSRGB`).
- Batch of many 12 MP photos to JPEG XL on 9 workers: never more than 2 libjxl encodes at once, so
  memory stays near 1.1 GB instead of 5 GB. Pinned in Task 2 (`atMostTwoEncodesAtOnce`).
- A portrait iPhone photo (EXIF orientation 6) saved as JPEG XL with metadata: upright pixels, no
  orientation tag coming back other than 1, camera data and GPS kept. Pinned in Task 3
  (`rotatedPhotoKeepsMetadataUpright`).
- A batch with "change format" off over `.jxl` inputs (crop, resize): each is written back as JPEG XL
  with its stored options, not "Can't save … in its own format". Pinned in Task 3
  (`jxlInputsKeepTheirFormat`).
- A 16-bit PNG saved as lossless JPEG XL decodes to the same 16-bit pixels. Pinned in Task 2
  (`sixteenBitLosslessRoundTrips`).

---

## Wave plan

| Wave | Tasks | Why |
|---|---|---|
| A | 1 | the vendored library everything links |
| B | 2 | `JXLEncoder` (uses 1) |
| C | 3 | format, routing, metadata, options UI (uses 2) |
| D | 4 (main session) | screen check, budgets, docs |

---

### Task 1: Vendor libjxl as `CJPEGXL`

**Files:**
- Create: `Sources/CJPEGXL/` — `libjxl/lib/{jxl,threads}` (the source lists above), `libjxl/LICENSE`,
  `libjxl/PATENTS`, `include/jxl/*.h` (libjxl's public C headers from `lib/include/jxl`, without the
  `*_cxx.h` ones), `include/jxl/{jxl_export.h,jxl_cms_export.h,jxl_threads_export.h,version.h}` (ours,
  what CMake would generate: `*_EXPORT`/`*_NO_EXPORT` empty, `*_DEPRECATED` as
  `__attribute__((__deprecated__))`; version 0.12.0 with libjxl's `JPEGXL_COMPUTE_NUMERIC_VERSION`),
  `highway/{hwy,LICENSE,LICENSE-BSD3}`, `brotli/{common,enc,dec,include,LICENSE}`,
  `skcms/{skcms.cc,skcms.h,src,LICENSE}`
- Modify: `Package.swift`, `README.md` ("Third-party code"), `Resources/Acknowledgements.txt`
- Test: `Tests/FeatherviewCoreTests/Formats/JXLEncoderTests.swift` (created here with one test)

**Interfaces:**
- Produces: module `CJPEGXL` (libjxl's C API: `JxlEncoderCreate`, `JxlEncoderVersion`,
  `JxlThreadParallelRunner*`, …), a dependency of `FeatherviewCore`.

How to vendor (in the scratchpad, never inside the repo):

```sh
git clone --depth 1 --branch v0.12.0 https://github.com/libjxl/libjxl.git up
git -C up submodule update --init --depth 1 third_party/brotli third_party/highway third_party/skcms
```

then copy per the Spike facts (`rsync -R` of the files named in `lib/jxl_lists.cmake`'s seven lists).

`Package.swift` target (after `CJPEGXR`); `cSettings` and `cxxSettings` both get the header paths
`libjxl`, `libjxl/lib`, `highway`, `brotli/include`, `skcms` and the defines `JPEGXL_ENABLE_SKCMS=1`,
`JPEGXL_ENABLE_TRANSCODE_JPEG=0`, `JPEGXL_ENABLE_BOXES=1`, plus `-w`; `exclude` the licence files,
`brotli/enc/static_init_lazy.cc` and brotli's `dictionary.bin*` if SwiftPM warns about them; package
`cxxLanguageStandard: .cxx17`. Comment above it in the style of the jxrlib one: what, licence, upstream
tag and commit, "only JXLEncoder uses it".

- [ ] **Step 1: Write the failing test** `linksLibjxl`: `import CJPEGXL` in the test file (add
  `"CJPEGXL"` to the test target's dependencies if it doesn't resolve through `FeatherviewCore`);
  `#expect(JxlEncoderVersion() == 12000)`.
- [ ] **Step 2: Run** `swift test --filter JXLEncoderTests` → FAIL (no module).
- [ ] **Step 3: Vendor and wire** as above. README: "libjxl 0.12.0 (BSD-3-Clause), with highway
  (Apache-2.0 or BSD-3-Clause), brotli (MIT) and skcms (BSD-3-Clause), for writing JPEG XL, vendored
  in `Sources/CJPEGXL` and built from source by SwiftPM." Acknowledgements: each of the four licences
  and libjxl's PATENTS text, in the file's existing style.
- [ ] **Step 4: Run** `swift build` and `swift build -c release` → `Build complete!` with no warnings
  from our targets; `swift test --filter JXLEncoderTests` → PASS;
  `nm -m .build/release/featherview-bench | grep GLOBAL__sub_I` lists no highway or brotli file
  (`enc_ans.cc` is the expected one).
- [ ] **Step 5: Commit** `chore: vendor libjxl 0.12.0 for writing JPEG XL`

---

### Task 2: `JXLEncoder`

**Files:**
- Create: `Sources/FeatherviewCore/Formats/JXLEncoder.swift`
- Test: `Tests/FeatherviewCoreTests/Formats/JXLEncoderTests.swift`

**Interfaces:**
- Consumes: `CJPEGXL` (Task 1), `EncodeError.failed` (`Imaging/ImageEncoder.swift`).
- Produces: `public enum JXLEncoder` —
  `public static func encode(_ image: CGImage, quality: Int, lossless: Bool, effort: Int, xmp: Data?) throws -> Data`
  (quality clamped to 1...100 and ignored when lossless; effort clamped to 1...9; `xmp` goes into an
  `xml ` box when non-nil). `static let maxConcurrentEncodes = 2`; for tests, internal
  `static var peakInFlight: Int` (highest number of encodes inside the semaphore at once, kept under an
  `OSAllocatedUnfairLock`) and `static func resetPeakInFlight()`. Decisions 4–8 are its behaviour.

- [ ] **Step 1: Write the failing tests** (images drawn in the test with Core Graphics; read back with
  `CGImageSourceCreateWithData`):
  - `writesJXLImageIOReads`: 64×48 sRGB opaque, quality 90, effort 7 → type `"public.jpeg-xl"`, 64×48.
  - `losslessRoundTripsExactly`: 64×48 RGBA8 with varied opaque pixels → decoded pixels drawn into the
    same sRGB context are byte-equal.
  - `sixteenBitLosslessRoundTrips`: 16-bit RGB image with values not representable in 8 bits →
    decoded `bitsPerComponent == 16` and the same samples.
  - `qualityChangesSize`: quality 20 < quality 95 bytes; quality 100 (lossy) encodes and is ≥ quality 95.
  - `keepsDisplayP3`: image in Display P3 → `kCGImagePropertyProfileName` "Display P3"; sRGB image →
    "sRGB IEC61966-2.1".
  - `greyAndCMYKBecomeSRGB`: a grey and a CMYK `CGImage` → each encodes, decodes with the right size and
    an RGB colour model.
  - `keepsAlphaOnlyWhenPresent`: half-transparent image (lossless) → decoded alpha 128 at a test pixel;
    opaque image → decoded `alphaInfo` has no alpha.
  - `xmpBoxIsRead`: `xmp` built with `CGImageMetadataCreateXMPData` holding `exif:DateTimeOriginal`
    and `tiff:Model` → both come back in the decoded properties; `xmp: nil` → no EXIF dictionary.
  - `everyEffortEncodes` (arguments 1...9, 32×32) and `outOfRangeOptionsAreClamped` (effort 0 and 12,
    quality 0 and 500 → encode, no throw).
  - `atMostTwoEncodesAtOnce`: 6 concurrent encodes (`DispatchQueue.concurrentPerform`) of a 512×512
    image at effort 7, after `JXLEncoder.resetPeakInFlight()` → `JXLEncoder.peakInFlight <= 2`, and all
    6 outputs decode.
  - `parallelEncodesMatchASerialOne`: the same image encoded serially and in 6 parallel encodes →
    identical bytes.
- [ ] **Step 2: Run** `swift test --filter JXLEncoderTests` → FAIL (no `JXLEncoder`).
- [ ] **Step 3: Implement.** Draw `image` into a `CGContext` (premultipliedLast; 16-bit:
  `byteOrder16Little`, integer) in the image's colour space or sRGB (Decision 5); repack to RGB for
  opaque images; `JxlBasicInfo` with `uses_original_profile = lossless`; colour via
  `JxlColorEncodingSetToSRGB` or `JxlEncoderSetICCProfile`; `JxlEncoderSetFrameLossless` or
  `JxlEncoderSetFrameDistance(max(JxlEncoderDistanceFromQuality(q), 0.1))`;
  `JXL_ENC_FRAME_SETTING_EFFORT`; `JxlEncoderUseBoxes`/`JxlEncoderAddBox("xml ")`/`JxlEncoderCloseBoxes`
  when `xmp != nil`; `JxlPixelFormat` `JXL_TYPE_UINT8`/`UINT16`, native endian; thread runner created
  and destroyed per encode; output grown by doubling on `JXL_ENC_NEED_MORE_OUTPUT`. Every libjxl
  failure → `EncodeError.failed`. The semaphore wraps the whole libjxl part, not the drawing.
- [ ] **Step 4: Run** `swift test --filter JXLEncoderTests` → PASS.
- [ ] **Step 5: Commit** `feat: JPEG XL encoder through libjxl`

---

### Task 3: JPEG XL in Save As, batch and Settings › Formats

**Files:**
- Modify: `Sources/FeatherviewCore/Imaging/OutputFormat.swift` (`Writer.jxl`, the `jxl` format,
  `hidden` += `"public.jpeg-xl"`, `effortRange`), `Sources/FeatherviewCore/Imaging/ImageEncoder.swift`
  (`.jxl` case, `metadataXMP(of:)`), `Sources/Featherview/FormatOptionsView.swift` (effort slider
  uses `format.effortRange`), `Sources/FeatherviewCore/Formats/WebPEncoder.swift` only if the clamp
  moves to `effortRange` (keep its behaviour)
- Test: `Tests/FeatherviewCoreTests/Imaging/OutputFormatTests.swift`,
  `Tests/FeatherviewCoreTests/Batch/BatchConverterTests.swift`

**Interfaces:**
- Consumes: `JXLEncoder.encode(_:quality:lossless:effort:xmp:)` (Task 2).
- Produces:
  - `OutputFormat.Writer.jxl`; format `id "jxl"`, name `"JPEG XL"`, extension `jxl`,
    `optionFields [.lossless, .quality, .effort, .keepMetadata]`, defaults quality 90, effort 7,
    lossless false, keepMetadata true.
  - `public var OutputFormat.effortRange: ClosedRange<Int>` — `1...9` for `.jxl`, `0...6` otherwise.
  - `static func ImageEncoder.metadataXMP(of input: URL) -> Data?` — Decision 7; nil when the source
    has no metadata in those namespaces or can't be read.
  - `ImageEncoder.encode` `.jxl`: `JXLEncoder.encode(first, quality:, lossless:, effort:,
    xmp: options.keepMetadata ? source.flatMap(metadataXMP) : nil)`; `dpi` and `hdr` ignored.

No new UI strings: "Effort:", its help, "Lossless", "Quality:" and the keep-metadata toggle exist;
format names are not translated.

- [ ] **Step 1: Write the failing tests:**
  - `OutputFormatTests.jxlFollowsThePlan`: the format's id, name, extension, writer, fields and
    defaults as above; `type?.identifier == "public.jpeg-xl"`; exactly one writable format with
    extension `jxl`; `FormatRegistry.hidden.contains("public.jpeg-xl")`; `effortRange` 1...9 for JXL,
    0...6 for WebP. Add `"jxl"` to the `ids` list in the existing all-formats test.
  - `OutputFormatTests.jxlUsesItsOptions`: `ImageEncoder.encode([img], as: jxl, options: lossless)`
    round-trips exactly; quality 20 smaller than 95.
  - `OutputFormatTests.rotatedPhotoKeepsMetadataUpright`: a JPEG fixture with EXIF orientation 6,
    DateTimeOriginal, FNumber 2.8, TIFF Model and GPS (write it with ImageIO properties) → decode via
    `ImageSaver.pages`, encode as JXL with `metadataFrom:` → output width/height swapped (upright),
    `kCGImagePropertyOrientation` absent or 1, FNumber 2.8, Model and GPS latitude equal; with
    `keepMetadata = false` → no EXIF DateTimeOriginal.
  - `BatchConverterTests.jxlInputsKeepTheirFormat`: two `.jxl` inputs (made with `JXLEncoder`),
    `changeFormat = false`, a resize step → both succeed, outputs are `.jxl` and decode as
    `public.jpeg-xl`.
  - `BatchConverterTests.convertsToJXL`: a JPEG and a PNG with alpha, `changeFormat = true`, format
    `jxl` → both succeed with `.jxl` names.
- [ ] **Step 2: Run** `swift test --filter "OutputFormatTests|BatchConverterTests"` → FAIL.
- [ ] **Step 3: Implement.** `metadataXMP`: `CGImageSourceCopyMetadataAtIndex`, enumerate tags
  (`CGImageMetadataEnumerateTagsUsingBlock`) into a new mutable metadata keeping the namespaces of
  Decision 7, remove the three paths, `CGImageMetadataCreateXMPData`.
- [ ] **Step 4: Run** `swift test` → all PASS; `swift build -c release`; `scripts/bundle.sh release`.
  Record the size of `build/Featherview.app/Contents/MacOS/Featherview` and both `.appex` binaries
  before and after this branch in the commit body (the extensions must not grow: they never encode).
- [ ] **Step 5: Commit** `feat: Save As and batch write JPEG XL`

---

### Task 4: Screen check, budgets, docs (main session, screen)

Needs the maintainer's go (screen bursts). Sample folder: 20 12 MP JPEGs from
`featherview-bench corpus`, one portrait photo with orientation 6 and GPS, a transparent PNG, a 16-bit
TIFF.

- [ ] **Step 1: Check by hand** (release build): Save As offers "JPEG XL" with Lossless, Quality, Effort
  (1–9), keep metadata; the file opens in Featherview, Preview and Finder's Quick Look; Get Info / the
  info panel shows camera data and location; the portrait photo is upright; the transparent PNG keeps
  its transparency; Settings › Formats remembers JPEG XL options and profiles; a batch of the 20 JPEGs to
  JPEG XL completes, Activity Monitor's memory for Featherview stays under about 1.5 GB, and the batch
  window stays responsive.
- [ ] **Step 2: Measure budgets:** cold launch with a 12 MP JPEG after ⌘Q (< 410 ms, compared with
  `main` on the same Mac, five launches each); `featherview-bench decode` and `browse --interval-ms 30`
  against `--baseline` from `main` → no regression; memory while browsing unchanged. A measurable
  launch regression blocks the milestone (fallback to discuss with the maintainer: build `CJPEGXL` as a
  separate dynamic library loaded with `dlopen` on first JXL save).
- [ ] **Step 3: Docs:** spec "Formats": replace "Writing JPEG XL is v2 (…)" with "Write (open-source
  encoder, per `AGENTS.md`): WebP (libwebp, BSD), JPEG XL (libjxl, BSD)" and the colour, alpha, 16-bit
  and SDR-only rules of Decisions 5–7 in spec wording; "Format options" row
  `| JPEG XL | lossless, quality 1–100 (default 90), effort 1–9 (default 7), keep metadata (default on) |`;
  roadmap row 17 → this plan, `done`; README features line (writes JPEG XL); `AGENTS.md` Imaging row:
  "(today: WebP and JPEG XL encoding)" and the Layout line for `Sources/CJPEGXL/`.
- [ ] **Step 4: Commit** `docs: JPEG XL writing done after manual QA`
