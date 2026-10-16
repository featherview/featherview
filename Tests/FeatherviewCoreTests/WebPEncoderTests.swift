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

    // Batch encodes on every core at once, and libwebp sets up its CPU-specific code on first use
    // without a lock. That only shows in a process that has not encoded yet, so this runs a child.
    @Test(.enabled(if: ProcessInfo.processInfo.environment[Self.freshKey] == nil))
    func firstEncodesInAFreshProcessRunInParallelSafely() throws {
        let arguments = CommandLine.arguments
        let bundle = try #require(arguments.firstIndex(of: "--test-bundle-path").map { arguments[$0 + 1] })
        let child = Process()
        child.executableURL = URL(fileURLWithPath: arguments[0])
        child.arguments = ["--test-bundle-path", bundle, "--filter", "parallelFirstEncodesChild", bundle,
                           "--testing-library", "swift-testing"]
        child.environment = ProcessInfo.processInfo.environment.merging([Self.freshKey: "1"]) { $1 }
        let pipe = Pipe()
        child.standardOutput = pipe
        child.standardError = pipe
        try child.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        child.waitUntilExit()
        #expect(child.terminationStatus == 0 && output.contains("parallelFirstEncodesChild()") && !output.contains("failed"),
                "\(output)")
    }

    static let freshKey = "FEATHERVIEW_FRESH_WEBP_PROCESS"

    /// libwebp's table, if it has been set up yet: a function pointer it fills in on first use.
    static func dspTable(_ name: String, slot: Int = 0) -> UnsafeRawPointer? {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) else { return nil }  // RTLD_DEFAULT
        return symbol.load(fromByteOffset: slot * MemoryLayout<UnsafeRawPointer?>.stride, as: UnsafeRawPointer?.self)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment[Self.freshKey] != nil))
    func parallelFirstEncodesChild() throws {
        // Lossless, lossy alpha (VP8FiltersInit) and the lossless coder lossy alpha uses: all untouched yet.
        let tables = [("VP8LCollectColorBlueTransforms", 0), ("WebPFilters", 1), ("VP8EncQuantizeBlock", 0)]
        #expect(tables.allSatisfy { Self.dspTable($0.0, slot: $0.1) == nil }, "not a fresh process")

        // Eight plain lossy encodes start at once; the first must set up every path, not just its own.
        let source = Self.image(256, 192)
        let results = UnsafeSendableBox([Data?](repeating: nil, count: 8))
        DispatchQueue.concurrentPerform(iterations: 8) { i in
            let data = try? WebPEncoder.encode(source, quality: 75, lossless: false, effort: 4, kind: .photo)
            results.lock.withLock { results.value[i] = data }
        }
        #expect(tables.allSatisfy { Self.dspTable($0.0, slot: $0.1) != nil }, "warm-up skipped a path")
        let serial = try WebPEncoder.encode(source, quality: 75, lossless: false, effort: 4, kind: .photo)
        #expect(results.value.allSatisfy { $0 == serial })
    }
}

/// Collects results from `concurrentPerform` in a test.
private final class UnsafeSendableBox<Value>: @unchecked Sendable {
    let lock = NSLock()
    var value: Value
    init(_ value: Value) { self.value = value }
}
