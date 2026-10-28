# Milestone 23: Info panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: run with the `plan-wave` workflow, wave by wave:
> Wave 1 = Tasks 1, 2, 3 and 5 (independent, Core), Wave 2 = Tasks 4, 6 and 7, Wave 3 = Task 8.
> Task 9 needs the screen and waits for the maintainer's go. Steps use checkbox (`- [ ]`) syntax.

**Goal:** The info panel of the approved design B2-1b-2: header with place, histogram, exposure card,
foldable groups (state kept until quit), offline place names, and a keyboard-driven All Metadata window.

**Architecture:** Core reads everything into value types (`ImageInfo`, `Histogram`, `MetadataCatalog`)
and formats every visible string, so the app only lays out. Place names come from one binary file
(`places.fvpl`) built per release by `featherview-bench places` from GeoNames and Natural Earth;
`PlaceIndex` (Core actor) loads it lazily on the first geotagged picture and answers in microseconds.
The app splits the panel out of `ViewerView.swift` into its own files and adds one utility window.

**Tech Stack:** Swift 6, ImageIO (EXIF/GPS/IPTC/TIFF/XMP via `CGImageSourceCopyMetadataAtIndex`),
Accelerate/vImage (histogram), Compression (LZFSE), SwiftUI + AppKit (`NSPanel` for All Metadata),
Swift Testing.

**Spec:** `docs/spec.md` "Info panel" (under Viewer), "About window", "Distribution" (place data per
release), "Menu commands" (Image › All Metadata…). Design: `docs/DESIGN.md` "Info panel" (updated in
Task 6) and <https://claude.ai/artifact/Lf6bXo8PaC2Exi6A6Unvmx>. Behaviour observed in the reference
viewer: `docs/parity.md` "Metadata". Roadmap: `docs/roadmap.md` row 23.

## Global Constraints

- Nothing in the panel or the All Metadata window uses the network; "Open in Maps" hands a
  `maps://?ll=<lat>,<lon>&q=<place>` URL to `NSWorkspace` only on click.
- Budgets unchanged (AGENTS.md): launch < 410 ms (no place data, no histogram before the panel is
  shown), prefetched next / previous ≈ 20 ms and not prefetched < 150 ms with the panel open.
  New targets, measured in Task 8: histogram ≤ 5 ms for a 2560 × 1600 decoded picture; place data
  load ≤ 50 ms (off the main thread, once); lookup ≤ 1 ms.
- Place data: GeoNames `cities1000.zip`, `admin1CodesASCII.txt` (download.geonames.org/export/dump,
  CC BY 4.0) and Natural Earth 10 m `ne_10m_geography_marine_polys` + `ne_10m_geography_regions_polys`
  GeoJSON (public domain). Marine features kept: `featurecla` ocean, sea, bay, gulf; regions:
  Desert, Range/mtn. Thresholds: place 25 km; sea "off" 200 km; region "near" 500 km.
- `places.fvpl` is never committed (`.gitignore` gets `build/places/`); downloads cached in
  `~/Library/Caches/net.mynetx.featherview-build/places`. The Quick Look extensions never link or
  bundle it.
- Group open state and histogram mode live in memory for the app run (no `UserDefaults`); at launch
  Camera and Location are open, mode Luminance.
- Copy is the spec's. Every new key in all 30 languages of `Resources/Localizable.xcstrings`
  (`scripts/strings.sh`, then translate). Numbers and coordinates stay left-to-right in RTL.
- Tokens only in `Theme.swift`; leading/trailing; TDD for FeatherviewCore; comments describe code as it is.

## Review Focus

1. Coordinates near the antimeridian (lon 179.9 / −179.9) and the poles: the nearest place must be
   found across the ±180° seam and lookups at lat ±90 must not crash — Task 3
   `nearestAcrossAntimeridian`, `poleDoesNotCrash`.
2. A picture whose GPS has a latitude but no longitude, a ref of "S"/"W", or zeroed coordinates
   (0, 0 written by apps without a fix): no Location group for missing halves; 0,0 with no altitude
   and no GPS date is treated as "no fix" — Task 1 `gpsMissingHalfIsDropped`, `nullIslandIsNoFix`.
3. Description fields present in more than one source (EXIF Artist vs IPTC By-line vs XMP dc:creator,
   ImageDescription vs dc:description): one row each, XMP first, then IPTC, then EXIF, never doubled —
   Task 1 `descriptionMergesSourcesOnce`.
4. Huge or odd metadata (10,000 keywords, a 1 MB maker note, non-UTF-8 IPTC): the panel and All
   Metadata stay responsive; binary values are hidden, long lists end in "…" in the panel — Task 5
   `binaryEntriesHidden`, Task 1 `keywordsCapped`.
5. Focus in the panel while browsing or closing it: → with focus on a group header must still go to
   the next image (and keep the focus on that header), I or Esc must return focus to the picture so
   single keys work again, never a stuck focus in a hidden panel — Task 6 Step 2; manual check in Task 9.
6. Switching images quickly with the panel open: stale reads must never overwrite the new image's
   info (late task finishing last) — Task 6 keys the read on url+revision and drops results whose
   key no longer matches; manual check in Task 9.

---

### Task 1: `ImageInfo` — everything the panel shows, read and formatted (Core)

**Files:**
- Create: `Sources/FeatherviewCore/Imaging/ImageInfo.swift`
- Modify: `Sources/FeatherviewCore/Imaging/MetadataReader.swift` (remove `fields(for:)`,
  `fields(from:fileSize:)`, `MetadataField`, `Label`; keep `dateTaken`, `exifDate`, `exposure`,
  `format(bytes:)`, `camera(make:model:)`)
- Test: `Tests/FeatherviewCoreTests/Imaging/ImageInfoTests.swift` (replaces `MetadataReaderTests.swift`;
  move its `camera`/`exposure`/`taken` tests over)

**Interfaces:**
- Produces:
  ```swift
  public struct ImageInfo: Equatable, Sendable {
      public struct Exposure: Equatable, Sendable { public var shutter, aperture, iso, focal: String?   // bare numbers: "1/250", "8", "100", "35"
          public var focal35: String?; public var bias: String?; public var flash: String?
          public var whiteBalance: String?; public var metering: String? }
      public struct Picture: Equatable, Sendable { public var dimensions: String?   // "3,000 × 2,000 · 6.0 MP"
          public var profile: String?; public var bitDepth: String?; public var hdr: String?
          public var software: String?; public var summary: String?               // "P3 · 8-bit · HDR"
          public var headroom: Double? }                                          // gain map headroom, nil for SDR
      public struct GPS: Equatable, Sendable { public var latitude: Double; public var longitude: Double
          public var altitude: Double? }
      public struct Description: Equatable, Sendable { public var title, caption, creator, copyright, comment: String?
          public var keywords: [String]; public var moreKeywords: Bool /* list cut, panel ends it in "…" */; public var rating: Int? }
      public var fileName: String; public var formatLine: String          // "JPEG · 3,000 × 2,000 · 476 KB"
      public var camera: String?; public var lens: String?; public var taken: String?
      public var exposure: Exposure; public var picture: Picture; public var gps: GPS?
      public var description: Description; public var folder: String; public var modified: String?
      public var created: String?
      public static func read(_ url: URL) -> ImageInfo
      public static func read(properties: [CFString: Any], metadata: CGImageMetadata?, url: URL,
                              fileSize: Int?) -> ImageInfo                  // pure, for tests
  }
  public enum InfoText {
      public static func latitude(_ v: Double) -> String    // "46.6356° N"
      public static func longitude(_ v: Double) -> String   // "160.0000° W"
      public static func altitude(_ metres: Double) -> String  // "1,447 m" (Measurement, as provided)
      public static func stars(_ rating: Int) -> String     // "★★★★☆"
  }
  ```

- [ ] **Step 1: Write the failing tests** in `ImageInfoTests` (images from `Fixtures.writeImage(properties:)`):
  `exposureTilesAreBareNumbers` (ExposureTime 1/250, FNumber 8, ISO [100], FocalLength 35 →
  "1/250","8","100","35"); `focal35OnlyWhenDifferent` (FocalLenIn35mmFilm 53 → "53 mm"; 35 → nil);
  `chips` (ExposureBiasValue −0.7 → "−0.7 EV"; Flash 16 → "No flash", 1 → "Flash"; WhiteBalance 0 →
  "Auto"; MeteringMode 5 → "Multi-segment", 2 → "Centre-weighted", 3 → "Spot");
  `formatLine` (3000×2000 JPEG of 487,424 bytes → "JPEG · 3,000 × 2,000 · 476 KB", orientation 6 swaps);
  `pictureSummary` (Display P3, 8 bit, gain map → "P3 · 8-bit · HDR", `headroom` > 1, hdr row
  starts with "Gain map, up to " and ends with "×"; uses `Fixtures.writeHDRGainMap`);
  `gpsSignsFromRefs` (46.6356 N, 8.5939 E, alt 1447 → GPS(46.6356, 8.5939, 1447); ref S/W negate);
  `gpsMissingHalfIsDropped` (latitude only → gps nil); `nullIslandIsNoFix` (0,0, no altitude → nil);
  `descriptionMergesSourcesOnce` (XMP dc:creator "A", IPTC By-line "B", EXIF Artist "C" → creator "A",
  one value); `keywordsCapped` (10,000 IPTC keywords → 50 kept); `missingValuesLeftOut` (bare PNG →
  camera, lens, taken, gps nil, exposure all nil); `coordinateText` (`latitude(-33.8688)` == "33.8688° S",
  `longitude(-160)` == "160.0000° W"); `stars` (4 → "★★★★☆").
- [ ] **Step 2: Run** `swift test --filter ImageInfoTests` — Expected: FAIL (no `ImageInfo`).
- [ ] **Step 3: Implement `ImageInfo.read`** — properties via `CGImageSourceCopyPropertiesAtIndex`,
  IPTC/XMP via `CGImageSourceCopyMetadataAtIndex` + `CGImageMetadataCopyTagWithPath` (dc:title,
  dc:description, dc:creator, dc:rights, dc:subject, xmp:Rating); own formats keep dimensions + size only
  (as `fields(for:)` did). Numbers with `formatted()` (locale), "×" and "·" verbatim. Labels and chip
  words via `String(localized:)` with comment "Info panel".
- [ ] **Step 4: Keep the app building:** Task 6 owns the view, so leave a shim
  `MetadataReader.fields(for:) -> [MetadataField]` that maps `ImageInfo` to the old rows (Task 6 deletes
  it). Run `swift test --filter ImageInfoTests` and `swift build`. Expected: PASS, build succeeds.
- [ ] **Step 5: Commit** `feat: ImageInfo reads and formats everything the info panel shows`

### Task 2: `Histogram` (Core)

**Files:**
- Create: `Sources/FeatherviewCore/Imaging/Histogram.swift`
- Test: `Tests/FeatherviewCoreTests/Imaging/HistogramTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public struct Histogram: Equatable, Sendable {
      public var luminance: [Float]; public var red: [Float]; public var green: [Float]; public var blue: [Float]  // 256 bins, normalised so the tallest bin of luminance is 1
      public var shadowsClipped: Double; public var highlightsClipped: Double   // fractions 0...1 at level 0 / top SDR level
      public var headroom: Double?          // nil for SDR; > 1 for HDR, bins span 0...headroom
      public var clipThreshold: Double { 0.001 }
      public static func compute(_ image: CGImage, headroom: Double?) -> Histogram
  }
  public enum HistogramText { public static func clipped(_ fraction: Double, highlights: Bool) -> String } // "Highlights: 2.4 % clipped"
  ```
- [ ] **Step 1: Write the failing tests:** `solidMidGreyFillsOneBin` (`Fixtures.solid(64,64,(128,128,128,255))`
  → luminance peak at bin 128, all else 0); `blackAndWhiteClip` (half 0, half 255 → shadowsClipped 0.5,
  highlightsClipped 0.5); `belowThresholdNotClipped` (1 white pixel in 2,000 → highlightsClipped < 0.001);
  `rgbChannelsSeparate` (pure red → red peak 255, green/blue peak 0); `hdrSpansHeadroom` (headroom 4,
  a pixel at linear 2.0 lands in bin 127); `clippedText` (0.024, true → "Highlights: 2.4 % clipped").
- [ ] **Step 2: Run** `swift test --filter HistogramTests` — FAIL.
- [ ] **Step 3: Implement** with vImage (`vImageHistogramCalculation_ARGB8888` on an RGBA8 copy for
  SDR; for HDR draw into an extended-linear float context and bin by hand), luminance Rec. 709 weights.
- [ ] **Step 4: Run** — PASS.
- [ ] **Step 5: Commit** `feat: Histogram with clipping and HDR headroom`

### Task 3: Place table, lookup and naming (Core)

**Files:**
- Create: `Sources/FeatherviewCore/Places/PlaceTable.swift` (records, regions, binary format, lookup),
  `Sources/FeatherviewCore/Places/PlaceName.swift` (the spec's four rules and both text forms),
  `Sources/FeatherviewCore/Places/PlaceIndex.swift` (lazy-loading actor)
- Test: `Tests/FeatherviewCoreTests/Places/PlaceTableTests.swift`, `PlaceNameTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public struct PlaceRecord: Equatable, Sendable { public var name: String; public var admin1: String?
      public var country: String; public var latitude: Double; public var longitude: Double }  // country: ISO 3166 alpha-2
  public struct RegionRecord: Equatable, Sendable { public enum Kind: UInt8, Sendable { case sea, region }
      public var name: String; public var kind: Kind; public var rings: [[(Double, Double)]] }  // lon, lat; outer ring first
  public struct PlaceTable: Sendable {
      public init(places: [PlaceRecord], regions: [RegionRecord])
      public init(data: Data) throws                 // "FVPL" v1, LZFSE payload
      public func encoded() -> Data
      public func nearest(latitude: Double, longitude: Double, within km: Double) -> (PlaceRecord, km: Double)?
      public func region(latitude: Double, longitude: Double) -> RegionRecord?   // sea before region
  }
  public struct PlaceName: Equatable, Sendable { public var short: String; public var full: String
      public static func describe(latitude: Double, longitude: Double, in table: PlaceTable,
                                  countryName: (String) -> String = { Locale.current.localizedString(forRegionCode: $0) ?? $0 }) -> PlaceName? }
  public actor PlaceIndex { public static let shared: PlaceIndex
      public func configure(url: URL?)              // app sets Bundle.main's places.fvpl at launch, nil if absent
      public func name(latitude: Double, longitude: Double) async -> PlaceName? }  // loads on first call
  ```
  Format: header "FVPL", UInt16 version 1, then an LZFSE-compressed payload: string table, places as
  Int32 lat/lon × 10,000 + string indices + 2-byte country, sorted by 1° cell with a cell start table
  (360 × 180 UInt32), regions as rings of Int32 × 10,000 with bounding boxes. Document it in a comment
  at the top of `PlaceTable.swift`.

- [ ] **Step 1: Write the failing tests** with a hand-built table (Andermatt 46.6356/8.5939 Uri CH;
  Banjul 13.4549/−16.5790 GM; Tozeur 33.9197/8.1335 TN; Suva −18.1416/178.4419 FJ; Taveuni −16.85/−179.97 FJ;
  sea "North Atlantic Ocean" box over 0…40 N, −40…−15 E; region "Sahara" box 18…32 N, −10…25 E;
  "North Pacific Ocean" box 10…50 N, 150 E…−130 E across the seam):
  `roundTripsThroughData` (encoded → init(data:) equal lookups); `townWithin25km` (46.64, 8.60 →
  short "Andermatt, Switzerland", full "near Andermatt, Uri, Switzerland", countryName stubbed to English);
  `nearestByDistanceNotPopulation`; `seaOffCountry` (13.35, −17.40 → "North Atlantic, off Gambia" /
  "North Atlantic Ocean, off Banjul, Gambia" — the short form drops "Ocean"); `regionNearCountry`
  (31.0, 9.0 → "Sahara, near Tunisia" both); `openOcean` (32, −160 → "North Pacific Ocean" both);
  `nothingNearby` (point outside all regions and > 25 km → nil); `nearestAcrossAntimeridian`
  (−16.9, 179.99 finds Taveuni); `poleDoesNotCrash` (90, 0 and −90, 0); `rejectsBadData` (wrong magic
  → throws); `indexLoadsLazily` (`PlaceIndex` with a temp file: no read before the first `name`).
- [ ] **Step 2: Run** `swift test --filter "PlaceTableTests|PlaceNameTests"` — FAIL.
- [ ] **Step 3: Implement** — haversine distance; search the point's cell and widen ring by ring
  (longitude wraps) until a ring's nearest edge is farther than the best hit or `km`; point-in-polygon
  by ray casting after a bounding-box check; rings crossing ±180 stored split by the generator.
- [ ] **Step 4: Run** — PASS.
- [ ] **Step 5: Commit** `feat: offline place names from a bundled place table`

### Task 4: Place data generator, bundling, credits

**Files:**
- Create: `Sources/FeatherviewCore/Places/PlaceSources.swift` (GeoNames TSV, admin1 and Natural Earth
  GeoJSON parsing; ring simplification), `scripts/places.sh`
- Modify: `Sources/FeatherviewBench/main.swift` (`case "places"`), `scripts/bundle.sh` (copy
  `build/places/places.fvpl` into the app's Resources if present, else print
  "warning: no place data; build/places/places.fvpl missing (run scripts/places.sh)"), `.gitignore`,
  `Resources/Acknowledgements.txt`, `Sources/Featherview/Windows/AboutView.swift` (the text sheet makes
  URLs clickable: `AttributedString` with `NSDataDetector` links), `Sources/Featherview/App` launch
  (`PlaceIndex.shared.configure(url: Bundle.main.url(forResource: "places", withExtension: "fvpl"))`),
  `.claude/agents/release.md` (run `scripts/places.sh` before the disk image; report "place data: fresh"
  or "place data: cached from <date>"), `README.md` "Third-party code"
- Test: `Tests/FeatherviewCoreTests/Places/PlaceSourcesTests.swift`

**Interfaces:**
- Consumes: `PlaceRecord`, `RegionRecord`, `PlaceTable.encoded()` (Task 3)
- Produces:
  ```swift
  public enum PlaceSources {
      public static func places(geonamesTSV: String, admin1TSV: String) -> [PlaceRecord]
      public static func regions(marineGeoJSON: Data, regionsGeoJSON: Data, toleranceKm: Double) throws -> [RegionRecord]
  }
  ```
  `featherview-bench places <out.fvpl>` downloads (or reuses cached) sources, builds and writes the
  file, prints counts, bytes and the build time. `scripts/places.sh` runs it into `build/places/` and
  falls back to the last file with a warning when offline.

- [ ] **Step 1: Write the failing tests:** `parsesGeoNamesLine` (one real `cities1000` line for
  Andermatt → name "Andermatt", admin1 "Uri" via `CH.URI`-style code join, country "CH"); `skipsMalformedLines`;
  `keepsOnlyListedFeatureClasses` (GeoJSON with ocean, sea, Desert, Plateau → Plateau dropped);
  `splitsRingsAtAntimeridian`; `simplifiesRings` (1,000-point circle → < 100 points at 1 km tolerance).
- [ ] **Step 2: Run** `swift test --filter PlaceSourcesTests` — FAIL.
- [ ] **Step 3: Implement** parsers (Douglas–Peucker for simplification) and the bench subcommand;
  Acknowledgements entries in the file's own format, exactly:
  "Featherview includes place names from GeoNames (https://www.geonames.org), simplified, under the
  Creative Commons Attribution 4.0 International licence (https://creativecommons.org/licenses/by/4.0/)."
  and "Featherview includes region outlines from Natural Earth (https://www.naturalearthdata.com),
  simplified, in the public domain."
- [ ] **Step 4: Run** tests (PASS), then `scripts/places.sh` and `scripts/bundle.sh debug`.
  Expected: `build/places/places.fvpl` ≤ 3 MB, bundle prints no warning, the app's Resources contain
  `places.fvpl`, the `.appex` bundles don't.
- [ ] **Step 5: Commit** `feat: place data built per release from GeoNames and Natural Earth`

### Task 5: `MetadataCatalog` — every tag for All Metadata (Core)

**Files:**
- Create: `Sources/FeatherviewCore/Imaging/MetadataCatalog.swift`
- Test: `Tests/FeatherviewCoreTests/Imaging/MetadataCatalogTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public struct MetadataEntry: Equatable, Sendable, Identifiable { public var id: String   // "EXIF.ExposureTime"
      public var label: String; public var tag: String; public var value: String }
  public struct MetadataSection: Equatable, Sendable, Identifiable { public var id: String // "EXIF", "GPS", "IPTC", "XMP", "TIFF", others as ImageIO names them
      public var entries: [MetadataEntry] }
  public struct MetadataCatalog: Equatable, Sendable { public var sections: [MetadataSection]; public var hiddenCount: Int
      public static func read(_ url: URL) -> MetadataCatalog
      public func filtered(_ query: String) -> MetadataCatalog          // case- and diacritic-insensitive over label, tag, value
      public static func copyText(_ entries: [MetadataEntry]) -> String } // "Exposure time (ExposureTime): 1/250 s\n…"
  ```
- [ ] **Step 1: Write the failing tests:** `groupsInOrder` (EXIF, GPS, IPTC, XMP, TIFF first, then
  others alphabetically); `readableLabels` (ExposureTime → "Exposure time", unknown "FooBar" → "Foo bar");
  `valuesFormatted` (ExposureTime → "1/250 s", GPS lat with ref → "46.6356° N"); `binaryEntriesHidden`
  (MakerNote Data, offsets, thumbnail → hidden, `hiddenCount` counts them); `filterMatchesTagLabelValue`
  ("iso" finds ISOSpeedRatings; "Ändermatt" matches "Andermatt"); `copyTextFormat`.
- [ ] **Step 2: Run** — FAIL. **Step 3: Implement** (label table for the ~60 common tags, fallback splits
  camel case; `String(localized:)` for labels). **Step 4: Run** — PASS.
- [ ] **Step 5: Commit** `feat: MetadataCatalog lists every tag with readable names`

### Task 6: The info panel (app)

**Files:**
- Create: `Sources/Featherview/Viewer/InfoPanel.swift` (panel, header, groups, rows, tiles, chips),
  `Sources/Featherview/Viewer/HistogramView.swift`, `Sources/Featherview/Viewer/InfoPanelState.swift`
- Modify: `Sources/Featherview/Viewer/ViewerView.swift` (remove the old `InfoPanel`, pass `model.image`), `Sources/Featherview/Design/Theme.swift` (tokens below),
  `docs/DESIGN.md` "Info panel" (B2-1b-2: rows 32 pt, label secondary · value primary, groups, histogram,
  tiles, chips, clip marks, place line), `Sources/FeatherviewCore/Imaging/MetadataReader.swift` (drop the
  Task 1 shim)

**Interfaces:**
- Consumes: `ImageInfo.read`, `InfoText` (Task 1); `Histogram.compute`, `HistogramText` (Task 2);
  `PlaceIndex.shared.name` (Task 3)
- Produces: `@MainActor @Observable final class InfoPanelState { static let shared; var open: Set<InfoGroup>; var mode: HistogramMode }`
  with `enum InfoGroup { case camera, image, location, description, file }`, `enum HistogramMode { case luminance, rgb }`;
  `InfoPanel(url: URL?, revision: Int, image: CGImage?)` (the histogram's headroom is `ImageInfo.picture.headroom`). Task 7 opens its window from
  the panel's "Show all metadata…" via `AllMetadataWindow.show()`.

New tokens (dark / light, from the canvas): `histogramLine` = accent; `histogramFill` = accent 0.14;
`histogramChannelRed/Green/Blue` = rgb(255,105,105,.85) / rgb(110,225,140,.85) / rgb(120,170,255,.9);
`clipMarkOff` = white 0.45 / black 0.45; `tileFill` = white 0.06 / black 0.05; `chipFill`, `chipLine`
= white 0.06 / 0.10 (light: black 0.04 / 0.10); `infoRowHeightCompact` = 32; `histogramHeight` = 60;
`focusRing` = accent, `focusRingWidth` = 2, `focusRingOutset` = 1;
`labelSecondary` stays, but the panel uses secondary for labels and primary for values.

- [ ] **Step 1:** Build the panel per spec and canvas board "B2-1b-2 · Dark (main)": header (name
  `.truncationMode(.middle)` + `.help(fullName)`, format line, pin + `PlaceName.short`), histogram block
  (segmented Luminance / RGB bound to `InfoPanelState.shared.mode`; clip marks as buttons showing
  `HistogramText.clipped` in a small bubble), groups in order Camera, Image, Location, Description, File
  (header buttons toggle `InfoPanelState.shared.open`, `accessibilityAddTraits(.isHeader)`, Space/Return),
  closed summaries per spec, tiles with `.minimumScaleFactor(0.8)`, chips in a wrapping layout, Location's
  first line `PlaceName.full` (`.lineLimit(2)`), "Open in Maps" and "Show in Finder" as the Small button +
  glyph. Reads: `ImageInfo` in a detached task keyed on url+revision; histogram computed from `image` in a
  detached task; place name awaited from `PlaceIndex`; each result applied only if its key still matches.
- [ ] **Step 2: Keyboard and accessibility** exactly as the spec's "Keyboard and accessibility" list:
  `@FocusState` chain in the panel (mode control → clip marks → group headers → open groups' buttons →
  "Show all metadata…"), entered from the picture with Tab and left with Esc / Tab past the end / a
  click on the picture (the viewer's key handler forwards Tab and ⇧Tab when `showInfo`, and keeps every
  other viewer key working while the panel has focus); `.focusable()` with a custom accent ring
  (`Theme.focusRing` 2 pt, 1 pt outset) shown whenever the control is focused; `ScrollViewReader` scrolls
  the focused control into view; VoiceOver labels, traits and values as the spec words them;
  `accessibilityDifferentiateWithoutColor` / Increase Contrast → `Theme.labelPrimary` for secondary
  text and 1.5 pt hairlines; Reduce Motion → group toggles without animation.
- [ ] **Step 3:** `swift build` and `scripts/bundle.sh debug` — Expected: build succeeds, no warnings.
- [ ] **Step 4:** Update `docs/DESIGN.md` "Info panel", the Elements table and "Accessibility" rows
  (focus ring, Increase Contrast) to the new look.
- [ ] **Step 5: Commit** `feat: info panel with histogram, exposure card, groups, place names, keyboard focus`

### Task 7: All Metadata window (app)

**Files:**
- Create: `Sources/Featherview/Windows/AllMetadataWindow.swift`
- Modify: `Sources/Featherview/Viewer/ViewerView.swift` (`ViewerCommands`: Image › "All Metadata…" ⌥⌘I
  after Show Info, enabled when `availability.canShowInfo`)

**Interfaces:**
- Consumes: `MetadataCatalog.read`, `.filtered`, `.copyText` (Task 5); the frontmost `ViewerModel`'s
  `list.current` and `fileRevision`
- Produces: `@MainActor enum AllMetadataWindow { static func show() }` — one `NSPanel` (utility style,
  not floating, restorable off), title `"\(name) — All Metadata"`, follows the current image of the
  frontmost viewer.

- [ ] **Step 1:** Build it per spec and the canvas board "Show all metadata… window": search field,
  Copy / Copy All, sections with counts and disclosure, rows with label + monospaced tag + trailing
  value, footer "55 entries · 9 internal entries hidden", selection in the accent. Keyboard exactly as
  the spec lists (⌘F, Tab, ↑/↓ with ⇧, ←/→, Home/End, Return, Esc twice, ⌘C, ⇧⌘C, ⌘W); a `List` with
  `selection: Set<MetadataEntry.ID>` and `.onKeyPress` for ←/→/Home/End/Esc; VoiceOver reads
  "label, tag, value".
- [ ] **Step 2:** `swift build` and `scripts/bundle.sh debug` — build succeeds.
- [ ] **Step 3: Commit** `feat: All Metadata window, fully keyboard-driven`

### Task 8: Strings, budgets, docs

**Files:**
- Modify: `Resources/Localizable.xcstrings`, `AGENTS.md` (budgets rows: histogram, place load/lookup),
  `Sources/FeatherviewBench/main.swift` (`histogram <dir>` timing of `Histogram.compute` on fit-size
  decodes; `places --time <file>` load and 10,000 random lookups), `docs/roadmap.md` (row 23 status),
  `docs/parity.md` ("Metadata" rows → v2 where the spec now covers them), `ROADMAP.md` (public list)

- [ ] **Step 1:** `scripts/strings.sh`; translate every new key into all 30 languages.
- [ ] **Step 2:** Run `swift run -c release featherview-bench histogram /tmp/fv` and
  `swift run -c release featherview-bench places --time build/places/places.fvpl`.
  Expected: histogram p95 ≤ 5 ms; load ≤ 50 ms; lookup p95 ≤ 1 ms. Write the measured numbers into AGENTS.md.
- [ ] **Step 3:** `swift test` — Expected: all pass. **Step 4: Commit** `docs: info panel budgets, strings and roadmap`

### Task 9: Screen check (waits for the maintainer's go)

- [ ] Release build; open a folder of real photos (JPEG with GPS, iPhone HEIC with HDR, RAW, PNG
  screenshot); check against the canvas boards: header place, histogram modes and clip bubble, groups
  open/close and stay as left across images and windows, summaries, Open in Maps opens Maps, Show in
  Finder, light mode, Arabic, Tab order and focus rings.
- [ ] Panel without the mouse: Tab in, through every control with a visible ring, Space/Return act,
  Esc back to the picture, ← / → still browse with focus in the panel; VoiceOver (⌘F5) reads headers,
  tiles, chips and the histogram as the spec words them; Increase Contrast and Reduce Motion.
- [ ] All Metadata: every key in the spec's list works without the mouse; it follows → / ← in the viewer.
- [ ] Hold → through 200 images with the panel open: `Navigate` p50/p95 within budget (log stream);
  first geotagged image after launch shows its place within 100 ms.
- [ ] Record results in `docs/roadmap.md` and close the milestone.
