import CoreGraphics
import Foundation
import ImageIO
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

    @Test func neverReplacesAFileThatAppearedAfterPlanning() throws {
        let dir = try Fixtures.makeTempDir()
        let input = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 8, height: 8)
        let out = try Fixtures.makeTempDir()
        let planned = out.appendingPathComponent("a.png")
        try Data("precious".utf8).write(to: planned)  // e.g. a sync client dropped it there mid-batch

        let result = BatchConverter.convert(input, to: planned, job: BatchJob(inputs: [input], outputFolder: out, format: .png))

        #expect(result.error == nil)
        #expect(try Data(contentsOf: planned) == Data("precious".utf8))
        #expect(result.output.lastPathComponent == "a 2.png")
        #expect(ImageDecoder.displaySize(of: result.output) == CGSize(width: 8, height: 8))
        // No temp file is left behind.
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: out.path)) == ["a.png", "a 2.png"])
    }

    @Test func concurrentBatchesIntoOneFolderKeepBothOutputs() async throws {
        let dir = try Fixtures.makeTempDir()
        let input = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 8, height: 8)
        let out = try Fixtures.makeTempDir()
        let job = BatchJob(inputs: [input], outputFolder: out, format: .png)
        async let first = BatchConverter.run(job)
        async let second = BatchConverter.run(job)
        let outputs = await (first + second).map(\.output.path)
        #expect(Set(outputs).count == 2)
        #expect(try FileManager.default.contentsOfDirectory(atPath: out.path).count == 2)
    }

    @Test(arguments: OutputFormat.allCases)
    func keepsCameraExifGpsAndIptcMetadata(format: OutputFormat) async throws {
        let dir = try Fixtures.makeTempDir()
        let input = try Fixtures.writeImage(
            to: dir.appendingPathComponent("meta.jpg"), width: 40, height: 20, orientation: 6,
            properties: [
                kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Canon", kCGImagePropertyTIFFModel: "EOS R5"],
                kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2024:05:01 12:00:00"],
                kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 52.5, kCGImagePropertyGPSLatitudeRef: "N"],
                kCGImagePropertyIPTCDictionary: [kCGImagePropertyIPTCKeywords: ["holiday"]],
            ])
        let out = try Fixtures.makeTempDir()

        let result = try #require(await BatchConverter.run(BatchJob(inputs: [input], outputFolder: out, format: format)).first)

        #expect(result.error == nil)
        let source = try #require(CGImageSourceCreateWithURL(result.output as CFURL, nil))
        let props = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any]
        let iptc = props[kCGImagePropertyIPTCDictionary] as? [CFString: Any]
        #expect(tiff?[kCGImagePropertyTIFFMake] as? String == "Canon")
        #expect(tiff?[kCGImagePropertyTIFFModel] as? String == "EOS R5")
        #expect(exif?[kCGImagePropertyExifDateTimeOriginal] as? String == "2024:05:01 12:00:00")
        #expect(gps?[kCGImagePropertyGPSLatitude] as? Double == 52.5)
        #expect(iptc?[kCGImagePropertyIPTCKeywords] as? [String] == ["holiday"])
        #expect(props[kCGImagePropertyOrientation] as? Int ?? 1 == 1)
    }

    @Test func convertsOffTheCooperativeThreadPool() async throws {
        let dir = try Fixtures.makeTempDir()
        let input = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 8, height: 8)
        let labels = Labels()
        _ = await BatchConverter.run(BatchJob(inputs: [input], outputFolder: dir, format: .png)) { input, output, job in
            labels.add(String(cString: __dispatch_queue_get_label(nil)))
            return BatchConverter.convert(input, to: output, job: job)
        }
        // Blocking ImageIO work on the pool would starve the viewer's decode tasks.
        #expect(labels.all.count == 1)
        #expect(!labels.all.contains { $0.contains("cooperative") })
    }

    // exFAT (camera cards, USB sticks) answers RENAME_EXCL with ENOTSUP.
    @Test func movesWithoutRenameExclWhereTheVolumeLacksIt() throws {
        let dir = try Fixtures.makeTempDir()
        let temp = dir.appendingPathComponent("a.tmp"), target = dir.appendingPathComponent("a.png")
        try Data("new".utf8).write(to: temp)
        #expect(BatchConverter.moveExclusive(temp.path, target.path) { _, _ in ENOTSUP } == 0)
        #expect(try Data(contentsOf: target) == Data("new".utf8))
        #expect(!FileManager.default.fileExists(atPath: temp.path))

        try Data("new".utf8).write(to: temp)
        #expect(BatchConverter.moveExclusive(temp.path, target.path) { _, _ in ENOTSUP } == EEXIST)
        #expect(try Data(contentsOf: target) == Data("new".utf8))  // existing file untouched
    }

    final class Labels: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [String] = []
        func add(_ s: String) { lock.withLock { values.append(s) } }
        var all: [String] { lock.withLock { values } }
    }
}
