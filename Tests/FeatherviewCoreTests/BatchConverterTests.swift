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
