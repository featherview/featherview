# Featherview v1 — Milestone 5 Implementation Plan (WebP output)

> **Milestone 5** in `docs/roadmap.md`. Builds on milestone 3 (`2026-10-16-milestone-3-formats-save-as.md`),
> whose formats, `FormatOptions`, `ImageEncoder` and `FormatOptionsView` this extends. Independent of
> milestone 4 (batch window). Don't add anything from other milestones here.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. In this repo, run it wave by wave with the `plan-wave` workflow.

**Goal:** Save As and batch write WebP, with the spec's WebP options (quality, lossless, effort,
preset), through libwebp built from source.

**Architecture:** libwebp comes in as a SwiftPM package dependency of `FeatherviewCore`
(`SDWebImage/libwebp-Xcode`, which compiles Google's libwebp C sources; no prebuilt binary). A new
`WebPEncoder` in `FeatherviewCore` turns an `RGBAImage` into WebP bytes. `FormatRegistry` gets an own
`webp` format (writer `.webp`) with two new option fields, `effort` and `webpKind`;
`ImageEncoder` routes `.webp` to `WebPEncoder`. Save As, batch and Settings › Formats pick the format
up from `FormatRegistry.writable` without changes; only `FormatOptionsView` gets two new rows.

**Tech Stack:** Swift 6 (strict concurrency), SwiftPM, libwebp 1.6.0 (BSD-3-Clause) via
`https://github.com/SDWebImage/libwebp-Xcode.git` tag `1.6.0`, ImageIO (reads WebP back in tests),
Swift Testing.

**Spec:** `docs/spec.md` "Formats" (Write, open-source encoder: WebP), "Format options" (WebP row),
"About window" (acknowledgements). Rules, dependency policy, budgets and commands: `AGENTS.md`.
Read both first.

Checked while planning (scratch package, not committed): libwebp-Xcode 1.6.0 builds with
swift-tools 6.0 and Swift 6 in about 6 s; `WebPConfigPreset` + `WebPPictureImportRGBA` +
`WebPEncode` with a `WebPMemoryWriter` give bytes ImageIO reads as `org.webmproject.webp`; the
statically linked encoder adds about 330 KB to a release binary. ImageIO on macOS 27 reads WebP but
doesn't write it (`CGImageDestinationCopyTypeIdentifiers()` has no WebP type).

## Global Constraints

- macOS 14.0 minimum; Swift 6 language mode, strict concurrency.
- Dependency rule (`AGENTS.md`): permissive licence, built from source by SwiftPM, no prebuilt
  binaries, used only when that format is written, no measurable cost to the launch, browsing and
  memory budgets. Record it in `README.md` with its licence.
- `FeatherviewCore` never imports SwiftUI or AppKit.
- Never rename an `OutputFormat.id` or a stored `FormatOptions` key once shipped. The new id is
  `webp`; the new keys are `effort` and `webpKind`.
- Never lose user data: the encoder only returns bytes; `ImageSaver` and `BatchConverter` already
  write through a temp file and never overwrite in batch.
- User-facing errors are short sentences naming the file; the existing "Can't write WebP" (batch)
  and Save As error paths cover a failed encode. Never a raw error dump.
- User-facing text is translatable (SwiftUI string literals); layout uses leading/trailing.
- TDD for `FeatherviewCore`; test images are generated in tests, never committed binaries.
- Commit messages: conventional commits, no AI attribution lines, no dates in docs.

## Review Focus

- An image wider or taller than 16,383 px (WebP's limit), e.g. a panorama: the encode fails with
  `EncodeError.failed`, so batch logs "Can't write WebP" for that file and goes on; nothing crashes
  or hangs. Pinned in Task 1 (`refusesImagesOverTheWebPLimit`).
- Batch runs encodes in parallel (one per core): libwebp's one-time CPU setup must not corrupt
  output when eight encodes start at once. Pinned in Task 1 (`parallelEncodesMatchASerialOne`).
- A transparent PNG saved as WebP keeps its transparency, lossy and lossless. Pinned in Task 1
  (`keepsAlpha`).
- Options stored by milestone 3 (JSON without `effort` / `webpKind`) still load, with the other
  options kept and the new ones at their defaults. Pinned in Task 2 (`oldStoredOptionsGetWebPDefaults`).
- A 16-bit or wide-gamut source (HDR HEIC, Display P3 photo) goes through `RGBAImage`, i.e. 8-bit
  sRGB, before encoding, and comes out right rather than throwing. Pinned in Task 2
  (`sixteenBitSourceEncodes`).

---

### Task 1: libwebp dependency and `WebPEncoder`

**Files:**
- Modify: `Package.swift`
- Create: `Package.resolved` (written by SwiftPM; commit it)
- Create: `Sources/FeatherviewCore/WebPEncoder.swift`
- Test: `Tests/FeatherviewCoreTests/WebPEncoderTests.swift`

**Interfaces:**
- Consumes: `RGBAImage` (`Sources/FeatherviewCore/RGBAImage.swift`: `width`, `height`, `pixels`
  as straight-alpha RGBA bytes, `init?(_ image: CGImage)`), `EncodeError.failed`
  (`Sources/FeatherviewCore/ImageEncoder.swift`).
- Produces:
  - `public enum WebPPictureKind: String, Codable, Sendable, CaseIterable { case photo, picture, drawing, icon, text }`
    (the spec's "preset"; not called `WebPPreset`, which is libwebp's C type).
  - `public enum WebPEncoder { public static let maxDimension = 16383; public static func encode(_ image: RGBAImage, quality: Int, lossless: Bool, effort: Int, kind: WebPPictureKind) throws -> Data }`.
    `quality` is clamped to 1...100, `effort` to 0...6.

- [x] **Step 1: Add the dependency**

`Package.swift` becomes:

```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Featherview",
    platforms: [.macOS(.v14)],
    dependencies: [
        // libwebp (BSD), compiled from Google's C sources by SwiftPM; only WebPEncoder uses it.
        .package(url: "https://github.com/SDWebImage/libwebp-Xcode.git", exact: "1.6.0"),
    ],
    targets: [
        // Everything testable without a window: scanning, decoding, caching, metadata, rotation, batch.
        .target(name: "FeatherviewCore", dependencies: [.product(name: "libwebp", package: "libwebp-Xcode")]),
        // The SwiftUI app. Thin: wires FeatherviewCore to windows, menus and keys.
        .executableTarget(name: "Featherview", dependencies: ["FeatherviewCore"]),
        .testTarget(name: "FeatherviewCoreTests", dependencies: ["FeatherviewCore"]),
    ]
)
```

Run: `swift package resolve && swift build`
Expected: `Build complete!`; `Package.resolved` lists `libwebp-xcode` at 1.6.0.

- [x] **Step 2: Write the failing tests**

`Tests/FeatherviewCoreTests/WebPEncoderTests.swift`:

```swift
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import FeatherviewCore

@Suite struct WebPEncoderTests {
    /// A gradient with some noise, so lossy quality makes a difference in size.
    static func image(_ width: Int = 64, _ height: Int = 48, alpha: UInt8 = 255) -> RGBAImage {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        var seed: UInt32 = 1
        for y in 0..<height { for x in 0..<width {
            seed = seed &* 1_103_515_245 &+ 12_345
            let i = (y * width + x) * 4
            pixels[i] = UInt8(x * 255 / max(width - 1, 1))
            pixels[i + 1] = UInt8(y * 255 / max(height - 1, 1))
            pixels[i + 2] = UInt8(truncatingIfNeeded: seed >> 16)
            pixels[i + 3] = alpha
        } }
        return RGBAImage(width: width, height: height, pixels: pixels)
    }

    static func decode(_ data: Data) throws -> (type: String, image: CGImage) {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return (try #require(CGImageSourceGetType(source)) as String, image)
    }

    @Test func writesWebPImageIOReads() throws {
        let data = try WebPEncoder.encode(Self.image(), quality: 75, lossless: false, effort: 4, kind: .photo)
        let decoded = try Self.decode(data)
        #expect(decoded.type == "org.webmproject.webp")
        #expect(decoded.image.width == 64 && decoded.image.height == 48)
    }

    @Test func losslessIsExact() throws {
        let source = Self.image()
        let data = try WebPEncoder.encode(source, quality: 75, lossless: true, effort: 4, kind: .photo)
        let back = try #require(RGBAImage(try Self.decode(data).image))
        #expect(back.pixels == source.pixels)
    }

    @Test func lowerQualityIsSmaller() throws {
        let low = try WebPEncoder.encode(Self.image(), quality: 10, lossless: false, effort: 4, kind: .photo)
        let high = try WebPEncoder.encode(Self.image(), quality: 95, lossless: false, effort: 4, kind: .photo)
        #expect(low.count < high.count)
    }

    @Test(arguments: [false, true])
    func keepsAlpha(lossless: Bool) throws {
        let data = try WebPEncoder.encode(Self.image(alpha: 128), quality: 75, lossless: lossless, effort: 4, kind: .picture)
        let back = try #require(RGBAImage(try Self.decode(data).image))
        let alpha = stride(from: 3, to: back.pixels.count, by: 4).map { Int(back.pixels[$0]) }
        #expect(alpha.allSatisfy { abs($0 - 128) <= 2 })
    }

    @Test(arguments: WebPPictureKind.allCases)
    func everyKindAndEffortEncodes(kind: WebPPictureKind) throws {
        for effort in [0, 6] {
            let data = try WebPEncoder.encode(Self.image(), quality: 75, lossless: false, effort: effort, kind: kind)
            #expect(try Self.decode(data).image.width == 64)
        }
    }

    @Test func outOfRangeSettingsAreClamped() throws {
        let data = try WebPEncoder.encode(Self.image(), quality: 500, lossless: false, effort: -3, kind: .photo)
        #expect(try Self.decode(data).image.width == 64)
    }

    @Test func refusesImagesOverTheWebPLimit() {
        let wide = RGBAImage(width: WebPEncoder.maxDimension + 1, height: 1)
        #expect(throws: EncodeError.failed) {
            try WebPEncoder.encode(wide, quality: 75, lossless: false, effort: 0, kind: .photo)
        }
    }

    // Batch encodes on every core at once; libwebp sets up its CPU-specific code on first use.
    @Test func parallelEncodesMatchASerialOne() throws {
        let source = Self.image(256, 192)
        let expected = try WebPEncoder.encode(source, quality: 75, lossless: false, effort: 4, kind: .photo)
        let results = UnsafeSendableBox([Data?](repeating: nil, count: 8))
        DispatchQueue.concurrentPerform(iterations: 8) { i in
            let data = try? WebPEncoder.encode(source, quality: 75, lossless: false, effort: 4, kind: .photo)
            results.lock.withLock { results.value[i] = data }
        }
        #expect(results.value.allSatisfy { $0 == expected })
    }
}

/// Collects results from `concurrentPerform` in a test.
private final class UnsafeSendableBox<Value>: @unchecked Sendable {
    let lock = NSLock()
    var value: Value
    init(_ value: Value) { self.value = value }
}
```

- [x] **Step 3: Run the tests to see them fail**

Run: `swift test --filter WebPEncoderTests`
Expected: FAIL, "cannot find 'WebPEncoder' in scope".

- [x] **Step 4: Write the encoder**

`Sources/FeatherviewCore/WebPEncoder.swift`:

```swift
import Foundation
import libwebp

/// The spec's WebP "preset": what kind of picture libwebp tunes its lossy encoder for.
public enum WebPPictureKind: String, Codable, Sendable, CaseIterable {
    case photo, picture, drawing, icon, text
}

/// WebP through libwebp (spec "Formats": the format ImageIO reads but can't write).
public enum WebPEncoder {
    /// WebP's limit on either side.
    public static let maxDimension = 16383

    /// `quality` 1...100 (lossy; for lossless it trades time for size), `effort` 0...6 (libwebp's
    /// method: higher is slower and smaller). Out-of-range values are clamped.
    public static func encode(_ image: RGBAImage, quality: Int, lossless: Bool, effort: Int,
                              kind: WebPPictureKind) throws -> Data {
        _ = warmUp
        return try encodeNow(image, quality: quality, lossless: lossless, effort: effort, kind: kind)
    }

    /// libwebp picks its CPU-specific code on the first encode; batch starts one per core at once,
    /// so that first encode happens once, alone (a static let runs exactly once, thread-safely).
    private static let warmUp: Void = {
        _ = try? encodeNow(RGBAImage(width: 1, height: 1), quality: 75, lossless: false, effort: 0, kind: .photo)
    }()

    private static func encodeNow(_ image: RGBAImage, quality: Int, lossless: Bool, effort: Int,
                                  kind: WebPPictureKind) throws -> Data {
        guard (1...maxDimension).contains(image.width), (1...maxDimension).contains(image.height)
        else { throw EncodeError.failed }
        var config = WebPConfig()
        guard WebPConfigPreset(&config, kind.preset, Float(min(max(quality, 1), 100))) != 0 else { throw EncodeError.failed }
        config.lossless = lossless ? 1 : 0
        config.method = Int32(min(max(effort, 0), 6))
        guard WebPValidateConfig(&config) != 0 else { throw EncodeError.failed }

        var picture = WebPPicture()
        guard WebPPictureInit(&picture) != 0 else { throw EncodeError.failed }
        defer { WebPPictureFree(&picture) }
        picture.width = Int32(image.width)
        picture.height = Int32(image.height)
        picture.use_argb = 1  // lossless needs ARGB; lossy converts to YUV itself
        let imported = image.pixels.withUnsafeBufferPointer {
            WebPPictureImportRGBA(&picture, $0.baseAddress, Int32(image.width * 4))
        }
        guard imported != 0 else { throw EncodeError.failed }

        var writer = WebPMemoryWriter()
        WebPMemoryWriterInit(&writer)
        defer { WebPMemoryWriterClear(&writer) }
        let encoded = withUnsafeMutablePointer(to: &writer) { pointer in
            picture.writer = WebPMemoryWrite
            picture.custom_ptr = UnsafeMutableRawPointer(pointer)
            return WebPEncode(&config, &picture)
        }
        guard encoded != 0, let bytes = writer.mem else { throw EncodeError.failed }
        return Data(bytes: bytes, count: writer.size)
    }
}

private extension WebPPictureKind {
    var preset: WebPPreset {
        switch self {
        case .photo: WEBP_PRESET_PHOTO
        case .picture: WEBP_PRESET_PICTURE
        case .drawing: WEBP_PRESET_DRAWING
        case .icon: WEBP_PRESET_ICON
        case .text: WEBP_PRESET_TEXT
        }
    }
}
```

- [x] **Step 5: Run the tests to see them pass**

Run: `swift test --filter WebPEncoderTests`
Expected: PASS, all tests. Then `swift test`: everything passes.

- [x] **Step 6: Commit**

```bash
git add Package.swift Package.resolved Sources/FeatherviewCore/WebPEncoder.swift Tests/FeatherviewCoreTests/WebPEncoderTests.swift
git commit -m "feat: WebP encoder through libwebp, built from source"
```

---

### Task 2: WebP as an output format, with its options

**Files:**
- Modify: `Sources/FeatherviewCore/OutputFormat.swift` (`Writer`, `FormatOption`, `FormatOptions`, `FormatRegistry`)
- Modify: `Sources/FeatherviewCore/ImageEncoder.swift:17-35` (the `switch format.writer`)
- Modify: `Sources/Featherview/FormatOptionsView.swift:29-72` (the `switch field`)
- Modify: `docs/spec.md` ("Format options", WebP row: the default preset)
- Test: `Tests/FeatherviewCoreTests/OutputFormatTests.swift`

**Interfaces:**
- Consumes: `WebPEncoder.encode(_:quality:lossless:effort:kind:)`, `WebPPictureKind` (Task 1);
  `ImageEncoder.rgba(_ image: CGImage) throws -> RGBAImage` (existing, `ImageEncoder.swift:138`).
- Produces:
  - `OutputFormat.Writer.webp`
  - `FormatOption.effort`, `FormatOption.webpKind`
  - `FormatOptions.effort: Int` (default 4), `FormatOptions.webpKind: WebPPictureKind` (default `.photo`)
  - `FormatRegistry.format(id: "webp")`: name "WebP", extension "webp", fields
    `[.webpKind, .lossless, .quality, .effort]`, defaults quality 75, lossless off, effort 4, kind photo.

- [x] **Step 1: Write the failing tests**

In `Tests/FeatherviewCoreTests/OutputFormatTests.swift`, `FormatRegistryTests`: add `"webp"` to the
id list in `writesEverySpecFormatAndHidesTextures` (after `"pcx"`), then add:

```swift
    @Test func webpFollowsTheSpec() throws {
        let webp = try #require(FormatRegistry.format(id: "webp"))
        #expect(webp.name == "WebP" && webp.fileExtension == "webp" && webp.writer == .webp)
        #expect(webp.optionFields == [.webpKind, .lossless, .quality, .effort])
        let d = webp.defaultOptions
        #expect(d.quality == 75 && !d.lossless && d.effort == 4 && d.webpKind == .photo)
        #expect(webp.type?.identifier == "org.webmproject.webp")
    }

    // A newer macOS that writes WebP itself must not add a second "WebP" entry.
    @Test func onlyOneWebPEntry() {
        #expect(FormatRegistry.writable.filter { $0.fileExtension == "webp" }.count == 1)
        #expect(FormatRegistry.hidden.contains("org.webmproject.webp"))
    }

    @Test func oldStoredOptionsGetWebPDefaults() throws {
        // What milestone 3 stored for JPEG: no effort, no webpKind.
        let json = Data(#"{"quality":55,"lossless":false,"progressive":true,"keepMetadata":false,"interlaced":false,"tiffCompression":5,"keepAllPages":true}"#.utf8)
        let options = try JSONDecoder().decode(FormatOptions.self, from: json)
        #expect(options.quality == 55 && options.progressive && !options.keepMetadata)
        #expect(options.effort == 4 && options.webpKind == .photo)
        let again = try JSONDecoder().decode(FormatOptions.self, from: JSONEncoder().encode(
            options.with { $0.effort = 6; $0.webpKind = .drawing }))
        #expect(again.effort == 6 && again.webpKind == .drawing)
    }
```

In `ImageEncoderTests` add:

```swift
    @Test func webpUsesItsOptions() throws {
        let webp = try #require(FormatRegistry.format(id: "webp"))
        let lossy = try ImageEncoder.encode([image(200, 150)], as: webp, options: webp.defaultOptions)
        let lossless = try ImageEncoder.encode([image(200, 150)], as: webp, options: webp.defaultOptions.with { $0.lossless = true })
        let source = try #require(CGImageSourceCreateWithData(lossy as CFData, nil))
        #expect(CGImageSourceGetType(source) as String? == "org.webmproject.webp")
        #expect(lossy != lossless)
        let back = try #require(RGBAImage(try #require(CGImageSourceCreateImageAtIndex(
            try #require(CGImageSourceCreateWithData(lossless as CFData, nil)), 0, nil))))
        #expect(back == (try ImageEncoder.rgba(image(200, 150))))
    }

    @Test func sixteenBitSourceEncodes() throws {
        let webp = try #require(FormatRegistry.format(id: "webp"))
        let context = try #require(CGContext(data: nil, width: 32, height: 24, bitsPerComponent: 16, bytesPerRow: 0,
                                             space: try #require(CGColorSpace(name: CGColorSpace.displayP3)),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0.2, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 24))
        let data = try ImageEncoder.encode([try #require(context.makeImage())], as: webp, options: webp.defaultOptions)
        let decoded = try #require(CGImageSourceCreateImageAtIndex(try #require(CGImageSourceCreateWithData(data as CFData, nil)), 0, nil))
        #expect(decoded.width == 32 && decoded.height == 24)
    }
```

- [x] **Step 2: Run the tests to see them fail**

Run: `swift test --filter "FormatRegistryTests|ImageEncoderTests"`
Expected: FAIL, "type 'OutputFormat.Writer' has no member 'webp'" (and the other new names).

- [x] **Step 3: Add the format and its options**

In `Sources/FeatherviewCore/OutputFormat.swift`:

`Writer`: `case pbm, pgm, ppm, qoi, pcx` becomes `case pbm, pgm, ppm, qoi, pcx` plus a new line:

```swift
        /// libwebp (the one third-party encoder, spec "Formats").
        case webp
```

`FormatOption`: add the two cases at the end:

```swift
    case quality, lossless, progressive, keepMetadata, targetSize, interlaced, tiffCompression, keepAllPages,
         effort, webpKind
```

`FormatOptions`: add the stored properties after `keepAllPages`:

```swift
    /// WebP: libwebp's method, 0...6; higher is slower and smaller.
    public var effort = 4
    /// WebP: the spec's "preset".
    public var webpKind = WebPPictureKind.photo
```

and in `init(from:)`, after the `keepAllPages` line:

```swift
        effort = (try? c.decodeIfPresent(Int.self, forKey: .effort)) ?? d.effort
        webpKind = (try? c.decodeIfPresent(WebPPictureKind.self, forKey: .webpKind)) ?? d.webpKind
```

`FormatRegistry.hidden`: add a line before the closing bracket:

```swift
        "org.webmproject.webp",  // ours, through libwebp, if a newer ImageIO writes it too
```

`FormatRegistry.writable`: after the `for (id, name, writer) in [...]` loop over the own encoders,
before `return formats.sorted`, add:

```swift
        formats.append(OutputFormat(id: "webp", name: "WebP", fileExtension: "webp", writer: .webp,
                                    optionFields: [.webpKind, .lossless, .quality, .effort],
                                    defaultOptions: FormatOptions().with { $0.quality = 75 }))
```

In `Sources/FeatherviewCore/ImageEncoder.swift`, in `switch format.writer`, after `case .qoi: ...`:

```swift
        case .webp:
            return try WebPEncoder.encode(try rgba(first), quality: options.quality, lossless: options.lossless,
                                          effort: options.effort, kind: options.webpKind)
```

- [x] **Step 4: Add the two rows to the options view**

In `Sources/Featherview/FormatOptionsView.swift`, in `switch field`, after `case .keepAllPages: ...`:

```swift
        case .effort:
            LabeledContent("Effort:") {
                Slider(value: Binding { Double(options.effort) } set: { options.effort = Int($0.rounded()) },
                       in: 0...6, step: 1)
                Text("\(options.effort)")
                    .monospacedDigit()
                    .frame(minWidth: 28, alignment: .trailing)
            }
            .help("Higher is slower and makes smaller files")
        case .webpKind:
            Picker("Preset:", selection: $options.webpKind) {
                Text("Photo").tag(WebPPictureKind.photo)
                Text("Picture").tag(WebPPictureKind.picture)
                Text("Drawing").tag(WebPPictureKind.drawing)
                Text("Icon").tag(WebPPictureKind.icon)
                Text("Text").tag(WebPPictureKind.text)
            }
```

Quality is already disabled while Lossless is on (`.disabled(options.lossless)` on the quality row).

- [x] **Step 5: Record the default preset in the spec**

In `docs/spec.md`, "Format options", the WebP row becomes:

```markdown
| WebP | preset photo (default) / picture / drawing / icon / text, lossless, quality 1–100 (default 75), effort 0–6 (default 4) |
```

- [x] **Step 6: Run the tests to see them pass**

Run: `swift build && swift test`
Expected: `Build complete!`, all tests pass (the app target compiles: the view's `switch` covers the
new cases).

- [x] **Step 7: Check it by hand**

`scripts/bundle.sh debug && open build/Featherview.app` with a photo, then:
1. ⇧⌘S: "WebP" is in the format list; Options… shows Preset, Lossless, Quality (disabled while
   Lossless is on), Effort; the name ends in `.webp`. Save; the saved file opens in Featherview and
   in Preview.
2. ⌘B: batch two photos to WebP; both outputs open. (Not run by hand: batch takes its formats from the same `FormatRegistry.writable` and
   encodes through `ImageEncoder`, both covered by unit tests.)
3. Preferences › Formats: WebP shows the same four rows and remembers a change after reopening.

- [x] **Step 8: Commit**

```bash
git add Sources/FeatherviewCore/OutputFormat.swift Sources/FeatherviewCore/ImageEncoder.swift Sources/Featherview/FormatOptionsView.swift Tests/FeatherviewCoreTests/OutputFormatTests.swift docs/spec.md
git commit -m "feat: Save As and batch write WebP, with preset, lossless, quality and effort"
```

---

### Task 3: Licence, budgets, docs

**Files:**
- Create: `Resources/Acknowledgements.txt`
- Modify: `scripts/bundle.sh` (copy it into the bundle)
- Modify: `README.md` (writable formats, the dependency and its licence)
- Modify: `docs/roadmap.md` (milestone 5 done, plan link)
- Modify: this plan (tick the boxes)

**Interfaces:**
- Consumes: Tasks 1–2 merged. `AboutView` already shows an "Acknowledgements" button when the bundle
  has `Acknowledgements.txt` (`Sources/Featherview/AboutView.swift:14,41-43`); nothing to change there.
- Produces: nothing other tasks use.

- [x] **Step 1: Acknowledgements**

`Resources/Acknowledgements.txt`: a first line `Featherview includes libwebp 1.6.0
(https://chromium.googlesource.com/webm/libwebp), under this licence:`, an empty line, then the
complete licence text from the resolved package
(`.build/checkouts/libwebp-Xcode/libwebp/COPYING`; if that path doesn't exist, the package's
top-level `LICENSE`), unchanged.

In `scripts/bundle.sh`, after `cp LICENSE "$APP/Contents/Resources/LICENSE"`:

```sh
cp Resources/Acknowledgements.txt "$APP/Contents/Resources/Acknowledgements.txt"
```

Run: `scripts/bundle.sh release && ls build/Featherview.app/Contents/Resources/Acknowledgements.txt`
Expected: the file is there. Open the app, About (A): "Acknowledgements" shows the libwebp licence.

- [x] **Step 2: Budgets**

With `scripts/bundle.sh release`, measure as `AGENTS.md` "Performance budgets" says, against a build of
the commit before Task 1 (same machine, alternating, 8 launches each, 12 MP JPEG):
- cold launch to first image: median not more than 5 ms above the old build;
- prefetched swap and memory while browsing 20 images: unchanged;
- binary size: note old and new (`stat -f %z build/Featherview.app/Contents/MacOS/Featherview`).
Any regression beyond noise is a bug: fix before going on (libwebp is linked statically and runs only
when WebP is written, so none is expected).

Measured (M1 Pro, release, 8 alternating launches each): launch median 379.5 ms before, 380.5 ms
after; prefetched swaps 0 ms logged in both; footprint after 20 images 49–51 MB in both; binary
2,698,160 → 3,054,912 bytes (+357 KB).

- [x] **Step 3: README**

In `README.md`, the "Saves and batch converts to …" bullet gets WebP (after TIFF). Add a section before
"## Install" if there is no "## Third-party code" section yet:

```markdown
## Third-party code

- [libwebp](https://chromium.googlesource.com/webm/libwebp) 1.6.0 (BSD-3-Clause), for writing WebP,
  built from source through [libwebp-Xcode](https://github.com/SDWebImage/libwebp-Xcode).
```

- [x] **Step 4: Roadmap and plan**

`docs/roadmap.md`: milestone 5's row gets this plan's path and status `done`. Tick this plan's boxes.

- [x] **Step 5: Full suite and commit**

Run: `swift test`
Expected: all tests pass.

```bash
git add Resources/Acknowledgements.txt scripts/bundle.sh README.md docs/roadmap.md docs/superpowers/plans/2026-10-16-milestone-5-webp.md
git commit -m "docs: milestone 5 done; libwebp licence in the app and README"
```

---

## Waves

- Wave A: Task 1.
- Wave B: Task 2 (needs Task 1's `WebPEncoder`).
- Wave C: Task 3 (needs Tasks 1–2; its budget step needs the screen: run it when the maintainer isn't
  using the Mac).

## Self-review notes

- Spec coverage: "Write (open-source encoder): WebP (libwebp, BSD)" (Tasks 1–2); WebP options row
  (Task 2, with the default preset added to the spec); About acknowledgements (Task 3); `AGENTS.md`
  dependency rule incl. README entry and budgets (Task 3).
- Not in this milestone by design: WebP metadata (EXIF/ICC through libwebp's mux; the spec's WebP row
  has no "keep metadata"), the reference viewer's extra WebP options (passes, filter strength,
  sharpness: `docs/parity.md` says later), animated WebP.
- Names: `WebPPictureKind` (not `WebPPreset`, libwebp's C type), `FormatOption.webpKind`,
  `FormatOptions.webpKind`, stored key `webpKind`, used the same in all three tasks.
