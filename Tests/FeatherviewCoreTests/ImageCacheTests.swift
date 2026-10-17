import CoreGraphics
import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct ImageCacheTests {
    @Test func concurrentRequestsDecodeOnce() async throws {
        let dir = try Fixtures.makeTempDir()
        let url = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 8, height: 8)
        let cache = ImageCache(capacity: 2)
        async let first = cache.image(for: url, target: .fit([PixelSize(width: 100, height: 100)]))
        async let second = cache.image(for: url, target: .fit([PixelSize(width: 100, height: 100)]))
        let (a, b) = try await (first, second)
        #expect(a === b)
    }

    @Test func evictsLeastRecentlyUsed() async throws {
        let dir = try Fixtures.makeTempDir()
        let files = try (0..<3).map {
            try Fixtures.writeImage(to: dir.appendingPathComponent("\($0).jpg"), width: 8, height: 8)
        }
        let cache = ImageCache(capacity: 2)
        for file in files { _ = try await cache.image(for: file, target: .fit([PixelSize(width: 100, height: 100)])) }
        #expect(await cache.count == 2)
    }

    @Test func decodedBytesCountsKeptImagesOnly() async throws {
        let dir = try Fixtures.makeTempDir()
        let files = try (0..<3).map {
            try Fixtures.writeImage(to: dir.appendingPathComponent("\($0).jpg"), width: 64, height: 32)
        }
        let cache = ImageCache(capacity: 2)
        #expect(await cache.decodedBytes == 0)
        var images: [CGImage] = []
        for file in files { images.append(try await cache.image(for: file, target: .full)) }
        #expect(await cache.decodedBytes == images.suffix(2).reduce(0) { $0 + $1.bytesPerRow * $1.height })
        await cache.removeAll()
        #expect(await cache.decodedBytes == 0)
    }

    @Test func failuresAreNotCached() async throws {
        let dir = try Fixtures.makeTempDir()
        let bad = try Fixtures.writeCorrupt(to: dir.appendingPathComponent("bad.jpg"))
        let cache = ImageCache()
        await #expect(throws: DecodeError.self) { try await cache.image(for: bad, target: .fit([PixelSize(width: 100, height: 100)])) }
        #expect(await cache.count == 0)
    }

    // Starts a slow full-size decode of a large image and returns once it is in flight.
    private func startLargeDecode(_ cache: ImageCache, _ url: URL) async throws {
        try Fixtures.writeImage(to: url, width: 6000, height: 4000)
        Task { _ = try? await cache.image(for: url, target: .full) }
        while await !cache.isDecoding(url) { await Task.yield() }
    }

    @Test func removeDuringDecodeGivesFreshDecode() async throws {
        let url = try Fixtures.makeTempDir().appendingPathComponent("a.jpg")
        let cache = ImageCache()
        try await startLargeDecode(cache, url)
        try Fixtures.writeImage(to: url, width: 40, height: 20)  // e.g. rotated on disk
        await cache.remove(url)
        #expect(try await cache.image(for: url, target: .full).width == 40)
        #expect(try await cache.image(for: url, target: .full).width == 40)
    }

    @Test func removeAllDuringDecodeGivesFreshDecode() async throws {
        let url = try Fixtures.makeTempDir().appendingPathComponent("a.jpg")
        let cache = ImageCache()
        try await startLargeDecode(cache, url)
        try Fixtures.writeImage(to: url, width: 40, height: 20)
        await cache.removeAll()
        #expect(try await cache.image(for: url, target: .full).width == 40)
        #expect(try await cache.image(for: url, target: .full).width == 40)
    }

    @Test func differentSizeDoesNotJoinRunningDecode() async throws {
        let url = try Fixtures.makeTempDir().appendingPathComponent("b.jpg")
        let cache = ImageCache()
        try await startLargeDecode(cache, url)
        // 750 = 6000 / 8, the halving step at or above 100.
        #expect(try await cache.image(for: url, target: .fit([PixelSize(width: 100, height: 100)])).width == 750)
        #expect(try await cache.image(for: url, target: .fit([PixelSize(width: 100, height: 100)])).width == 750)
    }

    @Test func differentFitTargetDoesNotJoinRunningDecode() async throws {
        let url = try Fixtures.makeTempDir().appendingPathComponent("e.jpg")
        let cache = ImageCache()
        try Fixtures.writeImage(to: url, width: 6000, height: 4000)
        let wide = Task { try await cache.image(for: url, target: .fit([PixelSize(width: 6000, height: 4000)])) }
        while await !cache.isDecoding(url) { await Task.yield() }
        // Joining would hand back the full-size 6000 px decode.
        #expect(try await cache.image(for: url, target: .fit([PixelSize(width: 100, height: 100)])).width == 750)
        _ = try await wide.value
    }

    @Test func sameFitTargetJoinsRunningDecode() async throws {
        let url = try Fixtures.makeTempDir().appendingPathComponent("f.jpg")
        let cache = ImageCache()
        try Fixtures.writeImage(to: url, width: 6000, height: 4000)
        let target = DecodeTarget.fit([PixelSize(width: 3000, height: 2000)])
        async let first = cache.image(for: url, target: target)
        async let second = cache.image(for: url, target: target)
        let (a, b) = try await (first, second)
        #expect(a === b)
        #expect(a.width == 3000)
    }

    @Test func cancelledCallerSkipsDecode() async throws {
        let url = try Fixtures.writeImage(to: Fixtures.makeTempDir().appendingPathComponent("c.jpg"), width: 8, height: 8)
        let cache = ImageCache()
        // Cancelled before it asks: cancelling from outside could race a task already running.
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await cache.image(for: url, target: .fit([PixelSize(width: 100, height: 100)]))
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await cache.count == 0)
        #expect(await !cache.isDecoding(url))
    }

    @Test func cancellingOneWaiterKeepsTheSharedDecode() async throws {
        let url = try Fixtures.makeTempDir().appendingPathComponent("d.jpg")
        try Fixtures.writeImage(to: url, width: 6000, height: 4000)
        let cache = ImageCache()
        let keeper = Task { try await cache.image(for: url, target: .full) }
        while await !cache.isDecoding(url) { await Task.yield() }
        let quitter = Task { try await cache.image(for: url, target: .full) }
        quitter.cancel()
        #expect(try await keeper.value.width == 6000)
    }

    @Test func zoomingWithinAStepDoesNotDecodeAgain() async throws {
        let url = try Fixtures.writeImage(to: Fixtures.makeTempDir().appendingPathComponent("g.jpg"), width: 400, height: 200)
        let cache = ImageCache(capacity: 1)
        let first = try await cache.image(for: url, target: .step(1))
        #expect(first.width == 200)
        #expect(try await cache.image(for: url, target: .step(1)) === first)
    }

    @Test func anotherStepDecodesAgain() async throws {
        let url = try Fixtures.writeImage(to: Fixtures.makeTempDir().appendingPathComponent("h.jpg"), width: 400, height: 200)
        let cache = ImageCache(capacity: 1)
        _ = try await cache.image(for: url, target: .step(1))
        // A cached ½ decode must not stand in for full size: zooming past its step would never sharpen.
        #expect(try await cache.image(for: url, target: .step(0)).width == 400)
        #expect(try await cache.image(for: url, target: .step(2)).width == 100)
    }
}
