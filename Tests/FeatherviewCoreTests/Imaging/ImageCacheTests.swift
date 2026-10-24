import CoreGraphics
import Foundation
import Testing
import os
@testable import FeatherviewCore

// Polling loops below wait on the queue; a regression that never queues fails at the limit instead of hanging.
@Suite(.timeLimit(.minutes(1))) struct ImageCacheTests {
    @Test func evictsLeastRecentlyUsed() async throws {
        let dir = try Fixtures.makeTempDir()
        let files = try (0..<3).map {
            try Fixtures.writeImage(to: dir.appendingPathComponent("\($0).jpg"), width: 8, height: 8)
        }
        let cache = ImageCache(capacity: 2)
        let target = DecodeTarget.fit([PixelSize(width: 100, height: 100)])
        for file in [files[0], files[1], files[0], files[2]] { _ = try await cache.image(for: file, target: target) }
        #expect(await cache.contains(files[0]))
        #expect(await !cache.contains(files[1]))
        #expect(await cache.contains(files[2]))
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

    /// Starts a job on `queue` that holds its thread until the returned semaphore is signalled; with width 1 the
    /// decodes queued after it wait, still in flight. `running`: returns once it holds the thread, not only queued.
    private func hold(_ queue: DecodeQueue, running: Bool = true) async throws -> DispatchSemaphore {
        let started = OSAllocatedUnfairLock(initialState: false), release = DispatchSemaphore(value: 0)
        let waiting = queue.waitingCount
        Task { _ = try? await queue.run(URL(fileURLWithPath: "/hold")) { started.withLock { $0 = true }; release.wait() } }
        if running { while !started.withLock({ $0 }) { try await Task.sleep(for: .milliseconds(1)) } }
        else { while queue.waitingCount <= waiting { try await Task.sleep(for: .milliseconds(1)) } }
        return release
    }

    @Test(arguments: [false, true])
    func removeDuringDecodeGivesFreshDecode(all: Bool) async throws {
        let url = try Fixtures.writeImage(to: Fixtures.makeTempDir().appendingPathComponent("a.jpg"), width: 8, height: 8)
        let queue = DecodeQueue(width: 1)
        let cache = ImageCache(queue: queue)
        let first = try await hold(queue)
        let stale = Task { try await cache.image(for: url, target: .full) }
        while await !cache.isDecoding(url) || queue.waitingCount < 1 { try await Task.sleep(for: .milliseconds(1)) }
        if all { await cache.removeAll() } else { await cache.remove(url) }  // e.g. rotated on disk
        let second = try await hold(queue, running: false)
        let fresh = Task { try await cache.image(for: url, target: .full) }
        while queue.waitingCount < 3 { try await Task.sleep(for: .milliseconds(1)) }
        first.signal()
        let staleImage = try await stale.value
        #expect(await !cache.contains(url))  // finished after the remove: not kept
        second.signal()
        let freshImage = try await fresh.value
        #expect(freshImage !== staleImage)
        #expect(try await cache.image(for: url, target: .full) === freshImage)
    }

    // Joining would hand back the larger decode: 800 px instead of 100 (800 / 8, the halving step at or above 100).
    @Test(arguments: [DecodeTarget.full, .fit([PixelSize(width: 800, height: 400)])])
    func fitRequestDoesNotJoinRunningFullDecode(running: DecodeTarget) async throws {
        let url = try Fixtures.writeImage(to: Fixtures.makeTempDir().appendingPathComponent("b.jpg"), width: 800, height: 400)
        let queue = DecodeQueue(width: 1)
        let cache = ImageCache(queue: queue)
        let release = try await hold(queue)
        let wide = Task { try await cache.image(for: url, target: running) }
        while await !cache.isDecoding(url) { try await Task.sleep(for: .milliseconds(1)) }
        let fit = Task { try await cache.image(for: url, target: .fit([PixelSize(width: 100, height: 100)])) }
        while queue.waitingCount < 2 { try await Task.sleep(for: .milliseconds(1)) }
        release.signal()
        #expect(try await fit.value.width == 100)
        #expect(try await cache.image(for: url, target: .fit([PixelSize(width: 100, height: 100)])).width == 100)
        #expect(try await wide.value.width == 800)
    }

    @Test func sameFitTargetJoinsRunningDecode() async throws {
        let url = try Fixtures.writeImage(to: Fixtures.makeTempDir().appendingPathComponent("f.jpg"), width: 800, height: 400)
        let queue = DecodeQueue(width: 1)
        let cache = ImageCache(queue: queue)
        let release = try await hold(queue)
        let target = DecodeTarget.fit([PixelSize(width: 400, height: 200)])
        let first = Task { try await cache.image(for: url, target: target) }
        while await !cache.isDecoding(url) { try await Task.sleep(for: .milliseconds(1)) }
        let second = Task { try await cache.image(for: url, target: target) }
        release.signal()
        let (a, b) = try await (first.value, second.value)
        #expect(a === b)
        #expect(a.width == 400)
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
        let url = try Fixtures.writeImage(to: Fixtures.makeTempDir().appendingPathComponent("d.jpg"), width: 80, height: 40)
        let queue = DecodeQueue(width: 1)
        let cache = ImageCache(queue: queue)
        let release = try await hold(queue)
        let keeper = Task { try await cache.image(for: url, target: .full) }
        while await !cache.isDecoding(url) { try await Task.sleep(for: .milliseconds(1)) }
        let quitter = Task { try await cache.image(for: url, target: .full) }
        quitter.cancel()
        release.signal()
        #expect(try await keeper.value.width == 80)
    }

    @Test func decodeFinishingOutsideTheWindowIsNotKept() async throws {
        let dir = try Fixtures.makeTempDir()
        // Large, so it is still running when the window moves on.
        let url = try Fixtures.writeImage(to: dir.appendingPathComponent("i.jpg"), width: 6000, height: 4000)
        let other = try Fixtures.writeImage(to: dir.appendingPathComponent("j.jpg"), width: 8, height: 8)
        let queue = DecodeQueue(width: 1)
        let cache = ImageCache(queue: queue)
        let release = try await hold(queue)
        queue.focus([url, URL(fileURLWithPath: "/hold")])
        let decode = Task { try await cache.image(for: url, target: .full) }
        while queue.waitingCount < 1 { await Task.yield() }
        release.signal()
        while queue.waitingCount > 0 { await Task.yield() }  // started
        queue.focus([other])  // moved on while it runs
        // Still in flight here means it has not yet decided whether to keep the image. A machine so loaded that
        // the decode already finished proves nothing either way.
        guard await cache.isDecoding(url) else { return }
        _ = try await decode.value
        #expect(await !cache.contains(url))
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

    @Test func byteBudgetEvicts() async throws {
        let dir = try Fixtures.makeTempDir()
        let files = try (0..<3).map {
            try Fixtures.writeImage(to: dir.appendingPathComponent("\($0).jpg"), width: 100, height: 100)
        }
        let one = try ImageDecoder.decode(files[0], halvingSteps: true)
        let cache = ImageCache(capacity: 10, byteBudget: 2 * one.bytesPerRow * one.height)
        for file in files { _ = try await cache.image(for: file, target: .full) }
        #expect(await cache.count == 2)
        #expect(await !cache.contains(files[0]))
    }

    @Test func largerThumbnailServesSmaller() async throws {
        let url = try Fixtures.writeImage(to: Fixtures.makeTempDir().appendingPathComponent("a.jpg"), width: 400, height: 300)
        let cache = ImageCache()
        let large = try await cache.image(for: url, target: .thumbnail(256))
        let small = try await cache.image(for: url, target: .thumbnail(128))
        #expect(large === small)
    }

    @Test func smallerThumbnailJoinsRunningLargerDecode() async throws {
        let url = try Fixtures.writeImage(to: Fixtures.makeTempDir().appendingPathComponent("a.jpg"), width: 400, height: 300)
        let queue = DecodeQueue(width: 1)
        let cache = ImageCache(queue: queue)
        let release = try await hold(queue)
        let large = Task { try await cache.image(for: url, target: .thumbnail(256)) }
        while await !cache.isDecoding(url) { try await Task.sleep(for: .milliseconds(1)) }
        // A second decode would take over the running one, which could then neither store nor be cancelled.
        let small = Task { try await cache.image(for: url, target: .thumbnail(128)) }
        release.signal()
        #expect(try await large.value === small.value)
        // Kept as the 256 decode it is, so it still serves 256.
        #expect(try await cache.image(for: url, target: .thumbnail(256)) === small.value)
    }

    @Test func largerThumbnailTakingOverStillLetsTheSmallerBeCancelled() async throws {
        let url = try Fixtures.writeImage(to: Fixtures.makeTempDir().appendingPathComponent("a.jpg"), width: 400, height: 300)
        let queue = DecodeQueue(width: 1)
        let cache = ImageCache(queue: queue)
        // Holds the only thread, so both thumbnail decodes wait.
        let release = try await hold(queue)
        let small = Task { try await cache.image(for: url, target: .thumbnail(128)) }
        while queue.waitingCount < 1 { try await Task.sleep(for: .milliseconds(1)) }
        let large = Task { try await cache.image(for: url, target: .thumbnail(256)) }
        while queue.waitingCount < 2 { try await Task.sleep(for: .milliseconds(1)) }
        small.cancel()
        while queue.waitingCount > 1 { try await Task.sleep(for: .milliseconds(1)) }
        release.signal()
        // Its waiting decode is dropped, not run and thrown away ahead of the 256 one.
        await #expect(throws: CancellationError.self) { try await small.value }
        #expect(try await large.value.width == 256)
    }

    @Test func smallerThumbnailDoesNotServeLarger() async throws {
        let url = try Fixtures.writeImage(to: Fixtures.makeTempDir().appendingPathComponent("a.jpg"), width: 400, height: 300)
        let cache = ImageCache()
        let small = try await cache.image(for: url, target: .thumbnail(128))
        let large = try await cache.image(for: url, target: .thumbnail(256))
        #expect(small !== large)
        #expect(large.width == 256)
    }

    @Test func thumbnailNeverServesFit() async throws {
        let url = try Fixtures.writeImage(to: Fixtures.makeTempDir().appendingPathComponent("a.jpg"), width: 1000, height: 750)
        let cache = ImageCache()
        let thumb = try await cache.image(for: url, target: .thumbnail(512))
        let fit = try await cache.image(for: url, target: .fit([PixelSize(width: 2000, height: 2000)]))
        #expect(thumb !== fit)
        #expect(fit.width == 1000)
    }

    /// The grid shows a kept picture in the same frame from it; it never holds what the budget evicted.
    @Test func cachedAnswersAtOnceWithKeptImagesOnly() async throws {
        let dir = try Fixtures.makeTempDir()
        let files = try (0..<3).map {
            try Fixtures.writeImage(to: dir.appendingPathComponent("\($0).jpg"), width: 400, height: 300)
        }
        let one = try await ImageCache().image(for: files[0], target: .thumbnail(128))
        let cache = ImageCache(capacity: .max, byteBudget: 2 * one.bytesPerRow * one.height)
        for file in files { _ = try await cache.image(for: file, target: .thumbnail(128)) }
        #expect(cache.cached(files[0], target: .thumbnail(128)) == nil)
        #expect(cache.cached(files[2], target: .thumbnail(128)) != nil)
        #expect(cache.cached(files[2], target: .thumbnail(256)) == nil)
        await cache.remove(files[2])
        #expect(cache.cached(files[2], target: .thumbnail(128)) == nil)
    }

    // The window moved to a screen with another colour space: images come in that one, decoded again.
    @Test func anotherColourSpaceDecodesAgain() async throws {
        let url = try Fixtures.writeImage(to: Fixtures.makeTempDir().appendingPathComponent("s.jpg"), width: 8, height: 8)
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!, p3 = CGColorSpace(name: CGColorSpace.displayP3)!
        let cache = ImageCache(colorSpace: srgb)
        let target = DecodeTarget.fit([PixelSize(width: 100, height: 100)])
        #expect(try await cache.image(for: url, target: target).colorSpace?.name == CGColorSpace.sRGB)
        await cache.setColorSpace(srgb)
        #expect(await cache.contains(url))
        await cache.setColorSpace(p3)
        #expect(await !cache.contains(url))
        #expect(try await cache.image(for: url, target: target).colorSpace?.name == CGColorSpace.displayP3)
    }

    @Test func decodeInTheOldColourSpaceIsNotKept() async throws {
        let url = try Fixtures.writeImage(to: Fixtures.makeTempDir().appendingPathComponent("o.jpg"), width: 8, height: 8)
        let queue = DecodeQueue(width: 1)
        let cache = ImageCache(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, queue: queue)
        let release = try await hold(queue)
        let old = Task { try await cache.image(for: url, target: .full) }
        while await !cache.isDecoding(url) { try await Task.sleep(for: .milliseconds(1)) }
        await cache.setColorSpace(CGColorSpace(name: CGColorSpace.displayP3)!)
        release.signal()
        _ = try await old.value
        #expect(await !cache.contains(url))
    }
}
