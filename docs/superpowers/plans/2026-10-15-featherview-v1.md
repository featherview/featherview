# Featherview v1 — Milestone 1 Implementation Plan (core viewer and batch)

> **Milestone 1 of 5** in `docs/roadmap.md`. The spec has grown since this plan was written; this
> milestone builds the core everything else extends. Features that are in the spec but not here
> (folder chooser, F7/F8, extra keys, multiple windows, Settings, full batch, more formats) are
> later milestones. Don't add them here.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship Featherview v1: a fast, keyboard-driven macOS image viewer with lossless rotate, info panel, Trash, and batch convert/resize/rename.

**Architecture:** All logic lives in the `FeatherviewCore` library (pure Swift + ImageIO, fully unit-tested). The `Featherview` executable is a thin SwiftUI app that wires the core to one viewer window, one batch window, menus and keys. SwiftPM builds it; `scripts/bundle.sh` wraps the binary into `build/Featherview.app`.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI + AppKit, ImageIO, Swift Testing, SwiftPM. No third-party dependencies.

**Spec:** `docs/spec.md` (requirements) and `AGENTS.md` (rules, budgets, commands). Read both first.

## Global Constraints

- macOS 14.0 minimum (`platforms: [.macOS(.v14)]`, `LSMinimumSystemVersion` 14.0).
- Bundle ID `net.mynetx.featherview`; log subsystem `net.mynetx.featherview`.
- No third-party dependencies. No `.xcodeproj`.
- Clean room: never consult IrfanView (binaries, site, docs, screenshots). `docs/spec.md` is the only source of requirements.
- Never lose data: atomic temp-file swap for rotation, Trash instead of delete, batch output never overwrites.
- Decode off the main thread at screen size; never read file contents while scanning a folder.
- Full Xcode required for `swift test` and for building the app target (see `AGENTS.md`).

## Review Focus

1. **Corrupt, missing or non-image files in the folder** — browsing must continue with "Can't open <name>", never crash or stall. Pinned by `ImageDecoderTests.corruptFileThrows`, `ImageCacheTests.failuresAreNotCached`, Task 11 QA step.
2. **Huge images (50+ MP, 4000×2000 PNG in tests)** — must decode downsampled to screen size, memory bounded. Pinned by `ImageDecoderTests.downsamplesLargeImages`.
3. **Rotation in a read-only folder or on an unsupported format** — original byte-identical, clear message. Pinned by `OrientationRotatorTests.readOnlyFolderLeavesOriginalIntact` and `refusesFormatsWithoutReliableOrientation`.
4. **Batch output into the input folder / duplicate names / names differing only by case** — never overwrite. Pinned by `BatchPlannerTests.neverOverwritesAnInput`, `namesDifferingOnlyInCaseClash`, `clashesGetNumberedSuffixes`.
5. **Files opened via a different path spelling (`/var` vs `/private/var`, other case)** — viewer must start at the opened image, not the first. Pinned by `ImageListTests.matchesCurrentThroughSymlinksAndCase`.

## Verification status (as of 2026-10-15)

- Every `FeatherviewCore` source file in this plan **compiled under Swift 6 strict concurrency** and its behaviour **passed an assertion harness equivalent to the tests below** on macOS 27 (Command Line Tools only).
- The Swift Testing files below have **not been compiled yet** (needs Xcode). Expect at most small syntax fixes; do not change tested behaviour to make them pass — fix the test if the test is wrong, the code if the code is wrong, and say which.
- The app files in Task 10 have **not been compiled** (SwiftUI macros need Xcode). Expect small fixes.

## Execution order (for parallel runs, e.g. ultracode)

| Wave | Tasks (parallel within a wave) | Needs |
|---|---|---|
| 0 | Task 0 | Xcode installed |
| A | 2, 4, 6, 8 | Task 1 (done) |
| B | 3 (needs 2), 5 (needs 4), 7 (needs 4), 9 (needs 4, 8) | wave A |
| C | 10 | all core tasks |
| D | 11 | 10 |

Each task touches only its own files, so tasks in one wave never conflict. Commit per task.

---

### Task 0: Toolchain check

**Files:** none

- [ ] **Step 1: Select Xcode**

Run: `xcode-select -p`
Expected: `/Applications/Xcode.app/Contents/Developer`. If it prints `/Library/Developer/CommandLineTools`, run `sudo xcode-select -s /Applications/Xcode.app` (ask the maintainer to run it; it needs their password) and accept the license with `sudo xcodebuild -license accept`.

- [ ] **Step 2: Build and run the (empty) test target**

Run: `swift build && swift test`
Expected: build succeeds; tests report 0 tests (only `Fixtures.swift` exists). If `swift test` errors about the `Testing` module or macros, Xcode isn't selected — go back to Step 1.

---

### Task 1: Scaffold — DONE (2026-10-15)

**Files (already in the repo):** `Package.swift`, `Sources/FeatherviewCore/PathKey.swift`, `Sources/Featherview/FeatherviewApp.swift` (placeholder window, replaced in Task 10), `Tests/FeatherviewCoreTests/Fixtures.swift`, `Resources/Info.plist`, `scripts/bundle.sh`, `.gitignore`, `AGENTS.md`, `CLAUDE.md`, `README.md`, `docs/spec.md`.

- [x] `scripts/bundle.sh debug` builds `build/Featherview.app`, ad-hoc signed with identifier `net.mynetx.featherview`; it launches.

**Produces:**
- `func pathKey(_ url: URL) -> String` (internal, FeatherviewCore): resolved, lower-cased path for file identity.
- `enum Fixtures` (tests): `makeTempDir() throws -> URL`, `writeImage(to:width:height:type:orientation:) throws -> URL` (`@discardableResult`, solid red, `type: UTType = .jpeg`, `orientation: Int = 1`), `writeCorrupt(to:) throws -> URL`.

---

### Task 2: Image formats and folder scanning

**Files:**
- Create: `Sources/FeatherviewCore/ImageFormats.swift`
- Create: `Sources/FeatherviewCore/FolderScanner.swift`
- Test: `Tests/FeatherviewCoreTests/FolderScannerTests.swift`

**Interfaces:**
- Consumes: `Fixtures` (Task 1).
- Produces: `ImageFormats.isDecodable(_ url: URL) -> Bool`; `FolderScanner.images(around url: URL) throws -> [URL]` (file → its folder's images; folder → its images; Finder order; hidden files skipped).

- [ ] **Step 1: Write the failing tests**

`Tests/FeatherviewCoreTests/FolderScannerTests.swift`:

```swift
import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct ImageFormatsTests {
    @Test(arguments: ["a.jpg", "a.JPG", "a.jpeg", "a.png", "a.heic", "a.tiff", "a.gif", "a.webp"])
    func decodable(_ name: String) {
        #expect(ImageFormats.isDecodable(URL(fileURLWithPath: "/x/\(name)")))
    }

    @Test(arguments: ["a.txt", "a.pdf", "a", "a.mov"])
    func notDecodable(_ name: String) {
        #expect(!ImageFormats.isDecodable(URL(fileURLWithPath: "/x/\(name)")))
    }
}

@Suite struct FolderScannerTests {
    @Test func listsImagesInFinderOrderSkippingOtherAndHiddenFiles() throws {
        let dir = try Fixtures.makeTempDir()
        try Fixtures.writeImage(to: dir.appendingPathComponent("img10.jpg"), width: 4, height: 4)
        try Fixtures.writeImage(to: dir.appendingPathComponent("img2.jpg"), width: 4, height: 4)
        try Fixtures.writeImage(to: dir.appendingPathComponent("img1.png"), width: 4, height: 4, type: .png)
        try Data("x".utf8).write(to: dir.appendingPathComponent("notes.txt"))
        try Data("x".utf8).write(to: dir.appendingPathComponent(".hidden.jpg"))

        let fromFile = try FolderScanner.images(around: dir.appendingPathComponent("img2.jpg"))
        #expect(fromFile.map(\.lastPathComponent) == ["img1.png", "img2.jpg", "img10.jpg"])
        #expect(try FolderScanner.images(around: dir).count == 3)
    }

    @Test func missingFolderThrows() {
        #expect(throws: (any Error).self) {
            try FolderScanner.images(around: URL(fileURLWithPath: "/no/such/folder/a.jpg"))
        }
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --filter "ImageFormatsTests|FolderScannerTests"`
Expected: compile error, `cannot find 'ImageFormats' in scope`.

- [ ] **Step 3: Implement**

`Sources/FeatherviewCore/ImageFormats.swift`:

```swift
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageFormats {
    /// Every type ImageIO can decode on this Mac (JPEG, PNG, HEIC, WebP, camera RAW, ...).
    static let decodable: [UTType] =
        (CGImageSourceCopyTypeIdentifiers() as? [String] ?? []).compactMap { UTType($0) }

    /// Decided by file extension only, so scanning a 10k-file folder never opens a file.
    public static func isDecodable(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension),
              !type.conforms(to: .pdf) else { return false }
        return decodable.contains { type.conforms(to: $0) }
    }
}
```

`Sources/FeatherviewCore/FolderScanner.swift`:

```swift
import Foundation

public enum FolderScanner {
    /// Decodable images next to `url` (or inside it, if it is a folder), in Finder order.
    public static func images(around url: URL) throws -> [URL] {
        let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        let folder = isFolder ? url : url.deletingLastPathComponent()
        let items = try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        return items
            .filter(ImageFormats.isDecodable)
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}
```

- [ ] **Step 4: Run to verify they pass**

Run: `swift test --filter "ImageFormatsTests|FolderScannerTests"`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/FeatherviewCore/ImageFormats.swift Sources/FeatherviewCore/FolderScanner.swift Tests/FeatherviewCoreTests/FolderScannerTests.swift
git commit -m "feat: scan a folder for decodable images in Finder order"
```

---

### Task 3: Image list navigation

**Files:**
- Create: `Sources/FeatherviewCore/ImageList.swift`
- Test: `Tests/FeatherviewCoreTests/ImageListTests.swift`

**Interfaces:**
- Consumes: `pathKey` (Task 1), `Fixtures` (Task 1), `FolderScanner.images(around:)` (Task 2, one test only).
- Produces: `struct ImageList: Equatable, Sendable` with `init(urls: [URL], current: URL? = nil)`, `urls: [URL]` (get), `index: Int` (get), `current: URL?`, `isEmpty: Bool`, `position: String` ("3 / 120"), `@discardableResult mutating next() -> Bool` and `previous() -> Bool` (false and unchanged at the end / start: the app then shows the folder chooser, Milestone 2), `first()`, `last()`, `removeCurrent()`, `neighbors(radius: Int) -> [URL]` (never wraps).

- [ ] **Step 1: Write the failing tests**

`Tests/FeatherviewCoreTests/ImageListTests.swift`:

```swift
import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct ImageListTests {
    let urls = ["a", "b", "c", "d"].map { URL(fileURLWithPath: "/x/\($0).jpg") }

    @Test func startsAtCurrent() {
        let list = ImageList(urls: urls, current: urls[2])
        #expect(list.index == 2)
        #expect(list.position == "3 / 4")
    }

    @Test func unknownCurrentStartsAtFirst() {
        #expect(ImageList(urls: urls, current: URL(fileURLWithPath: "/x/zzz.jpg")).index == 0)
    }

    @Test func matchesCurrentThroughSymlinksAndCase() throws {
        let dir = try Fixtures.makeTempDir()  // under /var, which is a symlink to /private/var
        let file = try Fixtures.writeImage(to: dir.appendingPathComponent("Photo.jpg"), width: 4, height: 4)
        let scanned = try FolderScanner.images(around: file)
        let list = ImageList(urls: scanned, current: URL(fileURLWithPath: dir.path + "/PHOTO.jpg"))
        #expect(list.current?.lastPathComponent == "Photo.jpg")
    }

    @Test func navigationStopsAtTheEnds() {
        var list = ImageList(urls: urls, current: urls[2])
        #expect(list.next())
        #expect(list.index == 3)
        #expect(!list.next())          // end of folder: caller shows the folder chooser
        #expect(list.index == 3)
        list.first()
        #expect(!list.previous())
        #expect(list.index == 0)
        list.last()
        #expect(list.index == 3)
    }

    @Test func neighborsNearestFirstWithoutWrapping() {
        let list = ImageList(urls: urls, current: urls[1])
        #expect(list.neighbors(radius: 2) == [urls[2], urls[0], urls[3]])
        #expect(ImageList(urls: urls, current: urls[3]).neighbors(radius: 2) == [urls[2], urls[1]])
        #expect(list.neighbors(radius: 0).isEmpty)
        #expect(ImageList(urls: [urls[0]]).neighbors(radius: 2).isEmpty)
    }

    @Test func removeCurrentShowsFollowingImage() {
        var middle = ImageList(urls: urls, current: urls[1])
        middle.removeCurrent()
        #expect(middle.current == urls[2])

        var last = ImageList(urls: urls, current: urls[3])
        last.removeCurrent()
        #expect(last.current == urls[2])
        #expect(last.urls.count == 3)
    }

    @Test func emptyListIsSafe() {
        var list = ImageList(urls: [urls[0]])
        list.removeCurrent()
        #expect(list.isEmpty)
        #expect(list.current == nil)
        #expect(list.position == "0 / 0")
        #expect(!list.next())
        #expect(!list.previous())
        list.removeCurrent()
        #expect(list.current == nil)
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --filter ImageListTests`
Expected: compile error, `cannot find 'ImageList' in scope`.

- [ ] **Step 3: Implement**

`Sources/FeatherviewCore/ImageList.swift`:

```swift
import Foundation

/// The images of one folder and which one is showing. Navigation stops at both ends.
public struct ImageList: Equatable, Sendable {
    public private(set) var urls: [URL]
    public private(set) var index: Int

    /// Selects `current` if it is in `urls` (compared by `pathKey`), else the first image.
    public init(urls: [URL], current: URL? = nil) {
        self.urls = urls
        let target = current.map(pathKey)
        self.index = urls.firstIndex { pathKey($0) == target } ?? 0
    }

    public var current: URL? { urls.indices.contains(index) ? urls[index] : nil }
    public var isEmpty: Bool { urls.isEmpty }
    /// 1-based, for the window title: "3 / 120".
    public var position: String { isEmpty ? "0 / 0" : "\(index + 1) / \(urls.count)" }

    /// False (and unchanged) at the last image: the caller decides what "past the end" means.
    @discardableResult
    public mutating func next() -> Bool {
        guard index + 1 < urls.count else { return false }
        index += 1
        return true
    }

    @discardableResult
    public mutating func previous() -> Bool {
        guard index > 0, !isEmpty else { return false }
        index -= 1
        return true
    }

    public mutating func first() { index = 0 }
    public mutating func last() { index = max(urls.count - 1, 0) }

    /// Drops the current entry (after Trash); the following image becomes current.
    public mutating func removeCurrent() {
        guard !isEmpty else { return }
        urls.remove(at: index)
        if index >= urls.count { index = max(urls.count - 1, 0) }
    }

    /// Images up to `radius` steps either side of current, nearest first, for prefetching.
    public func neighbors(radius: Int) -> [URL] {
        guard urls.count > 1, radius > 0 else { return [] }
        var result: [URL] = []
        for step in 1...radius {
            for offset in [step, -step] where urls.indices.contains(index + offset) {
                result.append(urls[index + offset])
            }
        }
        return result
    }
}
```

- [ ] **Step 4: Run to verify they pass**

Run: `swift test --filter ImageListTests`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/FeatherviewCore/ImageList.swift Tests/FeatherviewCoreTests/ImageListTests.swift
git commit -m "feat: image list with bounded navigation and prefetch neighbours"
```

---

### Task 4: Decoding

**Files:**
- Create: `Sources/FeatherviewCore/ImageDecoder.swift`
- Test: `Tests/FeatherviewCoreTests/ImageDecoderTests.swift`

**Interfaces:**
- Consumes: `Fixtures` (Task 1).
- Produces: `enum DecodeError: Error, Equatable { case unreadable(URL) }`; `ImageDecoder.displaySize(of: URL) -> CGSize?` (orientation applied); `ImageDecoder.decode(_ url: URL, maxPixelSize: Int? = nil) throws -> CGImage` (upright, longest side ≤ maxPixelSize, never upscaled, fully decoded).

- [ ] **Step 1: Write the failing tests**

`Tests/FeatherviewCoreTests/ImageDecoderTests.swift`:

```swift
import CoreGraphics
import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct ImageDecoderTests {
    @Test func appliesExifOrientation() throws {
        let dir = try Fixtures.makeTempDir()
        let url = try Fixtures.writeImage(to: dir.appendingPathComponent("r.jpg"), width: 40, height: 20, orientation: 6)
        #expect(ImageDecoder.displaySize(of: url) == CGSize(width: 20, height: 40))
        let image = try ImageDecoder.decode(url)
        #expect(image.width == 20)
        #expect(image.height == 40)
    }

    @Test func downsamplesLargeImages() throws {
        let dir = try Fixtures.makeTempDir()
        let url = try Fixtures.writeImage(to: dir.appendingPathComponent("big.png"), width: 4000, height: 2000, type: .png)
        let image = try ImageDecoder.decode(url, maxPixelSize: 500)
        #expect(max(image.width, image.height) == 500)
    }

    @Test func neverUpscales() throws {
        let dir = try Fixtures.makeTempDir()
        let url = try Fixtures.writeImage(to: dir.appendingPathComponent("s.jpg"), width: 40, height: 20)
        #expect(try ImageDecoder.decode(url, maxPixelSize: 4000).width == 40)
    }

    @Test func corruptFileThrows() throws {
        let dir = try Fixtures.makeTempDir()
        let url = try Fixtures.writeCorrupt(to: dir.appendingPathComponent("bad.jpg"))
        #expect(throws: DecodeError.unreadable(url)) { try ImageDecoder.decode(url) }
        #expect(ImageDecoder.displaySize(of: dir.appendingPathComponent("missing.jpg")) == nil)
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --filter ImageDecoderTests`
Expected: compile error, `cannot find 'ImageDecoder' in scope`.

- [ ] **Step 3: Implement**

`Sources/FeatherviewCore/ImageDecoder.swift`:

```swift
import CoreGraphics
import Foundation
import ImageIO

public enum DecodeError: Error, Equatable {
    case unreadable(URL)
}

public enum ImageDecoder {
    /// Pixel size as displayed, with EXIF orientation applied. nil if the file isn't a readable image.
    public static func displaySize(of url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let orientation = props[kCGImagePropertyOrientation] as? Int ?? 1
        return orientation >= 5 ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
    }

    /// Decodes upright, downsampled so the longest side is at most `maxPixelSize` (nil = full size).
    /// Never upscales. Pixels are decoded here, not lazily at first draw, so callers can run this
    /// off the main thread and the UI never stalls on display.
    public static func decode(_ url: URL, maxPixelSize: Int? = nil) throws -> CGImage {
        guard let size = displaySize(of: url),
              let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { throw DecodeError.unreadable(url) }
        let full = Int(max(size.width, size.height))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: min(maxPixelSize ?? full, full),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { throw DecodeError.unreadable(url) }
        return image
    }
}
```

- [ ] **Step 4: Run to verify they pass**

Run: `swift test --filter ImageDecoderTests`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/FeatherviewCore/ImageDecoder.swift Tests/FeatherviewCoreTests/ImageDecoderTests.swift
git commit -m "feat: upright, downsampled image decoding via ImageIO"
```

---

### Task 5: Image cache

**Files:**
- Create: `Sources/FeatherviewCore/ImageCache.swift`
- Test: `Tests/FeatherviewCoreTests/ImageCacheTests.swift`

**Interfaces:**
- Consumes: `ImageDecoder.decode(_:maxPixelSize:)`, `DecodeError` (Task 4); `Fixtures`.
- Produces: `actor ImageCache` with `init(capacity: Int = 8)`, `image(for: URL, maxPixelSize: Int?) async throws -> CGImage`, `prefetch(_ urls: [URL], maxPixelSize: Int?)`, `remove(_ url: URL)`, `removeAll()`, `count: Int`.

- [ ] **Step 1: Write the failing tests**

`Tests/FeatherviewCoreTests/ImageCacheTests.swift`:

```swift
import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct ImageCacheTests {
    @Test func concurrentRequestsDecodeOnce() async throws {
        let dir = try Fixtures.makeTempDir()
        let url = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 8, height: 8)
        let cache = ImageCache(capacity: 2)
        async let first = cache.image(for: url, maxPixelSize: 100)
        async let second = cache.image(for: url, maxPixelSize: 100)
        let (a, b) = try await (first, second)
        #expect(a === b)
    }

    @Test func evictsLeastRecentlyUsed() async throws {
        let dir = try Fixtures.makeTempDir()
        let files = try (0..<3).map {
            try Fixtures.writeImage(to: dir.appendingPathComponent("\($0).jpg"), width: 8, height: 8)
        }
        let cache = ImageCache(capacity: 2)
        for file in files { _ = try await cache.image(for: file, maxPixelSize: 100) }
        #expect(await cache.count == 2)
    }

    @Test func failuresAreNotCached() async throws {
        let dir = try Fixtures.makeTempDir()
        let bad = try Fixtures.writeCorrupt(to: dir.appendingPathComponent("bad.jpg"))
        let cache = ImageCache()
        await #expect(throws: DecodeError.self) { try await cache.image(for: bad, maxPixelSize: 100) }
        #expect(await cache.count == 0)
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --filter ImageCacheTests`
Expected: compile error, `cannot find 'ImageCache' in scope`.

- [ ] **Step 3: Implement**

`Sources/FeatherviewCore/ImageCache.swift`:

```swift
import CoreGraphics
import Foundation

/// Decoded images, least recently used evicted first. Keyed by URL only: callers clear it when
/// the decode size they need changes.
public actor ImageCache {
    private let capacity: Int
    private var images: [URL: CGImage] = [:]
    private var order: [URL] = []  // least recently used first
    private var inFlight: [URL: Task<CGImage, Error>] = [:]

    public init(capacity: Int = 8) {
        self.capacity = capacity
    }

    /// The cached image, or decodes it — once, even when several callers ask at the same time.
    public func image(for url: URL, maxPixelSize: Int?) async throws -> CGImage {
        if let hit = images[url] {
            touch(url)
            return hit
        }
        if let running = inFlight[url] { return try await running.value }
        let task = Task.detached(priority: .userInitiated) {
            try ImageDecoder.decode(url, maxPixelSize: maxPixelSize)
        }
        inFlight[url] = task
        defer { inFlight[url] = nil }
        let image = try await task.value
        store(image, for: url)
        return image
    }

    /// Warms the cache in the background. Failures are ignored here; they surface when shown.
    public func prefetch(_ urls: [URL], maxPixelSize: Int?) {
        for url in urls where images[url] == nil && inFlight[url] == nil {
            Task { _ = try? await self.image(for: url, maxPixelSize: maxPixelSize) }
        }
    }

    public func remove(_ url: URL) {
        images[url] = nil
        order.removeAll { $0 == url }
    }

    public func removeAll() {
        images = [:]
        order = []
    }

    public var count: Int { images.count }

    private func touch(_ url: URL) {
        order.removeAll { $0 == url }
        order.append(url)
    }

    private func store(_ image: CGImage, for url: URL) {
        images[url] = image
        touch(url)
        while order.count > capacity { images[order.removeFirst()] = nil }
    }
}
```

- [ ] **Step 4: Run to verify they pass**

Run: `swift test --filter ImageCacheTests`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/FeatherviewCore/ImageCache.swift Tests/FeatherviewCoreTests/ImageCacheTests.swift
git commit -m "feat: LRU image cache with de-duplicated decodes and prefetch"
```

---

### Task 6: Metadata for the info panel

**Files:**
- Create: `Sources/FeatherviewCore/MetadataReader.swift`
- Test: `Tests/FeatherviewCoreTests/MetadataReaderTests.swift`

**Interfaces:**
- Consumes: `Fixtures`.
- Produces: `struct MetadataField: Equatable, Sendable { label: String; value: String }`; `MetadataReader.fields(for: URL) -> [MetadataField]`; `MetadataReader.fields(from: [CFString: Any], fileSize: Int?) -> [MetadataField]`. Labels used: Dimensions, File size, Camera, Lens, Taken, Exposure, Aperture, ISO, Focal length.

- [ ] **Step 1: Write the failing tests**

`Tests/FeatherviewCoreTests/MetadataReaderTests.swift`:

```swift
import Foundation
import ImageIO
import Testing
@testable import FeatherviewCore

@Suite struct MetadataReaderTests {
    @Test func mapsCameraFields() {
        let props: [CFString: Any] = [
            kCGImagePropertyPixelWidth: 3000,
            kCGImagePropertyPixelHeight: 2000,
            kCGImagePropertyOrientation: 6,
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFMake: "Canon ",
                kCGImagePropertyTIFFModel: "EOS R6",
            ] as [CFString: Any],
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifExposureTime: 0.004,
                kCGImagePropertyExifFNumber: 8.0,
                kCGImagePropertyExifISOSpeedRatings: [400],
                kCGImagePropertyExifFocalLength: 49.6,
            ] as [CFString: Any],
        ]
        let fields = MetadataReader.fields(from: props, fileSize: nil)
        let byLabel = Dictionary(uniqueKeysWithValues: fields.map { ($0.label, $0.value) })
        #expect(byLabel == [
            "Dimensions": "2000 × 3000",  // orientation 6 swaps width and height
            "Camera": "Canon EOS R6",
            "Exposure": "1/250 s",
            "Aperture": "f/8",
            "ISO": "400",
            "Focal length": "50 mm",
        ])
    }

    @Test func missingValuesAreOmitted() {
        #expect(MetadataReader.fields(from: [:], fileSize: nil).isEmpty)
    }

    @Test func readsFileSizeFromDisk() throws {
        let dir = try Fixtures.makeTempDir()
        let url = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 8, height: 8)
        #expect(MetadataReader.fields(for: url).contains { $0.label == "File size" })
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --filter MetadataReaderTests`
Expected: compile error, `cannot find 'MetadataReader' in scope`.

- [ ] **Step 3: Implement**

`Sources/FeatherviewCore/MetadataReader.swift`:

```swift
import Foundation
import ImageIO

public struct MetadataField: Equatable, Sendable {
    public let label: String
    public let value: String
}

public enum MetadataReader {
    public static func fields(for url: URL) -> [MetadataField] {
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return fileSize.map { [MetadataField(label: "File size", value: format(bytes: $0))] } ?? [] }
        return fields(from: props, fileSize: fileSize)
    }

    /// Pure mapping from ImageIO properties. Missing values are left out, never shown as blanks.
    public static func fields(from props: [CFString: Any], fileSize: Int?) -> [MetadataField] {
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        var out: [MetadataField] = []
        func add(_ label: String, _ value: String?) {
            if let value, !value.isEmpty { out.append(MetadataField(label: label, value: value)) }
        }

        if let width = props[kCGImagePropertyPixelWidth] as? Int,
           let height = props[kCGImagePropertyPixelHeight] as? Int {
            let orientation = props[kCGImagePropertyOrientation] as? Int ?? 1
            add("Dimensions", orientation >= 5 ? "\(height) × \(width)" : "\(width) × \(height)")
        }
        add("File size", fileSize.map(format(bytes:)))
        add("Camera", [tiff[kCGImagePropertyTIFFMake], tiff[kCGImagePropertyTIFFModel]]
            .compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespaces) }
            .joined(separator: " "))
        add("Lens", exif[kCGImagePropertyExifLensModel] as? String)
        add("Taken", exif[kCGImagePropertyExifDateTimeOriginal] as? String)
        if let seconds = exif[kCGImagePropertyExifExposureTime] as? Double, seconds > 0 {
            add("Exposure", seconds < 1 ? "1/\(Int((1 / seconds).rounded())) s" : "\(seconds) s")
        }
        add("Aperture", (exif[kCGImagePropertyExifFNumber] as? Double)
            .map { "f/\($0.formatted(.number.precision(.fractionLength(0...1))))" })
        add("ISO", (exif[kCGImagePropertyExifISOSpeedRatings] as? [Int])?.first.map(String.init))
        add("Focal length", (exif[kCGImagePropertyExifFocalLength] as? Double).map { "\(Int($0.rounded())) mm" })
        return out
    }

    static func format(bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
```

- [ ] **Step 4: Run to verify they pass**

Run: `swift test --filter MetadataReaderTests`
Expected: all pass. Note: "Aperture" uses the current locale's decimal separator (f/2,8 in German); the test uses f/8 so it passes in every locale.

- [ ] **Step 5: Commit**

```bash
git add Sources/FeatherviewCore/MetadataReader.swift Tests/FeatherviewCoreTests/MetadataReaderTests.swift
git commit -m "feat: read EXIF/TIFF fields for the info panel"
```

---

### Task 7: Lossless rotation

**Files:**
- Create: `Sources/FeatherviewCore/OrientationRotator.swift`
- Test: `Tests/FeatherviewCoreTests/OrientationRotatorTests.swift`

**Interfaces:**
- Consumes: `ImageDecoder.displaySize(of:)` (Task 4, tests only); `Fixtures`.
- Produces: `enum Rotation: Sendable { case clockwise, counterClockwise }`; `enum RotateError: Error, Equatable { case unsupportedFormat, unreadable, writeFailed }`; `OrientationRotator.next(_ orientation: Int, _ rotation: Rotation) -> Int`; `OrientationRotator.rotate(_ url: URL, _ rotation: Rotation) throws`.

- [ ] **Step 1: Write the failing tests**

`Tests/FeatherviewCoreTests/OrientationRotatorTests.swift`:

```swift
import CoreGraphics
import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct OrientationRotatorTests {
    @Test(arguments: 1...8)
    func fourTurnsAreIdentity(_ orientation: Int) {
        var value = orientation
        for _ in 0..<4 { value = OrientationRotator.next(value, .clockwise) }
        #expect(value == orientation)
        let turned = OrientationRotator.next(orientation, .clockwise)
        #expect(OrientationRotator.next(turned, .counterClockwise) == orientation)
    }

    @Test func rotatesJPEGWithoutReencoding() throws {
        let dir = try Fixtures.makeTempDir()
        let url = try Fixtures.writeImage(to: dir.appendingPathComponent("r.jpg"), width: 60, height: 30)
        let sizeBefore = try Data(contentsOf: url).count

        try OrientationRotator.rotate(url, .clockwise)

        #expect(ImageDecoder.displaySize(of: url) == CGSize(width: 30, height: 60))
        #expect(abs(try Data(contentsOf: url).count - sizeBefore) < 200)  // re-encoding would change it a lot
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasPrefix(".featherview-") }
        #expect(leftovers.isEmpty)
    }

    @Test func refusesFormatsWithoutReliableOrientation() throws {
        let dir = try Fixtures.makeTempDir()
        let url = try Fixtures.writeImage(to: dir.appendingPathComponent("p.png"), width: 4, height: 4, type: .png)
        #expect(throws: RotateError.unsupportedFormat) { try OrientationRotator.rotate(url, .clockwise) }
    }

    @Test func readOnlyFolderLeavesOriginalIntact() throws {
        let dir = try Fixtures.makeTempDir()
        let url = try Fixtures.writeImage(to: dir.appendingPathComponent("ro.jpg"), width: 10, height: 5)
        let original = try Data(contentsOf: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path) }

        #expect(throws: RotateError.writeFailed) { try OrientationRotator.rotate(url, .clockwise) }
        #expect(try Data(contentsOf: url) == original)
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --filter OrientationRotatorTests`
Expected: compile error, `cannot find 'OrientationRotator' in scope`.

- [ ] **Step 3: Implement**

`Sources/FeatherviewCore/OrientationRotator.swift`:

```swift
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum Rotation: Sendable {
    case clockwise, counterClockwise
}

public enum RotateError: Error, Equatable {
    case unsupportedFormat, unreadable, writeFailed
}

public enum OrientationRotator {
    /// Formats whose EXIF orientation tag is honoured everywhere, so rotating needs no re-encode.
    static let supported: [UTType] = [.jpeg, .heic, .tiff]

    /// EXIF orientation after one clockwise quarter turn (mirrored values included).
    static let clockwise: [Int: Int] = [1: 6, 6: 3, 3: 8, 8: 1, 2: 7, 7: 4, 4: 5, 5: 2]

    public static func next(_ orientation: Int, _ rotation: Rotation) -> Int {
        switch rotation {
        case .clockwise: clockwise[orientation] ?? 6
        case .counterClockwise: clockwise.first { $0.value == orientation }?.key ?? 8
        }
    }

    /// Lossless: only the orientation tag changes, pixel data is copied untouched.
    /// Writes a temp file next to the original and swaps it in, so a failure never damages the original.
    public static func rotate(_ url: URL, _ rotation: Rotation) throws {
        guard let type = UTType(filenameExtension: url.pathExtension),
              supported.contains(where: { type.conforms(to: $0) }) else { throw RotateError.unsupportedFormat }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let sourceType = CGImageSourceGetType(source),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { throw RotateError.unreadable }
        let current = props[kCGImagePropertyOrientation] as? Int ?? 1
        let temp = url.deletingLastPathComponent()
            .appendingPathComponent(".featherview-\(UUID().uuidString).\(url.pathExtension)")
        defer { try? FileManager.default.removeItem(at: temp) }  // no-op once swapped in
        guard let dest = CGImageDestinationCreateWithURL(temp as CFURL, sourceType, 1, nil) else {
            throw RotateError.writeFailed
        }
        let options: [CFString: Any] = [
            kCGImageDestinationOrientation: next(current, rotation),
            kCGImageDestinationMergeMetadata: true,
        ]
        guard CGImageDestinationCopyImageSource(dest, source, options as CFDictionary, nil) else {
            throw RotateError.writeFailed
        }
        do { _ = try FileManager.default.replaceItemAt(url, withItemAt: temp) }
        catch { throw RotateError.writeFailed }
    }
}
```

- [ ] **Step 4: Run to verify they pass**

Run: `swift test --filter OrientationRotatorTests`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/FeatherviewCore/OrientationRotator.swift Tests/FeatherviewCoreTests/OrientationRotatorTests.swift
git commit -m "feat: lossless rotation via EXIF orientation with atomic swap"
```

---

### Task 8: Rename patterns and batch output planning

**Files:**
- Create: `Sources/FeatherviewCore/RenamePattern.swift`
- Create: `Sources/FeatherviewCore/BatchJob.swift`
- Test: `Tests/FeatherviewCoreTests/BatchPlannerTests.swift`

**Interfaces:**
- Consumes: `pathKey` (Task 1).
- Produces: `struct RenamePattern: Equatable, Sendable` with `init(_ template: String)`, `baseName(original: String, index: Int) -> String`; `enum OutputFormat: String, CaseIterable, Sendable { jpeg, png, heic, tiff }` with `type: UTType`, `fileExtension: String`, `isLossy: Bool`; `struct BatchJob: Sendable` with `init(inputs:outputFolder:format:quality: = 0.85, maxDimension: Int? = nil, rename: RenamePattern? = nil)`; `BatchPlanner.outputURLs(for: BatchJob, fileExists: (URL) -> Bool = <FileManager>) -> [URL]`.

- [ ] **Step 1: Write the failing tests**

`Tests/FeatherviewCoreTests/BatchPlannerTests.swift`:

```swift
import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct RenamePatternTests {
    @Test func tokens() {
        #expect(RenamePattern("{name}_{n:3}").baseName(original: "IMG", index: 7) == "IMG_007")
        #expect(RenamePattern("x{n}").baseName(original: "a", index: 12) == "x12")
        #expect(RenamePattern("{n:2}").baseName(original: "a", index: 123) == "123")
    }

    @Test func cannotEscapeTheOutputFolder() {
        #expect(RenamePattern("a/b:c").baseName(original: "z", index: 1) == "a-b-c")
    }

    @Test func emptyTemplateKeepsOriginal() {
        #expect(RenamePattern("").baseName(original: "z", index: 1) == "z")
    }

    @Test func originalNameIsNeverTreatedAsATemplate() {
        #expect(RenamePattern("{name}").baseName(original: "my{n}", index: 5) == "my{n}")
    }
}

@Suite struct BatchPlannerTests {
    let out = URL(fileURLWithPath: "/out")

    @Test func clashesGetNumberedSuffixes() {
        let inputs = ["/a/x.png", "/b/x.png", "/c/y.png"].map { URL(fileURLWithPath: $0) }
        let job = BatchJob(inputs: inputs, outputFolder: out, format: .jpeg)
        let plan = BatchPlanner.outputURLs(for: job) { $0.lastPathComponent == "y.jpg" }
        #expect(plan.map(\.lastPathComponent) == ["x.jpg", "x 2.jpg", "y 2.jpg"])
    }

    @Test func neverOverwritesAnInput() {
        let input = URL(fileURLWithPath: "/a/p.jpg")
        let job = BatchJob(inputs: [input], outputFolder: URL(fileURLWithPath: "/a"), format: .jpeg)
        #expect(BatchPlanner.outputURLs(for: job) { _ in false }.first?.lastPathComponent == "p 2.jpg")
    }

    @Test func namesDifferingOnlyInCaseClash() {
        let inputs = ["/a/A.png", "/b/a.png"].map { URL(fileURLWithPath: $0) }
        let job = BatchJob(inputs: inputs, outputFolder: out, format: .png)
        #expect(BatchPlanner.outputURLs(for: job) { _ in false }.map(\.lastPathComponent) == ["A.png", "a 2.png"])
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --filter "RenamePatternTests|BatchPlannerTests"`
Expected: compile error, `cannot find 'RenamePattern' in scope`.

- [ ] **Step 3: Implement**

`Sources/FeatherviewCore/RenamePattern.swift`:

```swift
import Foundation

/// Output file names for batch conversion.
/// `{name}` = original base name, `{n}` = 1-based counter, `{n:3}` = counter zero-padded to 3 digits.
/// Any other text is kept as typed.
public struct RenamePattern: Equatable, Sendable {
    public let template: String

    public init(_ template: String) {
        self.template = template
    }

    /// Base name without extension. "/" and ":" are replaced so a name can't leave the output folder.
    public func baseName(original: String, index: Int) -> String {
        // Counter first: an original name that happens to contain "{n}" must stay literal.
        let numbered = template.replacing(/\{n(?::(\d+))?\}/) { match in
            let digits = String(index)
            let width = match.1.flatMap { Int($0) } ?? 0
            return String(repeating: "0", count: max(0, width - digits.count)) + digits
        }
        let name = numbered
            .replacingOccurrences(of: "{name}", with: original)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return name.isEmpty ? original : name
    }
}
```

`Sources/FeatherviewCore/BatchJob.swift`:

```swift
import Foundation
import UniformTypeIdentifiers

public enum OutputFormat: String, CaseIterable, Sendable {
    case jpeg, png, heic, tiff

    public var type: UTType {
        switch self {
        case .jpeg: .jpeg
        case .png: .png
        case .heic: .heic
        case .tiff: .tiff
        }
    }

    public var fileExtension: String {
        switch self {
        case .jpeg: "jpg"
        case .png: "png"
        case .heic: "heic"
        case .tiff: "tiff"
        }
    }

    public var isLossy: Bool { self == .jpeg || self == .heic }
}

public struct BatchJob: Sendable {
    public var inputs: [URL]
    public var outputFolder: URL
    public var format: OutputFormat
    /// 0...1, lossy formats only.
    public var quality: Double
    /// Longest side in pixels; nil keeps the size. Never upscales.
    public var maxDimension: Int?
    /// nil keeps the original base name.
    public var rename: RenamePattern?

    public init(inputs: [URL], outputFolder: URL, format: OutputFormat, quality: Double = 0.85,
                maxDimension: Int? = nil, rename: RenamePattern? = nil) {
        self.inputs = inputs
        self.outputFolder = outputFolder
        self.format = format
        self.quality = quality
        self.maxDimension = maxDimension
        self.rename = rename
    }
}

public enum BatchPlanner {
    /// One output URL per input, in input order. Never an existing file, never an input,
    /// never the same name twice: clashes get " 2", " 3", ... appended.
    public static func outputURLs(
        for job: BatchJob,
        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> [URL] {
        var taken = Set(job.inputs.map(pathKey))
        return job.inputs.enumerated().map { offset, input in
            let original = input.deletingPathExtension().lastPathComponent
            let base = job.rename?.baseName(original: original, index: offset + 1) ?? original
            func candidate(_ suffix: String) -> URL {
                job.outputFolder.appendingPathComponent(base + suffix)
                    .appendingPathExtension(job.format.fileExtension)
            }
            var url = candidate("")
            var counter = 2
            while taken.contains(pathKey(url)) || fileExists(url) {
                url = candidate(" \(counter)")
                counter += 1
            }
            taken.insert(pathKey(url))
            return url
        }
    }
}
```

- [ ] **Step 4: Run to verify they pass**

Run: `swift test --filter "RenamePatternTests|BatchPlannerTests"`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/FeatherviewCore/RenamePattern.swift Sources/FeatherviewCore/BatchJob.swift Tests/FeatherviewCoreTests/BatchPlannerTests.swift
git commit -m "feat: rename patterns and collision-free batch output names"
```

---

### Task 9: Batch conversion

**Files:**
- Create: `Sources/FeatherviewCore/BatchConverter.swift`
- Test: `Tests/FeatherviewCoreTests/BatchConverterTests.swift`

**Interfaces:**
- Consumes: `ImageDecoder` (Task 4); `BatchJob`, `BatchPlanner`, `OutputFormat` (Task 8); `Fixtures`.
- Produces: `struct BatchResult: Sendable { input: URL; output: URL; error: String? }`; `BatchConverter.run(_ job: BatchJob, progress: @escaping @Sendable (Int, Int) -> Void = { _, _ in }) async -> [BatchResult]` (results in input order).

- [ ] **Step 1: Write the failing tests**

`Tests/FeatherviewCoreTests/BatchConverterTests.swift`:

```swift
import CoreGraphics
import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct BatchConverterTests {
    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func increment() { lock.withLock { value += 1 } }
        var count: Int { lock.withLock { value } }
    }

    @Test func convertsResizesAndReportsFailuresWithoutStopping() async throws {
        let dir = try Fixtures.makeTempDir()
        let rotated = try Fixtures.writeImage(to: dir.appendingPathComponent("rot.jpg"), width: 40, height: 20, orientation: 6)
        let big = try Fixtures.writeImage(to: dir.appendingPathComponent("big.png"), width: 4000, height: 2000, type: .png)
        let bad = try Fixtures.writeCorrupt(to: dir.appendingPathComponent("bad.jpg"))
        let out = try Fixtures.makeTempDir()
        let job = BatchJob(inputs: [rotated, big, bad], outputFolder: out, format: .jpeg, maxDimension: 100)
        let progress = Counter()

        let results = await BatchConverter.run(job) { _, _ in progress.increment() }

        #expect(results.map(\.input) == job.inputs)
        #expect(results.map { $0.error == nil } == [true, true, false])
        #expect(progress.count == 3)
        #expect(ImageDecoder.displaySize(of: results[0].output) == CGSize(width: 20, height: 40))  // upright, not upscaled
        #expect(ImageDecoder.displaySize(of: results[1].output) == CGSize(width: 100, height: 50))
        #expect(!FileManager.default.fileExists(atPath: results[2].output.path))
    }

    @Test func encodesHEIC() async throws {
        let dir = try Fixtures.makeTempDir()
        let input = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 64, height: 64)
        let results = await BatchConverter.run(BatchJob(inputs: [input], outputFolder: dir, format: .heic))
        #expect(results.first?.error == nil)
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --filter BatchConverterTests`
Expected: compile error, `cannot find 'BatchConverter' in scope`.

- [ ] **Step 3: Implement**

`Sources/FeatherviewCore/BatchConverter.swift`:

```swift
import Foundation
import ImageIO

public struct BatchResult: Sendable {
    public let input: URL
    public let output: URL
    /// nil = converted.
    public let error: String?
}

public enum BatchConverter {
    /// Converts every input, several at a time. One failure never stops the batch.
    /// `progress(done, total)` is called off the main thread.
    public static func run(
        _ job: BatchJob,
        progress: @escaping @Sendable (Int, Int) -> Void = { _, _ in }
    ) async -> [BatchResult] {
        let outputs = BatchPlanner.outputURLs(for: job)
        let total = job.inputs.count
        let width = max(1, ProcessInfo.processInfo.activeProcessorCount - 1)
        var results = [BatchResult?](repeating: nil, count: total)
        await withTaskGroup(of: (Int, BatchResult).self) { group in
            var started = 0
            var done = 0
            while started < min(width, total) {
                let i = started
                group.addTask { (i, convert(job.inputs[i], to: outputs[i], job: job)) }
                started += 1
            }
            for await (i, result) in group {
                results[i] = result
                done += 1
                progress(done, total)
                if started < total {
                    let next = started
                    group.addTask { (next, convert(job.inputs[next], to: outputs[next], job: job)) }
                    started += 1
                }
            }
        }
        return results.compactMap { $0 }
    }

    static func convert(_ input: URL, to output: URL, job: BatchJob) -> BatchResult {
        do {
            let image = try ImageDecoder.decode(input, maxPixelSize: job.maxDimension)
            guard let dest = CGImageDestinationCreateWithURL(
                output as CFURL, job.format.type.identifier as CFString, 1, nil)
            else { return BatchResult(input: input, output: output, error: "Can't write \(job.format.rawValue.uppercased())") }
            CGImageDestinationAddImage(dest, image, properties(of: input, job: job) as CFDictionary)
            guard CGImageDestinationFinalize(dest) else {
                try? FileManager.default.removeItem(at: output)  // never leave a half-written file
                return BatchResult(input: input, output: output, error: "Writing failed")
            }
            return BatchResult(input: input, output: output, error: nil)
        } catch {
            return BatchResult(input: input, output: output, error: "Can't read this image")
        }
    }

    /// Keeps EXIF, GPS and IPTC; drops what no longer matches the new pixels.
    static func properties(of input: URL, job: BatchJob) -> [CFString: Any] {
        var props: [CFString: Any] = [:]
        if let source = CGImageSourceCreateWithURL(input as CFURL, nil),
           let original = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            if var exif = original[kCGImagePropertyExifDictionary] as? [CFString: Any] {
                exif[kCGImagePropertyExifPixelXDimension] = nil
                exif[kCGImagePropertyExifPixelYDimension] = nil
                props[kCGImagePropertyExifDictionary] = exif
            }
            props[kCGImagePropertyGPSDictionary] = original[kCGImagePropertyGPSDictionary]
            props[kCGImagePropertyIPTCDictionary] = original[kCGImagePropertyIPTCDictionary]
        }
        props[kCGImagePropertyOrientation] = 1  // decode already rotated the pixels upright
        if job.format.isLossy { props[kCGImageDestinationLossyCompressionQuality] = job.quality }
        return props
    }
}
```

- [ ] **Step 4: Run all tests**

Run: `swift test`
Expected: every suite passes (Tasks 2–9).

- [ ] **Step 5: Commit**

```bash
git add Sources/FeatherviewCore/BatchConverter.swift Tests/FeatherviewCoreTests/BatchConverterTests.swift
git commit -m "feat: parallel batch convert/resize keeping metadata"
```

---

### Task 10: The app

**Files:**
- Modify (replace entirely): `Sources/Featherview/FeatherviewApp.swift`
- Create: `Sources/Featherview/ViewerModel.swift`
- Create: `Sources/Featherview/ViewerView.swift` (viewer, info panel, menu commands)
- Create: `Sources/Featherview/BatchView.swift` (batch model and window)

**Interfaces:**
- Consumes: everything public in FeatherviewCore (Tasks 2–9).
- Produces: the runnable app. No unit tests: the app layer is thin and verified manually in Task 11.

Not yet compiled (needs Xcode). Fix compile errors without changing behaviour described in `docs/spec.md`.

- [ ] **Step 1: Write `FeatherviewApp.swift`**

`Sources/Featherview/FeatherviewApp.swift`:

```swift
import FeatherviewCore
import SwiftUI

@main
struct FeatherviewApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var viewer = ViewerModel()
    @State private var batch = BatchModel()

    var body: some Scene {
        Window("Featherview", id: "viewer") {
            ViewerView(model: viewer)
                .onAppear { appDelegate.onOpen = { viewer.open($0) } }
        }
        .commands { ViewerCommands(model: viewer) }

        Window("Batch Convert", id: "batch") {
            BatchView(model: batch, viewer: viewer)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Finder can hand us a file before the window exists; hold it until the window is ready.
    var onOpen: ((URL) -> Void)? {
        didSet {
            if let onOpen, let pending {
                self.pending = nil
                onOpen(pending)
            }
        }
    }

    private var pending: URL?

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        if let onOpen { onOpen(url) } else { pending = url }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
```

- [ ] **Step 2: Write `ViewerModel.swift`**

`Sources/Featherview/ViewerModel.swift`:

```swift
import AppKit
import FeatherviewCore
import Observation
import os

@MainActor @Observable
final class ViewerModel {
    enum Zoom: Equatable {
        case fit
        /// 1 = one image pixel per screen pixel.
        case factor(Double)
    }

    private(set) var list = ImageList(urls: [])
    private(set) var image: CGImage?
    var errorMessage: String?
    var showInfo = false
    private(set) var zoom = Zoom.fit

    /// Fit mode decodes at screen size: enough for any window, far less memory than full size.
    private let screenPixels = Int(NSScreen.screens
        .map { max($0.frame.width, $0.frame.height) * $0.backingScaleFactor }
        .max() ?? 2560)
    private let cache = ImageCache(capacity: 8)
    private var loadTask: Task<Void, Never>?
    /// Read timings with: log stream --level debug --predicate 'subsystem == "net.mynetx.featherview"'
    private static let log = Logger(subsystem: "net.mynetx.featherview", category: "viewer")

    var title: String {
        list.current.map { "\($0.lastPathComponent) — \(list.position)" } ?? "Featherview"
    }

    func open(_ url: URL) {
        do {
            list = ImageList(urls: try FolderScanner.images(around: url), current: url)
            Task { await cache.removeAll() }
            show()
        } catch {
            errorMessage = "Can't open \(url.lastPathComponent)"
        }
    }

    // Past either end nothing happens yet; Milestone 2 shows the folder chooser here.
    func next() { if list.next() { show() } }
    func previous() { if list.previous() { show() } }
    func first() { list.first(); show() }
    func last() { list.last(); show() }

    func setZoom(_ zoom: Zoom) {
        let needsReload = (zoom == .fit) != (self.zoom == .fit)
        self.zoom = zoom
        if needsReload { show() }
    }

    func zoomIn() { setZoom(.factor(min(currentFactor * 1.1, 16))) }
    func zoomOut() { setZoom(.factor(max(currentFactor / 1.1, 0.05))) }

    private var currentFactor: Double {
        if case .factor(let f) = zoom { return f }
        return 1
    }

    /// Shows `list.current`, then prefetches its neighbours so arrow keys feel instant.
    func show() {
        loadTask?.cancel()
        guard let url = list.current else {
            image = nil
            return
        }
        let size: Int? = zoom == .fit ? screenPixels : nil
        let neighbors = list.neighbors(radius: 2)
        let started = ContinuousClock.now
        loadTask = Task {
            do {
                let decoded: CGImage
                if let size {
                    decoded = try await cache.image(for: url, maxPixelSize: size)
                } else {
                    // shortcut: full-size zoom bypasses the cache; cache full images too if zooming through a folder feels slow
                    decoded = try await Task.detached(priority: .userInitiated) { try ImageDecoder.decode(url) }.value
                }
                guard !Task.isCancelled else { return }
                image = decoded
                errorMessage = nil
                let elapsed = started.duration(to: .now).components
                let ms = elapsed.seconds * 1000 + elapsed.attoseconds / 1_000_000_000_000_000
                Self.log.debug("show \(url.lastPathComponent, privacy: .public): \(ms) ms")
            } catch {
                guard !Task.isCancelled else { return }
                image = nil
                errorMessage = "Can't open \(url.lastPathComponent)"
            }
            if let size { await cache.prefetch(neighbors, maxPixelSize: size) }
        }
    }

    func moveCurrentToTrash() {
        guard let url = list.current else { return }
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            Task { await cache.remove(url) }
            list.removeCurrent()
            show()
        } catch {
            errorMessage = "Couldn't move \(url.lastPathComponent) to the Trash"
        }
    }

    func rotate(_ rotation: Rotation) {
        guard let url = list.current else { return }
        do {
            try OrientationRotator.rotate(url, rotation)
            Task {
                await cache.remove(url)
                show()
            }
        } catch RotateError.unsupportedFormat {
            errorMessage = "Lossless rotation works with JPEG, HEIC and TIFF only"
        } catch {
            errorMessage = "Couldn't rotate \(url.lastPathComponent)"
        }
    }

    func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .folder]
        panel.canChooseDirectories = true
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }

    func toggleFullScreen() {
        NSApp.keyWindow?.toggleFullScreen(nil)
    }

    var isFullScreen: Bool {
        NSApp.keyWindow?.styleMask.contains(.fullScreen) == true
    }
}
```

- [ ] **Step 3: Write `ViewerView.swift`**

`Sources/Featherview/ViewerView.swift`:

```swift
import FeatherviewCore
import SwiftUI

struct ViewerView: View {
    @Bindable var model: ViewerModel
    @Environment(\.displayScale) private var displayScale
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let image = model.image {
                canvas(image)
            } else {
                Text(model.errorMessage ?? "Open an image with ⌘O, or drop one here")
                    .foregroundStyle(.secondary)
            }
        }
        .overlay(alignment: .bottom) {
            if let message = model.errorMessage, model.image != nil {
                Text(message)
                    .padding(8)
                    .background(.regularMaterial, in: .rect(cornerRadius: 6))
                    .padding()
            }
        }
        .navigationTitle(model.title)
        .inspector(isPresented: $model.showInfo) {
            InfoPanel(url: model.list.current)
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            model.open(url)
            return true
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress(action: handle)
        .frame(minWidth: 480, minHeight: 320)
    }

    @ViewBuilder
    private func canvas(_ image: CGImage) -> some View {
        let pointSize = CGSize(width: CGFloat(image.width) / displayScale,
                               height: CGFloat(image.height) / displayScale)
        switch model.zoom {
        case .fit:
            // Shrinks large images to the window; small ones stay at their real size.
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(maxWidth: pointSize.width, maxHeight: pointSize.height)
        case .factor(let factor):
            ScrollView([.horizontal, .vertical]) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(factor >= 2 ? .none : .high)
                    .frame(width: pointSize.width * factor, height: pointSize.height * factor)
            }
        }
    }

    /// Single-key shortcuts live here, not in the menus: a plain-letter menu shortcut would also
    /// fire while typing in the Batch window's text fields.
    private func handle(_ press: KeyPress) -> KeyPress.Result {
        guard press.modifiers.subtracting([.numericPad, .function]).isEmpty else { return .ignored }
        switch press.key {
        case .rightArrow, .space, .pageDown, .downArrow: model.next()
        case .leftArrow, .delete, .pageUp, .upArrow: model.previous()
        case .home: model.first()
        case .end: model.last()
        case .escape:
            guard model.isFullScreen else { return .ignored }
            model.toggleFullScreen()
        default:
            switch press.characters {
            case "r": model.rotate(.clockwise)
            case "l": model.rotate(.counterClockwise)
            case "i": model.showInfo.toggle()
            case "f": model.toggleFullScreen()
            case "0": model.setZoom(.fit)
            case "1": model.setZoom(.factor(1))
            case "+", "=": model.zoomIn()
            case "-": model.zoomOut()
            default: return .ignored
            }
        }
        return .handled
    }
}

struct InfoPanel: View {
    let url: URL?

    var body: some View {
        Form {
            ForEach(url.map(MetadataReader.fields(for:)) ?? [], id: \.label) { field in
                LabeledContent(field.label, value: field.value)
            }
        }
        .textSelection(.enabled)
        .inspectorColumnWidth(min: 220, ideal: 260)
    }
}

struct ViewerCommands: Commands {
    let model: ViewerModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open…") { model.showOpenPanel() }
                .keyboardShortcut("o")
        }
        CommandMenu("Image") {
            Button("Next  (→ or Space)") { model.next() }
            Button("Previous  (← or ⌫)") { model.previous() }
            Divider()
            Button("Rotate Right  (R)") { model.rotate(.clockwise) }
            Button("Rotate Left  (L)") { model.rotate(.counterClockwise) }
            Divider()
            Button("Move to Trash") { model.moveCurrentToTrash() }
                .keyboardShortcut(.delete, modifiers: .command)
            Button("Show Info  (I)") { model.showInfo.toggle() }
            Divider()
            Button("Batch Convert…") { openWindow(id: "batch") }
                .keyboardShortcut("b")
        }
        CommandGroup(after: .toolbar) {
            Button("Zoom to Fit  (0)") { model.setZoom(.fit) }
            Button("Actual Size  (1)") { model.setZoom(.factor(1)) }
            Button("Zoom In  (+)") { model.zoomIn() }
            Button("Zoom Out  (−)") { model.zoomOut() }
        }
    }
}
```

- [ ] **Step 4: Write `BatchView.swift`**

`Sources/Featherview/BatchView.swift`:

```swift
import FeatherviewCore
import SwiftUI

@MainActor @Observable
final class BatchModel {
    var inputs: [URL] = []
    var outputFolder: URL?
    var format = OutputFormat.jpeg
    var quality = 0.85
    var limitSize = false
    var maxDimension = 1920
    var useRename = false
    var renameTemplate = "{name}_{n:3}"
    private(set) var isRunning = false
    private(set) var done = 0
    private(set) var results: [BatchResult] = []

    var failures: [BatchResult] { results.filter { $0.error != nil } }

    func run() {
        guard let outputFolder, !inputs.isEmpty, !isRunning else { return }
        let job = BatchJob(
            inputs: inputs, outputFolder: outputFolder, format: format, quality: quality,
            maxDimension: limitSize ? max(16, maxDimension) : nil,
            rename: useRename ? RenamePattern(renameTemplate) : nil)
        isRunning = true
        done = 0
        results = []
        Task {
            results = await BatchConverter.run(job) { done, _ in
                Task { @MainActor in self.done = max(self.done, done) }
            }
            isRunning = false
        }
    }

    func addFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { inputs += panel.urls }
    }

    func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        if panel.runModal() == .OK { outputFolder = panel.url }
    }
}

struct BatchView: View {
    @Bindable var model: BatchModel
    let viewer: ViewerModel

    var body: some View {
        Form {
            Section("Images") {
                LabeledContent("Selected", value: "\(model.inputs.count)")
                HStack {
                    Button("Add Files…") { model.addFiles() }
                    Button("Use Viewer's Folder") { model.inputs = viewer.list.urls }
                        .disabled(viewer.list.isEmpty)
                    Button("Clear") { model.inputs = [] }
                }
            }
            Section("Output") {
                Picker("Format", selection: $model.format) {
                    ForEach(OutputFormat.allCases, id: \.self) { Text($0.rawValue.uppercased()) }
                }
                if model.format.isLossy {
                    Slider(value: $model.quality, in: 0.1...1) {
                        Text("Quality \(Int(model.quality * 100))")
                    }
                }
                Toggle("Limit size", isOn: $model.limitSize)
                if model.limitSize {
                    TextField("Longest side (px)", value: $model.maxDimension, format: .number)
                }
                Toggle("Rename", isOn: $model.useRename)
                if model.useRename {
                    TextField("Pattern", text: $model.renameTemplate)
                    Text("{name} = original name · {n} = number · {n:3} = 001")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Folder") {
                    Text(model.outputFolder?.path ?? "None").lineLimit(1).truncationMode(.middle)
                    Button("Choose…") { model.chooseOutputFolder() }
                }
            }
            Section {
                if model.isRunning {
                    ProgressView(value: Double(model.done), total: Double(max(model.inputs.count, 1)))
                }
                Button("Convert") { model.run() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.isRunning || model.inputs.isEmpty || model.outputFolder == nil)
                if !model.results.isEmpty {
                    Text("\(model.results.count - model.failures.count) converted, \(model.failures.count) failed")
                }
                ForEach(model.failures, id: \.input) { result in
                    Text("\(result.input.lastPathComponent): \(result.error ?? "")")
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 460, minHeight: 420)
    }
}
```

- [ ] **Step 5: Build the bundle**

Run: `scripts/bundle.sh debug`
Expected: prints `build/Featherview.app`, no errors or concurrency warnings.

- [ ] **Step 6: Smoke test**

Run: `mkdir -p /tmp/fv-smoke && sips -s format jpeg /System/Library/Desktop\ Pictures/*.heic --out /tmp/fv-smoke >/dev/null 2>&1; ls /tmp/fv-smoke | head -3; open -a "$PWD/build/Featherview.app" "/tmp/fv-smoke/$(ls /tmp/fv-smoke | head -1)"`
Expected: the window shows the image with `name — 1 / N` in the title. If the Desktop Pictures path is empty on this macOS version, copy any few JPEGs into `/tmp/fv-smoke` instead.

- [ ] **Step 7: Commit**

```bash
git add Sources/Featherview
git commit -m "feat: viewer window, keys, info panel, trash, batch window"
```

---

### Task 11: Manual QA against the spec and performance budgets

**Files:**
- Modify: `docs/spec.md` (only if QA reveals a spec gap; record the decision)

Run each check with `build/Featherview.app` built in **release** mode (`scripts/bundle.sh`). Record failures as GitHub issues (`gh issue create`) or fix them; do not mark a step done while it fails.

- [ ] **Step 1: Viewer basics** — open a file from Finder via "Open With"; title shows position; →/←/Space/Backspace/Home/End navigate and stop at the ends (the folder chooser is Milestone 2); a folder opened with ⌘O starts at its first image; dropping a file onto the window opens it.
- [ ] **Step 2: Bad files** — add `bad.jpg` (`echo x > bad.jpg`) to a folder; browsing over it shows "Can't open bad.jpg" and continues.
- [ ] **Step 3: Orientation** — a phone photo taken in portrait shows upright; R then L returns to the original; `md5 -q` of the pixel data via `sips -s format png file --out /tmp/a.png` is unchanged after R,R,R,R. Rotate a PNG → message, file unchanged.
- [ ] **Step 4: Trash** — ⌘⌫ moves the file to the Trash (check Finder), next image shows.
- [ ] **Step 5: Info and zoom** — I shows the panel with camera data on a camera JPEG; 0/1/+/− behave as in the spec; F and Esc toggle full screen.
- [ ] **Step 6: Typing safety** — in the batch window, typing "rl0f" into the rename field changes only the text, not the viewer.
- [ ] **Step 7: Batch** — 20 mixed images (JPEG/HEIC/PNG + one corrupt) → JPEG, limit 1920, rename `{name}_{n:3}`, output = input folder: 19 converted, 1 failed, nothing overwritten, outputs upright.
- [ ] **Step 8: Performance** — in one terminal: `log stream --level debug --predicate 'subsystem == "net.mynetx.featherview"'`. Make a 10,000-file folder: `mkdir /tmp/fv-10k && for i in $(seq 1 10000); do cp /tmp/fv-smoke/$(ls /tmp/fv-smoke | head -1) /tmp/fv-10k/img$i.jpg; done`. Open `img5000.jpg` from Finder; hold →. Check against the budgets in `AGENTS.md`: first image < 500 ms, logged `show` times < 150 ms for non-prefetched images and near 0 for prefetched ones, Activity Monitor memory stays flat while holding →.
- [ ] **Step 9: Website numbers** — the site (`~/Web/mx/featherview.github.io/index.html`, the three `.stat` blocks) shows the budgets (300 ms launch, 16 ms swap, 10,000 files in 0.5 s). Replace each with the median measured in Step 8 (5 runs, release build, name the Mac model and photo size in a footnote), never a number better than measured. Ask the maintainer before pushing (pushes go live).
- [ ] **Step 10: Commit any spec updates**

```bash
git add docs/spec.md
git commit -m "docs: record decisions from v1 QA"
```
