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

    // Starts a slow full-size decode of a large image and returns once it is in flight.
    private func startLargeDecode(_ cache: ImageCache, _ url: URL) async throws {
        try Fixtures.writeImage(to: url, width: 6000, height: 4000)
        Task { _ = try? await cache.image(for: url, maxPixelSize: nil) }
        while await !cache.isDecoding(url) { await Task.yield() }
    }

    @Test func removeDuringDecodeGivesFreshDecode() async throws {
        let url = try Fixtures.makeTempDir().appendingPathComponent("a.jpg")
        let cache = ImageCache()
        try await startLargeDecode(cache, url)
        try Fixtures.writeImage(to: url, width: 40, height: 20)  // e.g. rotated on disk
        await cache.remove(url)
        #expect(try await cache.image(for: url, maxPixelSize: nil).width == 40)
        #expect(try await cache.image(for: url, maxPixelSize: nil).width == 40)
    }

    @Test func removeAllDuringDecodeGivesFreshDecode() async throws {
        let url = try Fixtures.makeTempDir().appendingPathComponent("a.jpg")
        let cache = ImageCache()
        try await startLargeDecode(cache, url)
        try Fixtures.writeImage(to: url, width: 40, height: 20)
        await cache.removeAll()
        #expect(try await cache.image(for: url, maxPixelSize: nil).width == 40)
        #expect(try await cache.image(for: url, maxPixelSize: nil).width == 40)
    }

    @Test func differentSizeDoesNotJoinRunningDecode() async throws {
        let url = try Fixtures.makeTempDir().appendingPathComponent("b.jpg")
        let cache = ImageCache()
        try await startLargeDecode(cache, url)
        #expect(try await cache.image(for: url, maxPixelSize: 100).width == 100)
        #expect(try await cache.image(for: url, maxPixelSize: 100).width == 100)
    }
}
