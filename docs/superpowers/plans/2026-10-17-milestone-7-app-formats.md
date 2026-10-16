# Featherview v1 — Milestone 7 Implementation Plan (App formats)

> **Milestone 7** in `docs/roadmap.md`. Builds on milestone 3 (`2026-10-16-milestone-3-formats-save-as.md`),
> whose `OwnDecoders` registry, `RGBAImage`, `ByteReader` and Info.plist type declarations this extends.
> Independent of milestones 4, 5 and 6. Don't add anything from other milestones here (Finder previews
> for these formats are milestone 8).

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. In this repo, run it wave by wave with the `plan-wave` workflow.

**Goal:** Featherview opens Photoshop Large Documents (PSB), GIMP (XCF), Paint.NET (PDN) and
PaintShop Pro (PSP, PSPIMAGE) files and shows them flattened, through the same paths as every other
image: folder listing, viewer, batch input, info panel.

**Architecture:** PSB needs no decoder: ImageIO already reads its stored composite, only
`ImageFormats.isDecodable` rejects the extension. XCF, PDN and PSP get pure-Swift decoders in
`FeatherviewCore`, registered in `OwnDecoders.builtIn` like the milestone 3 decoders. They share two
new pieces: `Inflate` (zlib, gzip and raw deflate through Apple's Compression framework, sized
exactly, so a corrupt file can't inflate without bound) and `LayerCanvas` (normal source-over
compositing of one 8-bit straight-alpha layer at a time, with offset and opacity, clipped to the
canvas). Each decoder parses its container, turns each visible layer into an `RGBAImage`, draws it on
the canvas and drops it, so memory stays at the canvas plus one layer. A file that stores a full-size
composite uses it instead (PSP composite bank; PDN thumbnail when it is canvas-sized).

**Tech Stack:** Swift 6 (strict concurrency), SwiftPM, Compression framework (`compression_decode_buffer`,
`COMPRESSION_ZLIB` = raw DEFLATE), ImageIO (PSB, and JPEG-compressed PSP composites), Swift Testing.

**Spec:** `docs/spec.md` "Formats" (layered app formats, own decoders); `docs/parity.md` "Layered app
formats". Rules, budgets and commands: `AGENTS.md`. Read all three first.

**Reference material (gitignored, in the main checkout, read it by absolute path from a worktree):**

- Format specifications in `/Users/jm/Web/mx/featherview/research/appformats/specs/`:
  `xcf3.md` (GIMP's XCF spec, all versions up to 23), `psp6spec.txt` (PSP file format 4),
  `psp7spec.txt` (format 5), `psp8spec.txt` (format 8, which also says how 6 and 7 differ).
  PDN has no published spec: its body is a .NET BinaryFormatter stream, documented as MS-NRBF
  (https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-nrbf/); the PDN facts below come
  from looking at the bytes of the sample files.
- Real sample files with reference renderings in `/Users/jm/Web/mx/featherview/research/appformats/`
  (`xcf/`, `psb/`, `psp/`, `pdn/`, each with `ref/`), described file by file in its `INDEX.md`
  (properties, source, licence, quirks). Untrusted downloads: parse them, never execute anything.
  They are not committed and never will be (`AGENTS.md`: test images are generated in tests).
- Clean-room: read only the specs above and our own sample bytes. Never read another program's
  source for these formats (GIMP, Paint.NET plugins, kimageformats, pypdn, psd-tools, ImageMagick).

**Checked while planning (spikes, not committed):**

- PSB: `UTType(filenameExtension: "psb")` is `com.adobe.photoshop-large-image`, which conforms to
  `public.image` but not to `com.adobe.photoshop-image`, so `ImageFormats.isDecodable` says no.
  ImageIO decodes 19 of the 22 sample PSBs (8/16/32-bit RGB, gray, CMYK, duotone, raw and RLE).
  It fails on multichannel and on a zip-compressed composite; `pyaep_8bits.psb` has
  `hasRealMergedData = 0` (its stored composite isn't the real image). All three are known limits.
- XCF, PDN, PSP, PSPIMAGE have no system UTType (dynamic `dyn.` types), so Info.plist must import them.
  `public.image` in the existing document types already covers PSB.
- XCF: group layers store their own rendered projection in their hierarchy, so compositing only the
  top-level items (no `PROP_ITEM_PATH`, or a path of length 1) gives the image; children of a group are
  inside that projection. The maintainer's own XCFs are v011 and v023, normal mode only.
- PDN (every sample, Paint.NET 3.5 to 5.9): `PDN3` magic, 3-byte little-endian length of an XML header,
  the XML header (`<pdnImage width= height= layers= savedWithVersion=>` with a base64 PNG thumbnail at
  most 256 px on the long side in `<custom><thumb png="…">`), then two bytes `00 01`, then an NRBF stream
  ending in a MessageEnd record (`0x0B`), then the pixels of each deferred `PaintDotNet.MemoryBlock`:
  one byte format (`0` = gzip chunks), a big-endian UInt32 chunk size (`0x00040000` in every sample),
  then chunks of big-endian UInt32 chunk index, big-endian UInt32 byte length, and a gzip member,
  until the block's `length64` bytes are covered (the last chunk is shorter). Class and member names
  seen in the streams: `PaintDotNet.Document` (`layers`, `width`, `height`, `savedWith`),
  `PaintDotNet.LayerList` (`ArrayList+_items`, `ArrayList+_size`), `PaintDotNet.BitmapLayer`
  (`properties`, `surface`, `Layer+width`, `Layer+height`, `Layer+properties`),
  `PaintDotNet.Layer+LayerProperties` (`visible`, `isBackground`, `opacity`, `blendMode`, plus a name),
  `PaintDotNet.Surface` (`width`, `height`, `stride`, `scan0`), `PaintDotNet.MemoryBlock`
  (`length64`, `hasParent`, `deferred`). Paint.NET 3.5 has no `blendMode` member (only a `blendOp`
  object). Item 0 of the layer list is the bottom layer (the reference viewer shows it as page 2).
- The reference viewer shows all three flattened at the canvas size, a PSP whose only stored
  composite is a thumbnail from its layer, and draws an XCF group's Screen mode as Normal
  (`docs/parity.md`).

## Global Constraints

- macOS 14.0 minimum; Swift 6 language mode, strict concurrency.
- No new dependency: pure Swift plus Apple frameworks (Compression, ImageIO) only.
- `FeatherviewCore` never imports SwiftUI or AppKit.
- Decoders are pure functions of the file's bytes (`Data`, memory-mapped by `ImageDecoder`); they
  never touch other files, and read only the bytes they need (`ByteReader`, no copy of the file).
- Every read is bounds-checked (`ByteReader` throws `.truncated`); every size goes through
  `checkedSize` (256 MP cap) before an allocation; every pointer or offset into the file is checked
  against the file's length; every inflate is to an exact, pre-computed size. A bad file throws an
  `OwnDecodeError`, never traps, hangs or allocates more than the canvas it claims.
- Blending: visible layers composited with normal (source-over) blending and their opacity; any other
  blend mode is drawn as normal (spec: a known limit, listed in README). Hidden layers are skipped.
- Output is `RGBAImage` (8-bit sRGB, straight alpha). Higher bit depths and linear-light data are
  converted to 8-bit sRGB.
- User-facing errors stay the existing "Can't open <name>"; never a raw error dump.
- TDD for `FeatherviewCore`; test files are built byte by byte in tests (like `ILBMDecoderTests`),
  never committed binaries. The sample corpus is checked by an opt-in suite (Task 1) that is skipped
  when the samples aren't on disk.
- Commit messages: conventional commits, no AI attribution lines, no dates in docs or comments.
- Keep `shortcut:` comments for known limits, in the form `shortcut: <limit>, <when to upgrade>`.

## Review Focus

- A crafted or damaged file (pointers past the end or pointing back at themselves, a layer claiming
  60,000 × 60,000 pixels, a zlib stream that inflates to gigabytes, an NRBF object nested 100,000 deep):
  "Can't open <name>", no crash, no hang, no huge allocation. Pinned in each decoder task
  (`truncatedAtEveryLengthThrows`, `pointerPastTheEndThrows`, `hugeLayerThrows`) and in Task 1
  (`inflateRefusesMoreThanExpected`).
- A big real file (the maintainer's 2–56 MB XCFs, the 2048 × 2048 nine-layer `mooney_texture`) decodes
  off the main thread in well under a second in a release build, holding the canvas plus one layer,
  not every layer at once. Pinned by `LayerCanvas` drawing one layer at a time (Task 1) and measured in
  Task 6.
- A layer partly or wholly outside the canvas (negative offsets, offsets past the edge, a layer
  bigger than the canvas): clipped, the rest of the image right. Pinned in Task 1 (`clipsLayersOutsideTheCanvas`)
  and Task 3 (`negativeOffsetsAreClipped`).
- Semi-transparent layers over a transparent canvas: the straight-alpha result has no dark fringes
  and matches what the app shows for a PNG of the same pixels. Pinned in Task 1 (`halfOpaqueOverTransparent`).
- A 16-bit, float or linear-light XCF looks the same as its 8-bit version, not darker. Pinned in
  Task 3 (`linearLightLooksLikeGamma`) and by the corpus rows for the `gen_rgba_layers_*` files.

---

## Wave plan

| Wave | Tasks | Why |
|---|---|---|
| A | 1 | shared pieces every decoder uses |
| B | 2, 3, 4, 5 | independent formats, parallel (each adds one line to `OwnDecoders.builtIn`; merge keeps all) |
| C | 6 | app integration, docs, measurements (needs every format) |

---

### Task 1: Inflate, LayerCanvas and the sample corpus suite

**Files:**
- Create: `Sources/FeatherviewCore/Inflate.swift`
- Create: `Sources/FeatherviewCore/LayerCanvas.swift`
- Test: `Tests/FeatherviewCoreTests/InflateTests.swift`, `Tests/FeatherviewCoreTests/LayerCanvasTests.swift`
- Create: `Tests/FeatherviewCoreTests/SampleCorpus.swift` (helpers, no tests of its own yet)

**Interfaces:**
- Consumes: `RGBAImage`, `OwnDecodeError`, `checkedSize` (`Sources/FeatherviewCore/RGBAImage.swift`).
- Produces:
  - `enum Inflate` with
    `static func zlib(_ bytes: ArraySlice<UInt8>, size: Int) throws -> [UInt8]` (RFC 1950: 2-byte
    header, deflate, Adler-32 trailer),
    `static func gzip(_ bytes: ArraySlice<UInt8>, size: Int) throws -> [UInt8]` (RFC 1952 member:
    header with optional FEXTRA / FNAME / FCOMMENT / FHCRC fields, deflate, CRC-32 and size trailer),
    `static func raw(_ bytes: ArraySlice<UInt8>, size: Int) throws -> [UInt8]` (RFC 1951).
    Each returns exactly `size` bytes or throws `OwnDecodeError.corrupt` (header wrong, stream too
    short, or more output than `size`) / `.truncated` (input ends inside a header).
  - `struct LayerCanvas` with `init(width: Int, height: Int) throws` (transparent, `checkedSize`),
    `mutating func draw(_ layer: RGBAImage, x: Int, y: Int, opacity: Double)` (source-over, straight
    alpha, `opacity` 0…1 multiplies the layer's alpha, `x`/`y` may be negative or past the edge),
    and `var image: RGBAImage`.
  - Test helpers in `SampleCorpus.swift`: `enum SampleCorpus` with
    `static let root: URL?` (from the environment variable `FEATHERVIEW_SAMPLES`, nil when unset or
    missing), `static var isAvailable: Bool`,
    `static func reference(for file: URL) -> URL` (`<folder>/ref/<file name>.png`),
    `static func difference(_ a: RGBAImage, _ b: RGBAImage) -> Double` (both composited over white,
    mean absolute difference per channel, 0…255; sizes must match or it returns `.infinity`).

Facts to pin:

- `COMPRESSION_ZLIB` in Apple's Compression framework is raw DEFLATE (RFC 1951) without the zlib
  header or trailer, so `zlib` and `gzip` strip their wrappers and hand the deflate bytes to
  `compression_decode_buffer`. Decode into a buffer of `size + 1` bytes: a result of `size + 1` means
  the stream holds more than expected (a bomb or a wrong size) and is `.corrupt`; less than `size`
  is `.corrupt` too. A zero-length result is also what the function returns on error.
- `// shortcut: the Adler-32 / CRC-32 trailers aren't checked (a corrupt stream almost always fails to inflate to the exact size), check them if a file decodes to garbage.`
- Compositing in straight alpha, per channel, with `a_s` = layer alpha × opacity and `a_d` = canvas alpha
  (both 0…1): `a_o = a_s + a_d (1 − a_s)`; `c_o = (c_s a_s + c_d a_d (1 − a_s)) / a_o` (0 when `a_o` = 0);
  round to nearest. Work row by row on the clipped intersection with `withUnsafeMutableBufferPointer`
  (a 12 MP layer must draw in tens of milliseconds in a release build, not seconds).

- [ ] **Step 1: Write the failing tests** — `InflateTests`:
  - `zlibRoundTrip`: bytes compressed in the test (`compression_encode_buffer` + a hand-written zlib
    header `78 9C` + Adler-32 computed in the test) inflate back exactly.
  - `gzipRoundTrip` and `gzipWithFileNameField`: a gzip member with FNAME set (bytes built in the test)
    inflates back.
  - `rawRoundTrip`.
  - `inflateRefusesMoreThanExpected`: 1 MB of zeros compressed, asked for `size: 1000` → `.corrupt`.
  - `inflateRefusesLessThanExpected`: asked for more than the stream holds → `.corrupt`.
  - `badZlibHeaderThrows` (`(CMF × 256 + FLG) % 31 ≠ 0`, or CM ≠ 8, or FDICT set) and
    `badGzipMagicThrows`.
  `LayerCanvasTests`:
  - `opaqueLayerReplaces`, `halfOpaqueOverTransparent` (red at alpha 255 drawn with opacity 0.5 on an
    empty canvas → (255, 0, 0, 128), not a darkened red), `halfOpaqueOverWhite` (→ (255, 128, 128, 255) ±1),
    `layerAlphaTimesOpacity`, `zeroOpacityLeavesCanvas`.
  - `clipsLayersOutsideTheCanvas`: offsets (−2, −1), (canvas width − 1, 0), (1000, 1000), and a layer
    larger than the canvas on every side; only the overlap changes, no trap.
  - `canvasRefusesHugeSizes`: `LayerCanvas(width: 70000, height: 10)` throws `.corrupt`.
  `SampleCorpus` gets a test only in the format tasks; here add one smoke test
  `differenceOfIdenticalImagesIsZero` (in `LayerCanvasTests`).
- [ ] **Step 2: Run them to see them fail.** `swift test --filter "InflateTests|LayerCanvasTests"`
- [ ] **Step 3: Implement** `Inflate`, `LayerCanvas`, `SampleCorpus` to the interfaces above.
- [ ] **Step 4: Run the tests, then the full suite.** `swift test`
- [ ] **Step 5: Commit.** `feat: inflate and layer compositing for the layered app formats`

---

### Task 2: PSB through ImageIO

**Files:**
- Modify: `Sources/FeatherviewCore/ImageFormats.swift` (`isDecodable`)
- Test: `Tests/FeatherviewCoreTests/ImageDecoderTests.swift` (or a new `PSBTests.swift`), plus a corpus test

**Interfaces:**
- Consumes: `ImageFormats.isDecodable`, `ImageDecoder` (unchanged), `SampleCorpus` (Task 1).
- Produces: `.psb` files list in folders, open, batch-convert and show dimensions in the info panel
  through ImageIO, like `.psd`.

Fact to pin: map the extension `psb` to `psd` before the UTType lookup, next to the existing
`jfif` mapping (same comment style), so the conformance check accepts it. Don't add a second UTType
list. ImageIO itself reads the file by content.

- [ ] **Step 1: Write the failing tests.**
  - `psbIsDecodable`: `ImageFormats.isDecodable(URL(fileURLWithPath: "/x/a.psb"))` and `A.PSB`.
  - `decodesAHandBuiltPSB`: a minimal PSB built in the test and written to a temp `.psb` file —
    header `8BPS`, version **2**, 6 reserved zero bytes, channels 3, height 2, width 3, depth 8, mode 3
    (RGB); colour mode data length UInt32 0; image resources length UInt32 0; layer and mask
    information length **UInt64** 0 (PSB widens this one to 8 bytes); image data compression UInt16 0
    (raw) followed by the red plane, the green plane, the blue plane (big-endian throughout).
    `ImageDecoder` decodes it to 3 × 2 with the planes' colours, and `MetadataReader.fields` gives
    "3 × 2". Check the built bytes against the Photoshop file format spec you know before trusting a
    failure; if ImageIO refuses this minimal file, add a minimal image resources section
    and say so in the commit.
  - Corpus (`@Test(.enabled(if: SampleCorpus.isAvailable))`, `psbCorpusMatchesReferences`): every
    file in `psb/` except the known limits `kimg_mch3-8bits.psb`, `kimg_mch3-16bits.psb`,
    `gen_im_rgba8_zip.psb` decodes through `ImageDecoder` at full size and its `difference` to
    `ref/<name>.png` is below 2 (`pyaep_8bits.psb` only has to decode: its stored composite isn't the
    real image); the three known limits throw, never trap.
- [ ] **Step 2: Run to see them fail.** `swift test --filter PSB`
- [ ] **Step 3: Implement** the mapping.
- [ ] **Step 4: Run the tests with the corpus, then the full suite.**
  `FEATHERVIEW_SAMPLES=/Users/jm/Web/mx/featherview/research/appformats swift test --filter PSB`, `swift test`
- [ ] **Step 5: Commit.** `feat: open Photoshop Large Documents (PSB) through ImageIO`

---

### Task 3: XCF decoder (GIMP)

**Files:**
- Create: `Sources/FeatherviewCore/XCFDecoder.swift`
- Modify: `Sources/FeatherviewCore/OwnDecoders.swift` (add `XCFDecoder.format` to `builtIn`)
- Modify: `Tests/FeatherviewCoreTests/OwnDecodersTests.swift` (`builtInDecodersCoverTheSpec` gets `xcf`)
- Test: `Tests/FeatherviewCoreTests/XCFDecoderTests.swift`

**Interfaces:**
- Consumes: `ByteReader`, `RGBAImage`, `checkedSize`, `OwnFormat.raster`, `Inflate.zlib`, `LayerCanvas`.
- Produces: `enum XCFDecoder` with `static let format: OwnFormat` (name "GIMP XCF", extensions `["xcf"]`),
  `static func size(_ data: Data) throws -> (width: Int, height: Int)` (header only),
  `static func decode(_ data: Data) throws -> RGBAImage`.

Behaviour (from `specs/xcf3.md`; read its sections "The image structure", "The layer structure",
"The hierarchy structure", "Tile data organization" first):

- Header `gimp xcf ` + `file` (version 0) or `v` + 3 digits, a NUL, width, height, base type
  (0 RGB, 1 grayscale, 2 indexed), precision for version ≥ 4, then image properties, then layer pointers
  (topmost first, 0-terminated). Pointers are 32-bit before version 11 and 64-bit from version 11.
- Properties: type, length, payload. Use `PROP_COLORMAP` (indexed palette), `PROP_COMPRESSION`
  (0 none, 1 RLE, 2 zlib; others → `.unsupported`); skip every other property by its length. One known
  quirk (sample `commons_Afghanistan34Provinces-xx_numbering.xcf`): `PROP_USER_UNIT`'s length field
  is smaller than its payload, and GIMP reads the payload by its fields, not the length. Parse
  `PROP_USER_UNIT` by its fields too (see the spec). `PROP_COLORMAP` with a wrong length on an RGB image
  (`commons_Japan-prefecture-maps.xcf`): ignore the colormap on non-indexed images.
- Layer properties used: `PROP_VISIBLE`, `PROP_OPACITY` / `PROP_FLOAT_OPACITY` (float wins),
  `PROP_OFFSETS` (signed), `PROP_APPLY_MASK`, `PROP_GROUP_ITEM`, `PROP_ITEM_PATH`, `PROP_MODE` (read
  only to note it; every mode is drawn as normal). Composite only top-level items, bottom first
  (reverse of the pointer order): a group's hierarchy is its rendered projection.
- Layer mask: if present and `PROP_APPLY_MASK` is on, multiply the layer's alpha by the mask (a channel
  structure whose hierarchy is one gray channel at the image precision).
- Hierarchy → first level only → tiles of 64 × 64 (edge tiles smaller), row-major. A tile's data ends
  at the next tile pointer (the last one at the end of the file). RLE: per byte plane of the pixel,
  opcodes as in the spec; a run past the tile's plane size is `.corrupt`. zlib: `Inflate.zlib` to
  exactly tile pixels × bpp.
- Pixels: big-endian components of 1, 2, 4 or 8 bytes (integer, half, float, double), RGB / gray /
  indexed, with or without alpha, alpha last. Convert to 8-bit sRGB: integers scale, floats clamp to
  0…1, linear-light precisions (100, 200, 300, 500, 600, 700, and the version 4–6 tables in the
  spec) go through the sRGB transfer function on colour (not alpha). Convert half floats by hand
  (sign, 5-bit exponent, 10-bit mantissa, subnormals) rather than with `Float16`, which doesn't exist on
  Intel Macs. Version 7–11 files with more than 8 bits are development versions with undefined byte
  order → `.unsupported`. Indexed: palette lookup, alpha < 128 transparent, ≥ 128 opaque.
- Known limits, each as a `shortcut:` comment: blend modes other than normal drawn as normal; layer
  effects (version 20+) not applied (the stored pixels are pre-effect); `.xcf.gz` / `.xcf.bz2` not
  read (the extension is `gz`, which isn't an image); text layers show their stored pixels (correct).

- [ ] **Step 1: Write the failing tests.** Build XCF files in the test with a small `XCFBuilder`
  (image size, base type, precision, version, compression, layers with size, offsets, opacity,
  visibility, mask, group flag, pixels): a 32-bit-pointer version 0 file and a 64-bit-pointer
  version 11 file. Tests:
  - `oneOpaqueRGBLayer` (v0, uncompressed), `rleTiles` and `zlibTiles` on a 70 × 66 layer (edge tiles),
    `twoLayersWithOffsetAndOpacity` (top layer at (2, 1), 50 %; result equals `LayerCanvas` doing it),
    `hiddenLayerIsSkipped`, `grayWithAlpha`, `indexedWithAlphaThreshold`,
    `appliedMaskMultipliesAlpha` and `maskNotAppliedIsIgnored`, `groupDrawsItsProjectionNotItsChildren`
    (children deliberately different from the group's pixels), `negativeOffsetsAreClipped`,
    `sixteenBitGamma`, `halfFloatLinear`, `doubleGamma`,
    `linearLightLooksLikeGamma` (the same colours stored as u16 linear and u8 gamma decode within ±1),
    `sizeReadsHeaderOnly` (a file truncated after the header still reports its size),
    `userUnitLengthQuirk` (a `PROP_USER_UNIT` whose length field is 16 while the payload is longer; the
    layer after it still decodes).
  - Hostile input: `truncatedAtEveryLengthThrows` (every prefix of a small two-layer file throws, never
    traps), `pointerPastTheEndThrows`, `pointerLoopThrows` (a tile or layer pointer pointing at the header),
    `hugeLayerThrows` (a layer claiming 60,000 × 60,000 in a 1 KB file), `unknownCompressionThrows`,
    `notXCFIsNotThisFormat`.
  - Corpus (`.enabled(if: SampleCorpus.isAvailable)`, `xcfCorpusMatchesReferences`): every `.xcf` in
    `xcf/` decodes; files whose layers are all normal mode (`INDEX.md` "modes" 0 or 28, see the table)
    and visible-or-hidden only must be within `difference` < 3 of `ref/<name>.png`; files with other modes
    only need the right size. Print each file's difference so the reviewer sees them.
- [ ] **Step 2: Run to see them fail.** `swift test --filter XCFDecoderTests`
- [ ] **Step 3: Implement** `XCFDecoder` and register it.
- [ ] **Step 4: Run the tests with the corpus, then the full suite.**
  `FEATHERVIEW_SAMPLES=/Users/jm/Web/mx/featherview/research/appformats swift test --filter XCF`, `swift test`
- [ ] **Step 5: Commit.** `feat: open GIMP XCF files, flattened`

---

### Task 4: PSP decoder (PaintShop Pro)

**Files:**
- Create: `Sources/FeatherviewCore/PSPDecoder.swift`
- Modify: `Sources/FeatherviewCore/OwnDecoders.swift` (add `PSPDecoder.format`)
- Modify: `Tests/FeatherviewCoreTests/OwnDecodersTests.swift` (`psp`, `pspimage`)
- Test: `Tests/FeatherviewCoreTests/PSPDecoderTests.swift`

**Interfaces:**
- Consumes: `ByteReader`, `RGBAImage`, `checkedSize`, `OwnFormat.raster`, `Inflate.zlib`, `LayerCanvas`,
  ImageIO (`CGImageSourceCreateWithData`) for JPEG-compressed composites, `RGBAImage.init?(CGImage)`.
- Produces: `enum PSPDecoder` with `static let format: OwnFormat` (name "PaintShop Pro", extensions
  `["psp", "pspimage"]`), `static func size(_ data: Data) throws -> (width: Int, height: Int)`,
  `static func decode(_ data: Data) throws -> RGBAImage`.

Behaviour (from `specs/psp6spec.txt`, `psp7spec.txt`, `psp8spec.txt`; little-endian throughout):

- File header: the 32-byte signature `Paint Shop Pro Image File\n\x1a` padded with NULs, major and
  minor format version (UInt16). Supported: major 4 and up (PaintShop Pro 6 and later; the samples have
  4, 6, 7, 8, 9, 10, 12). Major 3 (PSP 5) uses another block header → `.unsupported`
  (`shortcut:` comment; no sample exists).
- Blocks: `~BK\0`, block id (UInt16), total block length (UInt32). Format 8 and up begin most blocks and
  chunks with their own chunk length; the spec of each version says which. Skip unknown blocks by length.
- General Image Attributes block: width, height, compression (0 none, 1 RLE, 2 LZ77, 3 JPEG), bit
  depth, greyscale flag, layer count.
- Use, in this order: (1) a Composite Image Bank entry of type composite (not thumbnail) at the full
  canvas size, (2) otherwise the Layer Bank: raster layers (and floating raster) bottom to top as the
  spec orders them, at their image rectangle, with their opacity and visibility flag; a layer's saved
  rectangle inside its image rectangle carries the channels; colour channels plus the transparency
  channel (bitmap type "transparency mask") as alpha. Channel compression none, RLE (PSP's own run
  length, see the spec), LZ77 (= a zlib stream, `Inflate.zlib` to the channel's uncompressed length).
  Paletted layers (1, 4, 8 bit) use the palette block; greyscale images replicate the channel.
  JPEG composites decode through ImageIO.
- Known limits as `shortcut:` comments: vector, adjustment, mask and art-media layers skipped (the
  composite bank, when present, already includes them); user masks ignored; blend modes drawn as normal;
  16-bit-per-channel images `.unsupported` unless the spec makes them trivial. Groups: honour a hidden
  group (its layers hidden) and the group's opacity if the spec of that version says which layers belong to
  it; otherwise composite the layers flat and note the limit.

- [ ] **Step 1: Write the failing tests.** A `PSPBuilder` in the test writes format 4 and format 8 files:
  attributes block, optional composite bank (full-size composite and a smaller thumbnail), layer bank
  with raster layers (rectangles, opacity, visibility, transparency channel), compression none / RLE / LZ77.
  Tests: `usesFullSizeCompositeWhenStored`, `ignoresThumbnailOnlyBankAndUsesLayers` (bank with a
  thumbnail only, like `pdnpsp_Sunset_PSP12.pspimage`), `twoLayersWithOpacity`, `hiddenLayerIsSkipped`,
  `layerRectangleOffset` (a layer smaller than the canvas, placed off origin), `transparencyChannelIsAlpha`,
  `rleChannel`, `lz77Channel`, `palettedLayer`, `greyscale`, `format8BlockChunkLengths`,
  `formatThreeIsUnsupported`, `sizeReadsHeaderOnly`.
  Hostile input: `truncatedAtEveryLengthThrows`, `blockLengthPastTheEndThrows`, `hugeLayerThrows`,
  `lz77BombThrows` (a channel whose stream inflates past its stated length), `notPSPIsNotThisFormat`.
  Corpus (`pspCorpusMatchesReferences`): every file in `psp/` decodes within `difference` < 3 of
  `ref/<name>.png` (GIMP's flatten); list any file that can't meet it with the reason in the test and the
  commit message (for example a vector layer GIMP renders and we skip).
- [ ] **Step 2: Run to see them fail.** `swift test --filter PSPDecoderTests`
- [ ] **Step 3: Implement** `PSPDecoder` and register it.
- [ ] **Step 4: Run the tests with the corpus, then the full suite.**
  `FEATHERVIEW_SAMPLES=/Users/jm/Web/mx/featherview/research/appformats swift test --filter PSP`, `swift test`
- [ ] **Step 5: Commit.** `feat: open PaintShop Pro (PSP, PSPIMAGE) files, flattened`

---

### Task 5: PDN decoder (Paint.NET)

**Files:**
- Create: `Sources/FeatherviewCore/NRBFReader.swift` (generic MS-NRBF object graph reader)
- Create: `Sources/FeatherviewCore/PDNDecoder.swift`
- Modify: `Sources/FeatherviewCore/OwnDecoders.swift` (add `PDNDecoder.format`)
- Modify: `Tests/FeatherviewCoreTests/OwnDecodersTests.swift` (`pdn`)
- Test: `Tests/FeatherviewCoreTests/NRBFReaderTests.swift`, `Tests/FeatherviewCoreTests/PDNDecoderTests.swift`

**Interfaces:**
- Consumes: `ByteReader`, `RGBAImage`, `checkedSize`, `OwnFormat.raster`, `Inflate.gzip`, `LayerCanvas`,
  ImageIO for the PNG thumbnail.
- Produces:
  - `struct NRBFReader` — `static func read(_ reader: inout ByteReader) throws -> NRBFGraph`, reading
    records until MessageEnd and leaving `reader` just after it. `struct NRBFGraph` with
    `objects: [Int32: NRBFObject]`, `root: Int32`, `order: [Int32]` (object ids in the order their
    records appeared). `enum NRBFValue { case null, bool(Bool), int(Int64), uint(UInt64), double(Double),
    string(String), reference(Int32), array([NRBFValue]), bytes([UInt8]) }`;
    `struct NRBFObject { let className: String; let members: [String: NRBFValue] }` (arrays are objects
    whose `members` hold `"items"`).
  - `enum PDNDecoder` with `static let format: OwnFormat` (name "Paint.NET", extensions `["pdn"]`),
    `static func size(_ data: Data) throws -> (width: Int, height: Int)` (XML header only),
    `static func decode(_ data: Data) throws -> RGBAImage`.

Behaviour:

- NRBF (MS-NRBF sections 2.1–2.7): records SerializedStreamHeader (0), ClassWithId (1),
  SystemClassWithMembers (2), ClassWithMembers (3), SystemClassWithMembersAndTypes (4),
  ClassWithMembersAndTypes (5), BinaryObjectString (6), BinaryArray (7), MemberPrimitiveTyped (8),
  MemberReference (9), ObjectNull (10), MessageEnd (11), BinaryLibrary (12), ObjectNullMultiple256 (13),
  ObjectNullMultiple (14), ArraySinglePrimitive (15), ArraySingleObject (16), ArraySingleString (17).
  Classes without member types (2, 3) can't be read without type info → `.unsupported` (BinaryFormatter
  writes types by default; no sample has them). ClassWithId reuses an earlier class's metadata by id.
  Strings carry a 7-bit variable-length prefix. Primitive types per section 2.1.2.3. Limits: nesting
  depth 64, at most 1,000,000 records, every length checked against `reader.remaining`.
- PDN container: as in "Checked while planning". `size` parses only the XML header's `width` and
  `height` attributes (a tiny attribute scan, no XML parser needed; `XMLParser` is fine too).
- Image: if the XML thumbnail PNG decodes to exactly the canvas size, use it (spec: a full-size stored
  composite is used; Paint.NET renders it with all blend modes). Otherwise: follow
  `Document.layers` → `LayerList` → `ArrayList+_items` (first `ArrayList+_size` entries, bottom first) →
  each `BitmapLayer`'s `properties` (visible, opacity 0…255) and `surface` → `Surface` (`width`,
  `height`, `stride`, `scan0` → `MemoryBlock`). After MessageEnd come the deferred blocks, one per
  `MemoryBlock` with `deferred = true`, in the order those objects appear in the stream (`order`);
  confirm the order on `pypdn_FlattenBlendTest.pdn`, whose layers differ. Read each block's chunks
  (any order, by index; each `Inflate.gzip` to `min(chunkSize, length64 − index × chunkSize)`), check
  every chunk arrives once. Pixels are BGRA, 4 bytes per pixel, rows `stride` apart; check against the
  samples whether alpha is straight (expected) or premultiplied. Draw visible layers on `LayerCanvas`
  with their opacity, one layer at a time.
- Known limits as `shortcut:` comments: blend modes drawn as normal; a body not starting `00 01`
  (older Paint.NET 2.x) `.unsupported`. Layers are not shown as separate pages (the reference viewer
  does; the maintainer chose flattened only), so no shortcut comment for that.

- [ ] **Step 1: Write the failing tests.** `NRBFReaderTests` with records built byte by byte:
  `headerAndEnd`, `classWithMembersAndTypes` (int, bool, double, string members), `classWithIdReusesMetadata`,
  `memberReferenceResolves`, `arraySinglePrimitiveBytes`, `arraySingleObject`, `binaryArray`,
  `objectNullMultiple`, `classWithoutTypesIsUnsupported`, `deepNestingThrows`, `hugeStringLengthThrows`,
  `truncatedAtEveryLengthThrows`. `PDNDecoderTests` with a small `PDNBuilder` in the test (XML header
  with or without thumbnail, an NRBF graph with the classes and members above, deferred gzip chunks):
  `sizeFromXMLHeader`, `usesCanvasSizedThumbnail`, `ignoresSmallThumbnailAndUsesLayers`,
  `twoLayersBottomFirst`, `hiddenLayerIsSkipped`, `layerOpacity`, `chunksInAnyOrder`,
  `missingChunkThrows`, `duplicateChunkThrows`, `chunkBombThrows`, `strideLargerThanRow`,
  `truncatedAtEveryLengthThrows`, `hugeCanvasThrows`, `notPDNIsNotThisFormat`.
  Corpus (`pdnCorpusMatchesReferences`): every file in `pdn/` decodes; `pypdn_oldPDN3510.pdn` within
  `difference` < 3 of `ref/pypdn_oldPDN3510.png`; every file, scaled down to its thumbnail's size, within
  < 6 of `ref/<name>.pdn.thumb.png` except files using other blend modes (only `pypdn_FlattenBlendTest.pdn`;
  check its layers' blend modes and keep it in the list only if some aren't normal).
- [ ] **Step 2: Run to see them fail.** `swift test --filter "NRBFReaderTests|PDNDecoderTests"`
- [ ] **Step 3: Implement** `NRBFReader`, `PDNDecoder`, register it.
- [ ] **Step 4: Run the tests with the corpus, then the full suite.**
  `FEATHERVIEW_SAMPLES=/Users/jm/Web/mx/featherview/research/appformats swift test --filter "NRBF|PDN"`, `swift test`
- [ ] **Step 5: Commit.** `feat: open Paint.NET (PDN) files, flattened`

---

### Task 6: Finder types, docs and measurements

**Files:**
- Modify: `Resources/Info.plist` (document type "Other image" + imported type declarations)
- Modify: `README.md` (formats list, known limits)
- Modify: `docs/roadmap.md` (milestone 7 status), this plan (ticks)

**Interfaces:**
- Consumes: every format above.
- Produces: Featherview in Finder's Open With for `.xcf`, `.pdn`, `.psp`, `.pspimage`, `.psb`, ranked
  Alternate (never the default).

- [ ] **Step 1: Info.plist.** Add imported types following the existing `net.mynetx.featherview.qoi`
  entry: `net.mynetx.featherview.xcf` ("GIMP image", `xcf`), `net.mynetx.featherview.pdn`
  ("Paint.NET image", `pdn`), `net.mynetx.featherview.psp` ("PaintShop Pro image", `psp`, `pspimage`),
  each conforming to `public.image` and `public.data`; add the three to the "Other image" document
  type's `LSItemContentTypes`. PSB is already covered by `public.image`.
- [ ] **Step 2: Check registration.** `scripts/bundle.sh release`, then
  `/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f build/Featherview.app`
  and `lsregister -dump | grep -A3 featherview.xcf`; Finder › a sample `.xcf` › Open With lists
  Featherview and the default app is unchanged.
- [ ] **Step 3: README.** Add PSB, XCF, PDN, PSP to "Also reads formats macOS can't" (PSB is read by
  macOS but wasn't offered; list it with the layered formats) and a short known-limits line: layered
  files are shown flattened; blend modes other than normal are drawn as normal; PSB without a stored
  composite, multichannel PSB and XCF layer effects aren't shown; `.xcf.gz` isn't read.
- [ ] **Step 4: Measure** (release build, `run-featherview` skill, the maintainer's Mac only when they
  agree to GUI use): open `research/appformats/xcf/mooney_texture.xcf.gz` unpacked
  (`gunzip -k` into the scratchpad), the largest maintainer XCF (`mdfind -name .xcf`; read-only, never copy
  into the repo or share screenshots) and `pdnpsp_Marble_head.PspImage`; note each file's time to appear
  from the per-image log and the app's memory. Expectation: well under a second for the 2048 × 2048
  nine-layer file; memory within the browsing budget plus one canvas. A miss is a bug in this milestone.
- [ ] **Step 5: Browse the corpus in the app.** Open `research/appformats/xcf/` and step through every
  file with →; then `psp/`, `pdn/`, `psb/`. Every file shows or says "Can't open <name>" (only the known
  limits may); the info panel shows dimensions; batch-convert one folder to PNG and spot-check output.
- [ ] **Step 6: Docs and commit.** Tick this plan, set milestone 7 to done in `docs/roadmap.md`.
  `docs: milestone 7 done; Finder lists Featherview for XCF, PDN and PSP`
