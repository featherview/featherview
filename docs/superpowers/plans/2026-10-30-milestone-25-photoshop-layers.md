# Milestone 25: Photoshop layers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: run with the `plan-wave` workflow, wave by wave:
> Wave 1 = Tasks 1, 2, 3 (independent), Wave 2 = Tasks 4, 5, 6 (independent), Wave 3 = Task 7,
> Wave 4 = Task 9 (the files still off the oracle after Wave 3). Task 8 needs the screen and comes last. Steps use checkbox (`- [ ]`) syntax.

**Goal:** An 8-bit RGB PSD/PSB saved without "Maximize Compatibility" shows the picture Photoshop shows,
drawn from its layers, instead of ImageIO's blank or placeholder composite.

**Architecture:** A parser reads the layer and mask section into a layer tree (records, channel pixels,
masks, tagged blocks); a descriptor parser reads Photoshop's action descriptors (fills, adjustments,
vector data). Pure per-pixel blend functions, fill and vector mask rendering, and adjustment functions
are separate units; a compositor walks the tree bottom-up at the decode's scale. `ImageDecoder` routes
files whose version info says there is no real composite to it; everything else is unchanged.

**Tech Stack:** Swift 6, `RGBAImage`, CoreGraphics (vector mask paths, gradients), `Inflate.zlib`
(zip channels), Swift Testing.

**Spec:** `docs/spec.md` › Formats, the paragraph "8-bit RGB PSD and PSB without a real stored composite…".

## Clean-room sources

Format facts come only from Adobe's published *Photoshop File Formats Specification* (adobe.com
devnet). Blend formulas: W3C *Compositing and Blending Level 1* for the separable and non-separable
modes it defines; the Photoshop-only modes (linear burn/dodge, vivid/linear/pin light, hard mix,
darker/lighter colour, subtract, divide, dissolve) from their published definitions, checked against
Photoshop's own composites in the corpus (Task 7). Never read the code of psd-tools, ag-psd, psd.rb or any
other PSD library or viewer; their test files are used as data only, locally, never committed.

## Corpus facts (2026-10-30)

513 PSD/PSB files from the test folders of psd-tools, ag-psd and psd.rb (in the session's scratchpad;
re-download with a sparse `git clone` of each repo's test folder), plus 28 on this Mac:
454 have layers, 3,080 layers; 416 of the layered files are 8-bit RGB. Blend keys: `norm` 2750, every
other mode 9–33 times, `pass` 5. 565 layer masks, 38 clipped layers, 127 with opacity < 255. Files
using: `lsct` (groups) 121, `SoCo` 125, `vmsk`/`vsms` 120/44, `lfx2`/`lrFX` (effects) 62/80, `TySh`
48, `SoLd`/`PlLd` 40/38, `GdFl` 28, `iOpa` 25, `curv` 16, `brit` 15, `hue2` 11, `levl` 8, `thrs` 8,
`post` 8, `nvrt` 8, `PtFl` 8, `grdm` 9, `blnc` 6, `selc` 5, `mixr` 5, `blwh` 5, `vibA` 5, `phfl` 5,
`clrL` 5, `expA` 16. 62 files lack a real composite (resource 1057 byte 4 = 0); ImageIO shows 24 of
them as one flat colour. The ~350 layered 8-bit RGB files *with* a real composite are the oracle: our
composite of their layers must match Photoshop's stored one (Task 7).

## Global Constraints

- Swift 6 strict concurrency; FeatherviewCore stays free of AppKit/SwiftUI.
- Only 8-bit RGB files without a real composite take the compositor. A real composite always wins
  (`PSDComposite`, Milestone 24). 16/32-bit, grey, CMYK, Lab, indexed, multichannel: ImageIO, as today.
- Known limits, drawn without them (never an error): layer effects (`lfx2`, `lrFX`, `lmfx`), colour
  lookup (`clrL`), 3D and video layers, knockout. Each gets a `shortcut:` comment where it is skipped.
- Damaged data: one bad layer or block → the whole compositor throws `OwnDecodeError.corrupt` and the
  file falls back to ImageIO (as before this milestone). Every length is bounded by the file's size.
- Memory: the canvas at the decode size plus one group's backdrop per nesting level plus one layer
  at a time; a layer's channels are read and reduced to the decode scale one by one.
- TDD for FeatherviewCore; test files are built by `PSDFixture` (extended) in code, never committed.
- No user-facing text (nothing to translate). Comments describe the code as it is.

## Review Focus

1. A group with blend mode `pass` vs an isolated group (`norm` or any other): pass-through children
   blend straight onto the backdrop, an isolated group composites its children onto transparency and
   then blends once — Task 4 `passThroughDiffersFromIsolatedGroup`.
2. Clipping: a clipped layer (clipping byte 1) blends inside the alpha of the nearest unclipped layer
   below it, and a hidden base hides its clipped layers — Task 4 `clippedLayerUsesBaseAlpha`, `hiddenBaseHidesClipped`.
3. Masks: layer mask with default colour 255 outside its rectangle vs 0; a disabled mask (flags bit 1)
   ignored; mask and vector mask multiplied — Task 4 `maskOutsideItsRectUsesDefaultColour`, Task 5 `vectorMaskCutsTheLayer`.
4. Layer bounds outside the canvas (negative top/left, past the right/bottom) and empty layers (0 × 0,
   groups' dividers) — Task 1 `layerBoundsOutsideCanvas`, Task 4 `emptyLayersAreSkipped`.
5. A file whose layer section is damaged (channel length past the end, RLE row overrun, zip that
   inflates short): the file still opens through ImageIO — Task 1 `corruptChannelThrows`, Task 7 `damagedLayersFallBack`.

---

### Task 1: `PSDLayers`, the layer and mask section (Core)

**Files:**
- Create: `Sources/FeatherviewCore/Formats/PSDLayers.swift`
- Modify: `Tests/FeatherviewCoreTests/Formats/PSDFixture.swift` (layers)
- Test: `Tests/FeatherviewCoreTests/Formats/PSDLayersTests.swift`

**Interfaces:**
- Produces:
  - `public struct PSDLayers: Sendable { width, height: Int; nodes: [PSDNode] /* bottom to top */; hasRealComposite: Bool; globalBlocks: [String: Data] }`
    and `public init?(url: URL) throws` — nil for anything but 8-bit RGB (3 or 4+ channels); throws `OwnDecodeError.corrupt` on damage.
  - `public indirect enum PSDNode: Sendable { case layer(PSDLayer); case group(PSDGroup) }`
  - `public struct PSDGroup { name: String; blend: String /* 4-char key, "pass" = pass-through */; opacity: UInt8; visible: Bool; mask: PSDMask?; clipped: Bool; blendIf: PSDBlendIf?; children: [PSDNode] }`
  - `public struct PSDLayer { name; rect: (top, left, bottom, right Int); blend: String; opacity: UInt8; fill: UInt8 /* iOpa, 255 when absent */; clipped: Bool; visible: Bool; mask: PSDMask?; blendIf: PSDBlendIf?; blocks: [String: Data]; func channels(scale: Double) throws -> RGBAImage? }`
    — `channels` reads this layer's R, G, B and transparency (-1) channel data from the file on demand
    (compression 0 raw, 1 RLE, 2 zip, 3 zip with prediction: per-row byte deltas), area-averaged to
    `scale` (≤ 1) with the layer's origin scaled the same way; nil for an empty layer.
  - `public struct PSDMask { rect; defaultColour: UInt8; disabled: Bool; relative: Bool; func pixels(scale:) throws -> (rect, [UInt8]) }` (channel -2; the user mask from the mask record's second rectangle when present).
  - `public struct PSDBlendIf { gray, red, green, blue: (source: [UInt8] /* 4 */, backdrop: [UInt8]) }` from the blending ranges.
- Groups come from `lsct`/`lsdk` (type 1/2 open/closed folder, 3 divider; the divider is the group's
  bottom in file order). `hasRealComposite` = resource 1057 byte 4 ≠ 0 (true without resource 1057).
- PSB: 8-byte lengths for the section, layer info and the long tagged-block keys (`LMsk Lr16 Lr32 Layr Mt16 Mt32 Mtrn Alph FMsk lnk2 FEid FXid PxSD`); 4-byte RLE row counts.
- `PSDFixture.makeLayered(width:height:layers: [FixtureLayer], realComposite: Bool, version:)` with
  `FixtureLayer(rect, pixels RGBA, blend, opacity, clipped, hidden, mask: (rect, pixels, default)?, compression, group: (open/close)?, blocks: [String: Data])`.

- [ ] **Step 1: Write the failing tests**

```swift
@Test(arguments: [(1, 0), (1, 1), (2, 1), (1, 2), (2, 3)])  // (version, channel compression)
func readsLayerPixels(version: Int, compression: Int) throws
// two layers 5×4 at (1,2) and 3×3 at (0,0): channels(scale: 1) equal the fixture's RGBA

@Test func readsGroupsBottomToTop() throws
// layers A, [group G: B, C], D in Photoshop order → nodes == [A, G(B, C), D] with G.blend == "pass"

@Test func readsRecordFields() throws
// blend "mul ", opacity 128, iOpa 64, clipped, hidden, Blend If ranges → the same values

@Test func layerBoundsOutsideCanvas() throws
// a layer at top -3, left -2 on a 4×4 canvas reads with its own rect unchanged

@Test func maskDefaultAndDisabled() throws
// mask rect, default colour 255, disabled flag → PSDMask fields; pixels(scale: 1) equal the fixture's

@Test func realCompositeFlag() throws
// realComposite false → hasRealComposite false; no resource 1057 → true

@Test func scaledChannelsAverage() throws
// 4×4 layer, scale 0.5 → 2×2 means (as PSDCompositeTests.areaAveragesOnDownscale)

@Test func corruptChannelThrows() throws
// channel length past the end; RLE row past the width; zip that inflates short → throws
```

- [ ] **Step 2: Run them — FAIL** (`swift test --filter PSDLayersTests`, `PSDLayers` not defined).
- [ ] **Step 3: Implement** `PSDLayers.swift` as above (offsets of each layer's channel data kept, pixels read on demand with `pread`).
- [ ] **Step 4: Run them — PASS.**
- [ ] **Step 5: Commit** `feat: read Photoshop layer records, groups, masks and channel pixels`

---

### Task 2: `PSDDescriptor`, Photoshop's action descriptors (Core)

**Files:**
- Create: `Sources/FeatherviewCore/Formats/PSDDescriptor.swift`
- Test: `Tests/FeatherviewCoreTests/Formats/PSDDescriptorTests.swift`

**Interfaces:**
- Produces: `public indirect enum PSDValue: Sendable, Equatable { case double(Double), unit(String, Double), int(Int), bool(Bool), text(String), enumerated(type: String, value: String), list([PSDValue]), object(PSDDescriptor), raw(Data) }`
  and `public struct PSDDescriptor: Sendable, Equatable { classID: String; items: [(key: String, value: PSDValue)]; subscript(key: String) -> PSDValue? }`
  with `public init(_ bytes: ArraySlice<UInt8>) throws` (starting at the Unicode class name) and
  `static func versioned(_ data: Data) throws -> PSDDescriptor` (4-byte version 16 first).
- Keys: 4-byte length, 0 = 4-char ID. Types: `Objc`/`GlbO` (object), `VlLs` (list), `doub`, `UntF`
  (unit + double), `UnFl` (unit + count + doubles → list), `long`, `comp` (Int64), `bool`, `TEXT`
  (Unicode), `enum`, `type`/`GlbC` (class → text), `tdta`/`alis` (length + raw), `obj ` (reference:
  parsed and kept as `raw`). Any other type → throws. Depth limited to 32, counts bounded by the bytes left.

- [ ] **Step 1: Failing tests**

```swift
@Test func readsNestedObjectsAndLists() throws
// hand-built SoCo descriptor: Clr  → Objc RGBC { Rd  doub 255, Grn  doub 128, Bl  doub 0 } → items equal

@Test func readsUnitsTextEnumsAndRaw() throws
// UntF #Prc 50; TEXT "Gradient"; enum BlnM Mltp; tdta 3 bytes; UnFl #Pxl [1, 2]

@Test func rejectsUnknownTypeAndOverruns() throws
// type "zzzz" throws; a count past the end throws; 40 nested objects throw
```

- [ ] **Step 2: FAIL. Step 3: Implement. Step 4: PASS.**
- [ ] **Step 5: Commit** `feat: read Photoshop action descriptors`

---

### Task 3: `PSDBlend`, every Photoshop blend mode (Core)

**Files:**
- Create: `Sources/FeatherviewCore/Formats/PSDBlend.swift`
- Test: `Tests/FeatherviewCoreTests/Formats/PSDBlendTests.swift`

**Interfaces:**
- Produces: `public enum PSDBlend { static func mode(_ key: String) -> Mode? ; enum Mode: CaseIterable { normal, dissolve, darken, multiply, colorBurn, linearBurn, darkerColor, lighten, screen, colorDodge, linearDodge, lighterColor, overlay, softLight, hardLight, vividLight, linearLight, pinLight, hardMix, difference, exclusion, subtract, divide, hue, saturation, color, luminosity } ;
  static func blend(_ mode: Mode, backdrop: SIMD3<Float>, source: SIMD3<Float>) -> SIMD3<Float> ;
  static func composite(_ mode: Mode, onto canvas: inout RGBAImage, layer: RGBAImage, at: (x: Int, y: Int), alpha: [UInt8]? /* mask, layer-sized */, opacity: Float, fill: Float, x y for dissolve) }`
- Keys: `norm diss dark mul  idiv lbrn dkCl lite scrn div  lddg lgCl over sLit hLit vLit lLit pLit hMix diff smud fsub fdiv hue  sat  colr lum `.
- `composite`: W3C source-over with the mixing step `Cs' = (1 − αb)·Cs + αb·B(Cb, Cs)`, straight alpha
  in and out, rounding half up to 8 bits. Fill opacity scales the layer's own pixels before blending;
  opacity scales the result (for the "special eight" modes — colour burn, linear burn, colour dodge,
  linear dodge, vivid light, linear light, hard mix, difference — Photoshop applies fill inside the
  blend; take this from the corpus check in Task 7 and record what it shows). Dissolve: a pixel is
  taken fully or not with probability α, from a hash of (x, y) so a decode is repeatable.

- [ ] **Step 1: Failing tests** (values in 0…1)

```swift
@Test func separableModes() {
    let b = SIMD3<Float>(0.2, 0.5, 0.8), s = SIMD3<Float>(0.6, 0.5, 0.1)
    #expect(PSDBlend.blend(.multiply, backdrop: b, source: s) ≈ (0.12, 0.25, 0.08))
    #expect(PSDBlend.blend(.screen, backdrop: b, source: s) ≈ (0.68, 0.75, 0.82))
    #expect(PSDBlend.blend(.linearBurn, backdrop: b, source: s) ≈ (0, 0, 0))
    #expect(PSDBlend.blend(.subtract, backdrop: b, source: s) ≈ (0, 0, 0.7))
    #expect(PSDBlend.blend(.difference, backdrop: b, source: s) ≈ (0.4, 0, 0.7))
    // plus one case per remaining separable mode, from its definition, with an edge value (0 or 1) each
}

@Test func nonSeparableModes()
// hue/saturation/colour/luminosity of (0.2,0.5,0.8) over (0.6,0.5,0.1) per W3C SetLum/SetSat; darker/lighter colour pick by luminosity

@Test func keysRoundTrip()  // every key above maps to a distinct Mode; "pass" and "zzzz" map to nil

@Test func compositeRespectsAlphaOpacityAndMask()
// 50 % source over opaque backdrop, opacity 0.5, mask 128 → expected bytes; transparent backdrop takes the source unblended

@Test func dissolveIsRepeatable()  // same input twice → same output; ≈ α of pixels taken over 10,000 pixels
```

- [ ] **Step 2: FAIL. Step 3: Implement** (per-pixel loops on the overlapping rows only).
- [ ] **Step 4: PASS. Step 5: Commit** `feat: every Photoshop blend mode`

---

### Task 4: `PSDCompositor`, groups, clipping, masks (Core)

**Files:**
- Create: `Sources/FeatherviewCore/Formats/PSDCompositor.swift`
- Test: `Tests/FeatherviewCoreTests/Formats/PSDCompositorTests.swift`

**Interfaces:**
- Consumes: Task 1 `PSDLayers`/`PSDNode`, Task 3 `PSDBlend`.
- Produces: `public struct PSDCompositor { init(_ layers: PSDLayers, content: @Sendable (PSDLayer, Double) throws -> RGBAImage? = { try $0.channels(scale: $1) }, adjustment: @Sendable (PSDLayer) -> ((inout RGBAImage, [UInt8]?) -> Void)? = { _ in nil }); func render(scale: Double) throws -> RGBAImage }`
  — `content` and `adjustment` are the hooks Task 7 fills with Task 5 and Task 6; the defaults use only stored pixels.
- Rules: bottom-up over `nodes`; a hidden node (and the clipped layers on a hidden base) is skipped;
  pass-through group: children onto the current canvas, then the group's mask and opacity limit them
  (draw children onto a copy, blend the copy back through mask × opacity); isolated group: children onto
  transparency, then composited with the group's mode/opacity/mask; clipping: a run of clipped layers
  composites onto a transparent layer-sized copy of the base, limited to the base's alpha, then blends
  as part of the base; layer mask (relative or absolute, default colour outside its rect, disabled →
  ignored) multiplies alpha; Blend If: per pixel, source/backdrop grey or channel value outside the
  ranges (with the split feather between the inner and outer values) lowers alpha; adjustment layers
  apply to the canvas below them through their mask and opacity. White background: none (transparent
  where nothing is drawn; the viewer shows its own background, as for PNG).
  `// shortcut: knockout (knko) is ignored, honour it if a file shows it.`

- [ ] **Step 1: Failing tests** (fixtures from Task 1's `makeLayered`)

```swift
@Test func normalLayersStackLikeSourceOver() throws
@Test func passThroughDiffersFromIsolatedGroup() throws   // a multiply child: pass-through darkens the background, an isolated normal group doesn't
@Test func clippedLayerUsesBaseAlpha() throws
@Test func hiddenBaseHidesClipped() throws
@Test func maskOutsideItsRectUsesDefaultColour() throws   // default 0 hides, default 255 shows
@Test func groupOpacityAndMaskApplyOnce() throws
@Test func blendIfDropsDarkSourcePixels() throws          // source grey range 128…255: a black pixel vanishes, white stays
@Test func emptyLayersAreSkipped() throws
@Test func scaledRenderMatchesFullRenderReduced() throws  // render(scale: 0.5) within 2 of render(scale: 1) reduced by area averaging, for normal layers
@Test func adjustmentHookRunsOnTheCanvasBelow() throws    // an invert hook inverts only what is below it, through its mask
```

- [ ] **Step 2: FAIL. Step 3: Implement. Step 4: PASS.**
- [ ] **Step 5: Commit** `feat: composite Photoshop layers with groups, clipping, masks and Blend If`

---

### Task 5: `PSDFills`, fill layers and vector masks (Core)

**Files:**
- Create: `Sources/FeatherviewCore/Formats/PSDFills.swift`
- Test: `Tests/FeatherviewCoreTests/Formats/PSDFillsTests.swift`

**Interfaces:**
- Consumes: Task 1 `PSDLayer.blocks`, `PSDLayers.globalBlocks` (patterns: `Patt`/`Pat2`/`Pat3`), Task 2 `PSDDescriptor`.
- Produces: `public enum PSDFills { static func content(_ layer: PSDLayer, canvas: (width: Int, height: Int), patterns: [String: RGBAImage], scale: Double) throws -> RGBAImage?`
  — nil when the layer has no `SoCo`/`GdFl`/`PtFl`; else the fill over the whole canvas (or the vector
  mask's bounds), cut by the vector mask; `static func vectorMask(_ layer: PSDLayer, canvas:, scale:) throws -> (rect, [UInt8])?`
  — `vmsk`/`vsms` path records (each knot: 3 points, coordinates as 8.24 fixed fractions of the canvas
  height/width; closed/open subpaths; path fill rule record; flags: invert, disable) filled with CoreGraphics,
  antialiased, even-odd per the records; `static func patterns(_ layers: PSDLayers) throws -> [String: RGBAImage]`.
- Gradient: types linear, radial, angle, reflected, diamond; angle, scale, offset, reverse, dither (ignored:
  `shortcut: gradient dither is off, add noise if banding shows`); colour stops and transparency stops with
  midpoints, interpolated in RGB; `Grdn` "custom" gradients only (`ClNs` noise gradients: `shortcut`, solid first colour).
- A layer that also stores pixels (shape layers do) uses the fill + vector mask, not the pixels.

- [ ] **Step 1: Failing tests**

```swift
@Test func solidColourFillsTheCanvas() throws            // SoCo RGB (255, 128, 0) → every pixel
@Test func vectorMaskCutsTheLayer() throws               // a square path over the middle half: inside opaque, outside clear, edge antialiased
@Test func invertedAndDisabledVectorMasks() throws
@Test func linearGradientEndsAndMiddle() throws          // black→white at 90°: first row black, last white, middle ≈ 128
@Test func radialAndReflectedGradients() throws
@Test func transparencyStops() throws
@Test func patternTiles() throws                         // 2×2 pattern, PtFl with its ID → tiled over a 5×3 canvas
@Test func scaledVectorMask() throws                     // scale 0.5 halves the mask's size, same shape
```

- [ ] **Step 2: FAIL. Step 3: Implement. Step 4: PASS.**
- [ ] **Step 5: Commit** `feat: render Photoshop fill layers and vector masks`

---

### Task 6: `PSDAdjustments`, adjustment layers (Core)

**Files:**
- Create: `Sources/FeatherviewCore/Formats/PSDAdjustments.swift`
- Test: `Tests/FeatherviewCoreTests/Formats/PSDAdjustmentsTests.swift`

**Interfaces:**
- Consumes: Task 2 `PSDDescriptor` (for `blwh`, `vibA`, `CgEd`, `expA` where descriptor-based), the raw block bytes for the binary ones.
- Produces: `public enum PSDAdjustments { static func adjustment(key: String, data: Data) throws -> ((inout SIMD3<Float>) -> Void)? }`
  — nil for keys it doesn't know (`clrL` and anything else: drawn without, per the known limits);
  throws on damaged data. Keys and their block layouts from Adobe's spec: `levl`, `curv`, `brit`/`CgEd`,
  `hue2`, `blnc`, `blwh`, `mixr`, `expA`, `vibA`, `phfl`, `nvrt`, `thrs`, `post`, `selc`, `grdm`.
- Each works on 8-bit-equivalent values in 0…1 (Levels and Curves build a 256-entry table per channel
  plus the composite table, applied composite first as Photoshop does).

- [ ] **Step 1: Failing tests** — one per key, e.g.

```swift
@Test func invert()        // (0.2, 0.5, 1) → (0.8, 0.5, 0)
@Test func threshold()     // level 128: 127/255 → 0, 128/255 → 1, on luminosity
@Test func posterize()     // 4 levels: 0.3 → 1/3
@Test func levels()        // input 50…200, gamma 1, output 0…255: 50 → 0, 125 → 127.5 ± 0.5, 200 → 255
@Test func curves()        // points (0,0) (128,200) (255,255): 128 → 200, monotone, ends fixed
@Test func hueSaturation() // master hue +180: pure red → cyan; saturation −100: grey with the same luminosity
@Test func brightnessContrastLegacyAndModern()
@Test func exposure()      // +1 EV doubles linear light
@Test func unknownKeyIsNil() // "clrL", "zzzz" → nil
// and colour balance, black & white, channel mixer, vibrance, photo filter, selective colour, gradient map
```

- [ ] **Step 2: FAIL. Step 3: Implement. Step 4: PASS.**
- [ ] **Step 5: Commit** `feat: Photoshop adjustment layers`

---

### Task 7: Routing, the corpus oracle, budgets (Core + bench)

**Files:**
- Modify: `Sources/FeatherviewCore/Imaging/ImageDecoder.swift` (`decodeFile`, `thumbnail`)
- Modify: `Sources/FeatherviewCore/Formats/PSDCompositor.swift` (wire Task 5 and 6 into the hooks: `PSDCompositor.photoshop(_ layers:)`)
- Modify: `Sources/FeatherviewBench/` (`psdlayers <dir>` subcommand)
- Modify: `AGENTS.md` (budget row "Photoshop layers"; the bench command)
- Test: `Tests/FeatherviewCoreTests/Imaging/PSDLayerRoutingTests.swift`

**Interfaces:**
- Consumes: Tasks 1–6.
- Behaviour: in `decodeFile` / `thumbnail`, a `psd`/`psb` whose `PSDComposite(url:)` is nil, and whose
  `PSDLayers(url:)` is 8-bit RGB with `hasRealComposite == false` and at least one node, is rendered by
  `PSDCompositor.photoshop` at `scale = longest / max(width, height)` (fit: `fit(size, exact: true)`;
  a zoom step: its step size), then `inColorSpace` with the file's ICC profile (resource 1039) or sRGB.
  Any throw → ImageIO, as before. Page 0 only. `RegionZoom`/`readsRegions` stays false for these files.
- Bench: `featherview-bench psdlayers <dir>` — for every 8-bit RGB layered PSD/PSB **with** a real
  composite: render the layers at scale 1, compare with `PSDComposite.decode` of the stored composite
  (both straight RGBA over white): mean absolute difference per channel, share of pixels off by > 8, the
  tagged blocks it uses that are known limits; one line per file, then totals for files without known
  limits; `--time` adds the render time.

- [ ] **Step 1: Failing tests**

```swift
@Test func fileWithoutCompositeRendersItsLayers() throws   // makeLayered(realComposite: false): decode(url) equals PSDCompositor render (not the fixture's blank composite)
@Test func fileWithCompositeKeepsIt() throws               // realComposite true: decode uses PSDComposite (the stored pixels, which the fixture makes differ from the layers)
@Test func fitDecodeIsExactSize() throws                   // as PSDRoutingTests.fitDecodeIsExactSize
@Test func damagedLayersFallBack() throws                  // a channel length past the end: decode(url) still succeeds (ImageIO)
@Test func sixteenBitStaysWithImageIO() throws
```

- [ ] **Step 2: FAIL. Step 3: Implement. Step 4: PASS; `swift test` all PASS.**
- [ ] **Step 5: Corpus oracle.** Run `swift run -c release featherview-bench psdlayers <corpus>` on the
  downloaded corpus. Target, over the files without known limits: ≥ 95 % with mean difference ≤ 1 and
  ≤ 1 % of pixels off by > 8. Look at every file over the target and fix the cause (fill-inside-blend for
  the special eight modes, rounding, group rules); list what stays over and why in this task's report.
  Also run the 62 files without a real composite and look at ten of them as PNGs next to ImageIO's
  (scratchpad, never committed).
- [ ] **Step 6: Budgets.** `--time` on the corpus; AGENTS.md row: `| Photoshop layers | fit decode of a
  layered 8-bit RGB PSD without a composite < 500 ms for 12 MP and 30 layers. Measured: <fill in> |`.
  If a file over 12 MP and 30 layers misses it, profile and fix before recording.
- [ ] **Step 7: Commit** `feat: Photoshop files without a stored composite show their layers`

---

### Task 9: The seven files still off Photoshop's composite (Core)

Measured on main after Task 7 and its review fixes (`featherview-bench psdlayers` on the corpus, 30 Oct):
206 of 220 comparable files within target, 101 of 108 when copies under `flat/` are counted once
(93.5 %, target ≥ 95 %). Speed is within budget (fit decode of the 12 MP, 30-layer file ~246 ms). The
seven files over the target, none using a known limit:

| File (psd-tools `tests/psd_files/` unless noted) | Mean diff | Pixels off > 8 |
|---|---|---|
| `adjustments/brightnesscontrast_rgb.psd` | 37.45 | 93.5 % |
| `adjustments/huesaturation_rgb.psd` | 0.70 | 2.3 % |
| `colormodes/4x4_8bit_rgb.psd` | 21.33 | 75 % |
| `colorprofiles/north_america_newspaper.psd` | 20.75 | 87.5 % |
| `gradients/noise-gradient-rgb.psd` | 2.22 | 33.3 % |
| `masks3.psd` | 3.30 | 14.0 % |
| ag-psd `test/read/gradient-overlay-2/src.psd` | 15.00 | 100 % |

**Files:** whichever of `PSDLayers.swift`, `PSDAdjustments.swift`, `PSDFills.swift`, `PSDCompositor.swift`
holds each cause; tests in the matching `*Tests.swift`.

**Interfaces:** none new; the oracle (`featherview-bench psdlayers <corpus>`) is the measure.

- [ ] **Step 1: Find each cause.** For each file, list its layers, blend modes, masks and tagged blocks
  (descriptor keys included), render it with `PSDCompositor.photoshop` and compare with the stored composite
  region by region (scratchpad PNGs, never committed) until the differing layer or block is known. Decide
  the correct behaviour from Adobe's *Photoshop File Formats Specification* and the stored composite only
  (clean-room rules above: never another library's code). Likely areas, unconfirmed: Brightness/Contrast's
  legacy mode (`brit` with the "use legacy" flag) versus the newer curve; Hue/Saturation's colourize or
  per-range rounding; gradient fill type, interpolation, dither, reverse or noise gradients (`GdFl`);
  mask density / feather or a disabled mask in `masks3`. A cause that is a layer effect or another known
  limit goes on the known-limits list with a `shortcut:` comment instead of a fix.
- [ ] **Step 2: Failing tests**, one per cause, built with `PSDFixture` (never a corpus file), each
  asserting the pixel values the stored composite shows, e.g.
  `@Test func legacyBrightnessContrastShiftsLinearly()`, `@Test func noiseGradientFillUsesItsSeed()`.
- [ ] **Step 3: FAIL. Step 4: Fix. Step 5: PASS; `swift test -j 4` all PASS.**
- [ ] **Step 6: Oracle again.** `swift run -c release featherview-bench psdlayers <corpus>`: ≥ 95 % of the
  unique comparable files within target (≥ 103 of 108), no file that was within target falls out, and the
  fit decode of the 12 MP, 30-layer file stays < 500 ms (`featherview-bench decode`). Report the per-file
  numbers before and after, and what stays over and why.
- [ ] **Step 7: Commit** each cause as its own `fix:` commit.

---

### Task 8: Screen check (waits for the maintainer's go)

- [ ] Open a folder of the corpus files without a real composite: every one shows a picture (no blank),
  ←/→ through them within the not-prefetched budget for files ≤ 12 MP.
- [ ] Thumbnail grid of the same folder; Finder thumbnails and Quick Look (the extensions decode through `ImageDecoder` too).
- [ ] A file with known limits (layer effects) shows without the effects, no error.
- [ ] Mark milestone 25 done in `docs/roadmap.md` and `ROADMAP.md` with the oracle numbers, commit
  `docs: Photoshop layers measured`.
