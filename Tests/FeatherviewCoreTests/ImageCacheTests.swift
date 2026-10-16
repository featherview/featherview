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
