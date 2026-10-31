import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct BatchPhotosTests {
    final class Added: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [(name: String, existed: Bool, png: Bool, folder: URL)] = []
        var all: [(name: String, existed: Bool, png: Bool, folder: URL)] { lock.withLock { items } }
        func record(_ url: URL) {
            let data = (try? Data(contentsOf: url)) ?? Data()
            let item = (url.lastPathComponent, FileManager.default.fileExists(atPath: url.path),
                        data.starts(with: [0x89, 0x50, 0x4E, 0x47]), url.deletingLastPathComponent())
            lock.withLock { items.append(item) }
        }
    }

    struct Refused: Error {}

    func settings(_ edit: (inout BatchSettings) -> Void = { _ in }) -> BatchSettings {
        var s = BatchSettings()
        s.formatID = "png"
        edit(&s)
        return s
    }

    @Test func libraryInputsNeedADestination() {
        let library = BatchSettings.photosCache.appendingPathComponent("6A1F-99/IMG_0001.HEIC")
        let file = URL(fileURLWithPath: "/tmp/a.jpg")
        #expect(settings().problem(inputs: [file, library]) == PhotosText.needsDestination)
        #expect(settings { $0.outputFolder = "/tmp/out" }.problem(inputs: [library]) == nil)
        #expect(settings { $0.toPhotos = true }.problem(inputs: [library]) == nil)
        #expect(settings().problem(inputs: [file]) == nil)
    }

    /// Pictures dragged from Photos land in Dropped/<n>, a folder the app empties: like library
    /// pictures, they need a folder or the Photos library.
    @Test func droppedInputsNeedADestination() {
        let dropped = BatchSettings.droppedCache.appendingPathComponent("1/IMG_0001.HEIC")
        let file = URL(fileURLWithPath: "/tmp/a.jpg")
        #expect(settings().problem(inputs: [file, dropped]) == PhotosText.needsDestination)
        #expect(settings { $0.outputFolder = "/tmp/out" }.problem(inputs: [dropped]) == nil)
        #expect(settings { $0.toPhotos = true }.problem(inputs: [dropped]) == nil)
        #expect(settings().problem(inputs: [BatchSettings.droppedCache.deletingLastPathComponent().appendingPathComponent("Dropped-x/a.jpg")]) == nil)
    }

    @Test func photosNeedsAnImportableFormat() {
        let file = URL(fileURLWithPath: "/tmp/a.jpg")
        #expect(settings { $0.formatID = "qoi"; $0.toPhotos = true }.problem(inputs: [file]) == PhotosText.cantImport(format: "QOI"))
        #expect(settings { $0.formatID = "qoi" }.problem(inputs: [file]) == nil)
        for id in ["jpg", "heic", "png", "tiff", "gif"] { #expect(FormatRegistry.format(id: id)?.photosImports == true) }
        for id in ["qoi", "webp", "jp2", "bmp"] { #expect(FormatRegistry.format(id: id)?.photosImports == false) }
    }

    @Test func keepFormatChecksEachInputsOwnFormat() {
        let jpgs = [URL(fileURLWithPath: "/tmp/a.jpg"), URL(fileURLWithPath: "/tmp/b.JPEG")]
        let keep = settings { $0.changeFormat = false; $0.formatID = "qoi"; $0.toPhotos = true }
        #expect(keep.problem(inputs: jpgs) == nil)
        #expect(keep.problem(inputs: jpgs + [URL(fileURLWithPath: "/tmp/c.webp")]) == PhotosText.cantImport(format: "WebP"))
        let keepJPEG = settings { $0.changeFormat = false; $0.formatID = "jpg"; $0.toPhotos = true }
        #expect(keepJPEG.problem(inputs: [URL(fileURLWithPath: "/tmp/c.qoi")]) == PhotosText.cantImport(format: "QOI"))
        // No writable own format: Keep format would hand Photos the original bytes.
        for ext in ["xcf", "jxr", "psb", "dds", "sgi"] {
            #expect(keepJPEG.problem(inputs: jpgs + [URL(fileURLWithPath: "/tmp/c.\(ext)")]) == PhotosText.cantImport(format: ext.uppercased()))
        }
    }

    @Test func toPhotosIsStored() throws {
        let stored = try JSONEncoder().encode(settings { $0.toPhotos = true })
        #expect(try JSONDecoder().decode(BatchSettings.self, from: stored).toPhotos)
        #expect(try !JSONDecoder().decode(BatchSettings.self, from: Data("{}".utf8)).toPhotos)
    }

    @Test func outputsGoToPhotosAndNotToDisk() async throws {
        let dir = try Fixtures.makeTempDir(), out = try Fixtures.makeTempDir()
        let a = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 8, height: 6)
        let b = try Fixtures.writeImage(to: dir.appendingPathComponent("b.jpg"), width: 8, height: 6)
        var job = BatchJob(inputs: [a, b].map { BatchInput(url: $0) }, settings: settings {
            $0.outputFolder = out.path
            $0.renamePattern = "Trip {n}"
            $0.toPhotos = true
        })
        let added = Added()
        job.addToPhotos = { added.record($0) }

        let results = await BatchConverter.run(job)

        #expect(results.map(\.status) == [.converted, .converted])
        #expect(added.all.map(\.name) == ["Trip 1.png", "Trip 2.png"])
        #expect(added.all.allSatisfy { $0.existed && $0.png })
        #expect(added.all.allSatisfy { !$0.folder.standardizedFileURL.path.hasPrefix(dir.standardizedFileURL.path) })
        for output in results.flatMap(\.outputs) { #expect(!FileManager.default.fileExists(atPath: output.path)) }
        for item in added.all { #expect(!FileManager.default.fileExists(atPath: item.folder.appendingPathComponent(item.name).path)) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: out.path).isEmpty)
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: dir.path)) == ["a.jpg", "b.jpg"])
    }

    @Test func refusedAddFailsTheRow() async throws {
        let dir = try Fixtures.makeTempDir()
        let a = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 8, height: 6)
        let b = try Fixtures.writeImage(to: dir.appendingPathComponent("b.jpg"), width: 8, height: 6)
        var job = BatchJob(inputs: [a, b].map { BatchInput(url: $0) }, settings: settings {
            $0.toPhotos = true
            $0.safety.trashOriginals = true
        })
        let added = Added()
        job.addToPhotos = { url in
            added.record(url)
            if url.lastPathComponent == "b.png" { throw Refused() }
        }
        let trashed = BatchConverterTests.Box([URL]())

        let results = await BatchConverter.run(job, trash: { url in trashed.update { $0.append(url) } })

        #expect(results.map(\.status) == [.converted, .failed])
        #expect(results[1].message == "Can't add b.png to Photos.")
        #expect(results[1].outputs.isEmpty)
        #expect(trashed.get == [a])  // a refused output keeps its original
        for item in added.all { #expect(!FileManager.default.fileExists(atPath: item.folder.appendingPathComponent(item.name).path)) }
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: dir.path)) == ["a.jpg", "b.jpg"])
    }

    @Test func libraryInputsAreNeverTrashed() async throws {
        let cache = BatchSettings.photosCache.appendingPathComponent("test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: cache) }
        let input = try Fixtures.writeImage(to: cache.appendingPathComponent("IMG_0001.jpg"), width: 8, height: 6)
        let out = try Fixtures.makeTempDir()
        let job = BatchJob(inputs: [BatchInput(url: input)], settings: settings {
            $0.outputFolder = out.path
            $0.safety.trashOriginals = true
        })
        let trashed = BatchConverterTests.Box([URL]())

        let results = await BatchConverter.run(job, trash: { url in trashed.update { $0.append(url) } })

        #expect(results.map(\.status) == [.converted])
        #expect(trashed.get.isEmpty)
    }

    /// The batch window runs both checks on the main thread after every list change: 10,000 files stay
    /// well under a frame each (a debug build; release is several times faster).
    @Test func problemChecksAreQuickForLargeLists() {
        let urls = (0..<10_000).map { URL(fileURLWithPath: "/Users/someone/Pictures/IMG_\($0).jpg") }
        let keep = settings { $0.changeFormat = false; $0.toPhotos = true }
        let nextTo = settings()
        let clock = ContinuousClock()
        #expect(keep.problem(inputs: urls) == nil)
        #expect(nextTo.problem(inputs: urls) == nil)
        let keepTime = clock.measure { _ = keep.problem(inputs: urls) }
        let nextToTime = clock.measure { _ = nextTo.problem(inputs: urls) }
        #expect(keepTime < .milliseconds(25))
        #expect(nextToTime < .milliseconds(25))
    }
}
