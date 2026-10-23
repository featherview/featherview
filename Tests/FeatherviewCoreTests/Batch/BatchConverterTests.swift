import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import FeatherviewCore
import FeatherviewJXL

@Suite struct BatchConverterTests {
    final class Box<T: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var value: T
        init(_ value: T) { self.value = value }
        func update(_ change: (inout T) -> Void) { lock.withLock { change(&value) } }
        var get: T { lock.withLock { value } }
    }

    func job(_ inputs: [URL], out: URL, format: String = "png", root: URL? = nil,
             _ edit: (inout BatchSettings) -> Void = { _ in }) -> BatchJob {
        var s = BatchSettings()
        s.formatID = format
        s.outputFolder = out.path
        edit(&s)
        return BatchJob(inputs: inputs.map { BatchInput(url: $0, root: root) }, settings: s)
    }

    /// A Trash stand-in: records each URL and moves it to a folder of its own.
    final class FakeTrash: @unchecked Sendable {
        let folder: URL
        private let lock = NSLock()
        private var items: [URL] = []
        init() throws { folder = try Fixtures.makeTempDir() }
        var trashed: [URL] { lock.withLock { items } }
        var names: [String] { trashed.map(\.lastPathComponent) }
        func trash(_ url: URL) throws {
            lock.withLock { items.append(url) }
            try FileManager.default.moveItem(at: url, to: folder.appendingPathComponent(UUID().uuidString + url.lastPathComponent))
        }
    }

    // MARK: Milestone 1 cases

    @Test func convertsResizesAndReportsFailuresWithoutStopping() async throws {
        let dir = try Fixtures.makeTempDir()
        let rotated = try Fixtures.writeImage(to: dir.appendingPathComponent("rot.jpg"), width: 40, height: 20, orientation: 6)
        let big = try Fixtures.writeImage(to: dir.appendingPathComponent("big.png"), width: 4000, height: 2000, type: .png)
        let bad = try Fixtures.writeCorrupt(to: dir.appendingPathComponent("bad.jpg"))
        let out = try Fixtures.makeTempDir()
        let job = job([rotated, big, bad], out: out, format: "jpg") {
            $0.resize.isOn = true
            $0.resize.side = 100
        }
        let seen = Box([URL]())

        let results = await BatchConverter.run(job) { r in seen.update { $0.append(r.input) } }

        #expect(results.map(\.input) == [rotated, big, bad])
        #expect(seen.get == [rotated, big, bad])
        #expect(results.map(\.status) == [.converted, .converted, .failed])
        #expect(ImageDecoder.displaySize(of: try #require(results[0].output)) == CGSize(width: 20, height: 40))  // upright, not upscaled
        #expect(ImageDecoder.displaySize(of: try #require(results[1].output)) == CGSize(width: 100, height: 50))
        #expect(results[2].output == nil)
        #expect(results[2].message == "Can't open bad.jpg")
        #expect(try FileManager.default.contentsOfDirectory(atPath: out.path).count == 2)
    }

    @Test func encodesHEIC() async throws {
        let dir = try Fixtures.makeTempDir()
        let input = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 64, height: 64)
        let results = await BatchConverter.run(job([input], out: dir, format: "heic"))
        #expect(results.first?.status == .converted)
    }

    @Test func neverReplacesAFileThatAppearedAfterNaming() throws {
        let out = try Fixtures.makeTempDir()
        let planned = out.appendingPathComponent("a.png")
        try Data("precious".utf8).write(to: planned)  // e.g. a sync client dropped it there mid-batch

        let written = try BatchConverter.write(Data("new".utf8), to: planned)

        #expect(try Data(contentsOf: planned) == Data("precious".utf8))
        #expect(written.lastPathComponent == "a 2.png")
        #expect(try Data(contentsOf: written) == Data("new".utf8))
        // No temp file is left behind.
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: out.path)) == ["a.png", "a 2.png"])
    }

    @Test func concurrentBatchesIntoOneFolderKeepBothOutputs() async throws {
        let dir = try Fixtures.makeTempDir()
        let input = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 8, height: 8)
        let out = try Fixtures.makeTempDir()
        let job = job([input], out: out)
        async let first = BatchConverter.run(job)
        async let second = BatchConverter.run(job)
        let outputs = await (first + second).compactMap { $0.output?.path }
        #expect(Set(outputs).count == 2)
        #expect(try FileManager.default.contentsOfDirectory(atPath: out.path).count == 2)
    }

    @Test(arguments: ["jpg", "png", "heic", "tiff"])
    func keepsCameraExifGpsAndIptcMetadata(format: String) async throws {
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

        let result = try #require(await BatchConverter.run(job([input], out: out, format: format)).first)

        let output = try #require(result.output)
        let source = try #require(CGImageSourceCreateWithURL(output as CFURL, nil))
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
        let labels = Box([String]())
        let job = job([input], out: dir)
        _ = await BatchConverter.run(job, prepare: { index, input in
            labels.update { $0.append(String(cString: __dispatch_queue_get_label(nil))) }
            return BatchConverter.prepare(input, index: index, settings: job.settings, watermark: .success(nil))
        })
        // Blocking ImageIO work on the pool would starve the viewer's decode tasks.
        #expect(labels.get.count == 1)
        #expect(!labels.get.contains { $0.contains("cooperative") })
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

    // MARK: Order and counter

    @Test func counterFollowsListOrderAndSkipsFailures() async throws {
        let out = try Fixtures.makeTempDir()
        let inputs = (1...5).map { URL(fileURLWithPath: "/in/\($0).jpg") }
        let job = job(inputs, out: out) {
            $0.renamePattern = "{n:3}"
        }
        let order = Box([URL]())

        let results = await BatchConverter.run(job, workers: 4, onResult: { r in order.update { $0.append(r.input) } },
                                               prepare: { index, _ in
            if index == 1 { return BatchConverter.Prepared(error: "Can't open 2.jpg") }
            if index != 3 { Thread.sleep(forTimeInterval: 0.1) }  // input 4 finishes first
            return BatchConverter.Prepared(data: Data("\(index)".utf8))
        })

        #expect(order.get == inputs)
        #expect(results.map { $0.output?.lastPathComponent } == ["001.png", nil, "002.png", "003.png", "004.png"])
        #expect(try Data(contentsOf: out.appendingPathComponent("003.png")) == Data("3".utf8))
        #expect(results[1].logLine == "Can't open 2.jpg")
    }

    @Test func renameModeCopiesBytes() async throws {
        let dir = try Fixtures.makeTempDir(), out = try Fixtures.makeTempDir()
        let input = try Fixtures.writeImage(to: dir.appendingPathComponent("IMG_1.jpg"), width: 8, height: 8)
        let results = await BatchConverter.run(job([input], out: out) {
            $0.changeFormat = false
            $0.renamePattern = "Holiday {n:3}"
        })
        let output = try #require(results.first?.output)
        #expect(output.lastPathComponent == "Holiday 001.jpg")
        #expect(try Data(contentsOf: output) == Data(contentsOf: input))
    }

    @Test func renameModeFailsForADanglingSymlink() async throws {
        let dir = try Fixtures.makeTempDir(), out = try Fixtures.makeTempDir()
        let link = dir.appendingPathComponent("dangling.jpg")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: dir.appendingPathComponent("gone.jpg"))
        let trash = try FakeTrash()

        let results = await BatchConverter.run(job([link], out: out) {
            $0.changeFormat = false
            $0.safety.trashOriginals = true
        }, trash: trash.trash)

        #expect(results.first?.status == .failed)
        #expect(results.first?.logLine == "Can't open dangling.jpg")
        #expect(trash.trashed.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: out.path).isEmpty)
    }

    @Test func convertAndRenameUsesPattern() async throws {
        let dir = try Fixtures.makeTempDir(), out = try Fixtures.makeTempDir()
        let a = try Fixtures.writeImage(to: dir.appendingPathComponent("IMG_1.jpg"), width: 8, height: 8)
        let b = try Fixtures.writeImage(to: dir.appendingPathComponent("IMG_2.jpg"), width: 8, height: 8)
        let results = await BatchConverter.run(job([a, b], out: out) {
            $0.renamePattern = "Holiday {n:3}"
        })
        #expect(results.map { $0.output?.lastPathComponent } == ["Holiday 001.png", "Holiday 002.png"])
        #expect(results[0].logLine == "IMG_1.jpg → Holiday 001.png")
    }

    // MARK: Keep format

    @Test func keepFormatCopiesBesideOriginals() async throws {
        let dir = try Fixtures.makeTempDir()
        let a = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 8, height: 8)
        let b = try Fixtures.writeImage(to: dir.appendingPathComponent("b.png"), width: 8, height: 8, type: .png)
        let before = [try Data(contentsOf: a), try Data(contentsOf: b)]

        let results = await BatchConverter.run(job([a, b], out: dir) {
            $0.changeFormat = false
            $0.outputFolder = ""
        })

        #expect(results.map(\.status) == [.converted, .converted])
        let expected: [String?] = [dir.appendingPathComponent("a 2.jpg").path, dir.appendingPathComponent("b 2.png").path]
        #expect(results.map { $0.output?.path } == expected)
        #expect(try results.map { try Data(contentsOf: try #require($0.output)) } == before)
        #expect(try [Data(contentsOf: a), Data(contentsOf: b)] == before)
    }

    @Test func keepFormatResavesInOwnFormat() async throws {
        let dir = try Fixtures.makeTempDir(), out = try Fixtures.makeTempDir()
        let input = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 400, height: 200)

        let results = await BatchConverter.run(job([input], out: out, format: "png") {
            $0.changeFormat = false
            $0.resize.isOn = true
            $0.resize.side = 100
        })

        let output = try #require(results.first?.output)
        #expect(output.lastPathComponent == "a.jpg")
        #expect(ImageDecoder.displaySize(of: output) == CGSize(width: 100, height: 50))
        let type = CGImageSourceCreateWithURL(output as CFURL, nil).flatMap(CGImageSourceGetType) as String?
        #expect(type == "public.jpeg")
    }

    @Test func keepFormatMixedList() async throws {
        let dir = try Fixtures.makeTempDir(), out = try Fixtures.makeTempDir()
        let jpeg = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 40, height: 20)
        let png = try Fixtures.writeImage(to: dir.appendingPathComponent("b.png"), width: 40, height: 20, type: .png)
        // Two pages, as in PCXCodecTests.dcxPagesThroughImageDecoder.
        let first = try PCXCodec.encode(RGBAImage(width: 3, height: 2))
        let second = try PCXCodec.encode(RGBAImage(width: 5, height: 4))
        let dcx = dir.appendingPathComponent("c.dcx")
        try Data(Fixtures.le32(0x3ADE68B1) + Fixtures.le32(16) + Fixtures.le32(16 + first.count) + Fixtures.le32(0) + first + second).write(to: dcx)
        // ImageIO reads it (JPEG bytes); nothing writes CR3.
        let raw = dir.appendingPathComponent("d.cr3")
        try FileManager.default.copyItem(at: jpeg, to: raw)

        let results = await BatchConverter.run(job([jpeg, png, dcx, raw], out: out) {
            $0.changeFormat = false
            $0.resize.isOn = true
            $0.resize.side = 10
        })

        #expect(results.map(\.input) == [jpeg, png, dcx, raw])
        #expect(results.map(\.status) == [.converted, .converted, .failed, .failed])
        #expect(results.map { $0.output?.lastPathComponent } == ["a.jpg", "b.png", nil, nil])
        #expect(results[2].message == "Can't save c.dcx in its own format")
        #expect(results[3].message == "Can't save d.cr3 in its own format")
        let png2 = try #require(results[1].output)
        #expect(CGImageSourceCreateWithURL(png2 as CFURL, nil).flatMap(CGImageSourceGetType) as String? == "public.png")
    }

    @Test func keepFormatPicksTheWriterByExtension() async throws {
        let dir = try Fixtures.makeTempDir(), out = try Fixtures.makeTempDir()
        // .pbm, .pgm and .ppm share one UTType; .heif and .jfif have none of the writers' types.
        let pgm = dir.appendingPathComponent("a.pgm"), ppm = dir.appendingPathComponent("b.ppm")
        try Data("P2\n2 1\n255\n0 128\n".utf8).write(to: pgm)
        try Data("P3\n2 1\n255\n255 0 0 0 0 255\n".utf8).write(to: ppm)
        let heif = try Fixtures.writeImage(to: dir.appendingPathComponent("c.heif"), width: 40, height: 20, type: .heic)
        let jfif = dir.appendingPathComponent("d.jfif")
        try FileManager.default.copyItem(at: try Fixtures.writeImage(to: dir.appendingPathComponent("d.jpg"), width: 40, height: 20), to: jfif)

        let results = await BatchConverter.run(job([pgm, ppm, heif, jfif], out: out) {
            $0.changeFormat = false
            $0.resize.isOn = true
            $0.resize.side = 10
        })

        #expect(results.map(\.status) == [.converted, .converted, .converted, .converted])
        #expect(results.map { $0.output?.lastPathComponent } == ["a.pgm", "b.ppm", "c.heif", "d.jfif"])
        let magic = try results.prefix(2).map { String(decoding: try Data(contentsOf: try #require($0.output)).prefix(2), as: UTF8.self) }
        #expect(magic == ["P5", "P6"] || magic == ["P2", "P3"])
        let types = try results.suffix(2).map { CGImageSourceCreateWithURL(try #require($0.output) as CFURL, nil).flatMap(CGImageSourceGetType) as String? }
        // ImageIO names a HEIC file's type by its extension too: public.heif for .heif.
        #expect(types == ["public.heif", "public.jpeg"])
    }

    @Test func jxlInputsKeepTheirFormat() async throws {
        _ = Fixtures.jxl
        let dir = try Fixtures.makeTempDir(), out = try Fixtures.makeTempDir()
        let inputs = try ["a.jxl", "b.jxl"].map { name in
            let source = try ImageDecoder.decode(
                try Fixtures.writeImage(to: dir.appendingPathComponent(name + ".png"), width: 40, height: 20, type: .png))
            let url = dir.appendingPathComponent(name)
            try JXLEncoder.encode(source, quality: 90, lossless: false, effort: 3, xmp: nil).write(to: url)
            return url
        }

        let results = await BatchConverter.run(job(inputs, out: out) {
            $0.changeFormat = false
            $0.resize.isOn = true
            $0.resize.side = 10
        })

        #expect(results.map(\.status) == [.converted, .converted])
        #expect(results.map { $0.output?.lastPathComponent } == ["a.jxl", "b.jxl"])
        for result in results {
            let output = try #require(result.output)
            #expect(CGImageSourceCreateWithURL(output as CFURL, nil).flatMap(CGImageSourceGetType) as String? == "public.jpeg-xl")
        }
    }

    @Test func convertsToJXL() async throws {
        _ = Fixtures.jxl
        let dir = try Fixtures.makeTempDir(), out = try Fixtures.makeTempDir()
        let jpeg = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 40, height: 20)
        let context = try #require(CGContext(data: nil, width: 20, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0, green: 0.5, blue: 1, alpha: 0.5))
        context.fill(CGRect(x: 0, y: 0, width: 10, height: 20))
        let png = dir.appendingPathComponent("b.png")
        let dest = try #require(CGImageDestinationCreateWithURL(png as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(dest, try #require(context.makeImage()), nil)
        #expect(CGImageDestinationFinalize(dest))

        let results = await BatchConverter.run(job([jpeg, png], out: out, format: "jxl") { $0.changeFormat = true })

        #expect(results.map(\.status) == [.converted, .converted])
        #expect(results.map { $0.output?.lastPathComponent } == ["a.jxl", "b.jxl"])
    }

    @Test func canStartWithEmptyFolder() {
        var s = BatchSettings()
        s.outputFolder = ""
        #expect(BatchProgress.canStart(isRunning: false, scans: 0, inputCount: 1, settings: s))
        s.changeFormat = false
        #expect(BatchProgress.canStart(isRunning: false, scans: 0, inputCount: 1, settings: s))
        s.outputFolder = "relative"
        #expect(!BatchProgress.canStart(isRunning: false, scans: 0, inputCount: 1, settings: s))
    }

    // MARK: Pages

    @Test func multiPageNotesPageOneOfN() async throws {
        let dir = try Fixtures.makeTempDir()
        let tiff = try Fixtures.writeMultiPageTIFF(to: dir.appendingPathComponent("scan.tiff"), pages: 3)
        let result = try #require(await BatchConverter.run(job([tiff], out: dir, format: "jpg")).first)
        #expect(result.status == .converted)
        #expect(result.message == "page 1 of 3")
        #expect(result.logLine == "scan.tiff → scan.jpg · page 1 of 3")
    }

    @Test func keepAllPagesTIFFHasNoNote() async throws {
        let dir = try Fixtures.makeTempDir(), out = try Fixtures.makeTempDir()
        let tiff = try Fixtures.writeMultiPageTIFF(to: dir.appendingPathComponent("scan.tiff"), pages: 3)
        let result = try #require(await BatchConverter.run(job([tiff], out: out, format: "tiff")).first)
        #expect(result.status == .converted)
        #expect(result.message == nil)
        #expect(ImageDecoder.pageCount(of: try #require(result.output)) == 3)
    }

    // MARK: Safety

    @Test func replaceExistingTrashesOldFile() async throws {
        let dir = try Fixtures.makeTempDir(), out = try Fixtures.makeTempDir()
        let input = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 8, height: 8)
        let old = out.appendingPathComponent("a.png")
        try Data("old".utf8).write(to: old)
        let trash = try FakeTrash()

        let results = await BatchConverter.run(job([input], out: out) { $0.safety.replaceExisting = true }, trash: trash.trash)

        #expect(results.first?.output?.lastPathComponent == "a.png")
        #expect(trash.names == ["a.png"])
        #expect(ImageDecoder.displaySize(of: old) == CGSize(width: 8, height: 8))
    }

    @Test func replaceExistingNeverTouchesInputs() async throws {
        let dir = try Fixtures.makeTempDir()
        let jpg = try Fixtures.writeImage(to: dir.appendingPathComponent("x.jpg"), width: 8, height: 8)
        let png = try Fixtures.writeImage(to: dir.appendingPathComponent("x.png"), width: 4, height: 4, type: .png)
        let before = try Data(contentsOf: png)
        let trash = try FakeTrash()

        let results = await BatchConverter.run(job([jpg, png], out: dir) { $0.safety.replaceExisting = true }, trash: trash.trash)

        #expect(results.map(\.status) == [.converted, .converted])
        #expect(!results.contains { $0.output == png })
        #expect(trash.trashed.isEmpty)
        #expect(try Data(contentsOf: png) == before)
    }

    @Test func fileAppearingDuringRunIsKept() async throws {
        let out = try Fixtures.makeTempDir()
        let appeared = out.appendingPathComponent("a.png")
        let results = await BatchConverter.run(job([URL(fileURLWithPath: "/in/a.jpg")], out: out), prepare: { _, _ in
            try? Data("precious".utf8).write(to: appeared)
            return BatchConverter.Prepared(data: Data("new".utf8))
        })
        #expect(try Data(contentsOf: appeared) == Data("precious".utf8))
        #expect(results.first?.output?.lastPathComponent == "a 2.png")
    }

    @Test func trashOriginalsOnlyAfterWrite() async throws {
        let dir = try Fixtures.makeTempDir()
        let input = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 8, height: 8)
        let blocker = dir.appendingPathComponent("file")
        try Data().write(to: blocker)  // the output folder can't be created inside a file
        let trash = try FakeTrash()

        let results = await BatchConverter.run(job([input], out: blocker.appendingPathComponent("out")) {
            $0.safety.trashOriginals = true
        }, trash: trash.trash)

        #expect(results.first?.status == .failed)
        #expect(results.first?.message == "Can't save a.jpg")
        #expect(trash.trashed.isEmpty)
        #expect(FileManager.default.fileExists(atPath: input.path))
    }

    @Test func trashOriginalsTakesSidecars() async throws {
        let dir = try Fixtures.makeTempDir(), out = try Fixtures.makeTempDir()
        let input = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 8, height: 8)
        try Data("<xmp/>".utf8).write(to: dir.appendingPathComponent("a.xmp"))
        let trash = try FakeTrash()

        let results = await BatchConverter.run(job([input], out: out) { $0.safety.trashOriginals = true }, trash: trash.trash)

        #expect(results.first?.status == .converted)
        #expect(Set(trash.names) == ["a.jpg", "a.xmp"])
        #expect(trash.names.first == "a.jpg")
    }

    @Test func commitTrashesTheSidecarsFoundBeforeIt() throws {
        // The serial commit never lists the input's folder; the parallel prepare stage did.
        let dir = try Fixtures.makeTempDir(), out = try Fixtures.makeTempDir()
        let input = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 8, height: 8)
        let found = dir.appendingPathComponent("a.aae"), unlisted = dir.appendingPathComponent("a.xmp")
        try Data().write(to: found)
        try Data().write(to: unlisted)
        var settings = BatchSettings()
        settings.formatID = "png"
        settings.outputFolder = out.path
        settings.safety.trashOriginals = true
        let batchInput = BatchInput(url: input, root: nil)
        var namer = BatchNamer(settings: settings, inputs: [batchInput])
        let trash = try FakeTrash()

        let result = BatchConverter.commit(BatchConverter.Prepared(data: Data("x".utf8), sidecars: [found]),
                                           input: batchInput, settings: settings, namer: &namer, trash: trash.trash)

        #expect(result.status == .converted)
        #expect(trash.names == ["a.jpg", "a.aae"])
    }

    @Test func trashOriginalsLeavesSidecarsWithAnOutputOfTheSameName() async throws {
        // Converting in place: a.jpg now owns a.xmp.
        let dir = try Fixtures.makeTempDir()
        let input = try Fixtures.writeImage(to: dir.appendingPathComponent("a.png"), width: 8, height: 8, type: .png)
        let sidecar = dir.appendingPathComponent("a.xmp")
        try Data("<xmp/>".utf8).write(to: sidecar)
        let trash = try FakeTrash()

        let results = await BatchConverter.run(job([input], out: dir, format: "jpg") { $0.safety.trashOriginals = true },
                                               trash: trash.trash)

        #expect(results.first?.output?.lastPathComponent == "a.jpg")
        #expect(trash.names == ["a.png"])
        #expect(FileManager.default.fileExists(atPath: sidecar.path))
    }

    @Test func trashOriginalsLeavesSidecarsAnEarlierOutputTookOver() async throws {
        // a.png converts in place to a.heic and keeps a.xmp; a.jpg's output "a 2.heic" must not take it away.
        let dir = try Fixtures.makeTempDir()
        let png = try Fixtures.writeImage(to: dir.appendingPathComponent("a.png"), width: 8, height: 8, type: .png)
        let jpg = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 8, height: 8)
        let sidecar = dir.appendingPathComponent("a.xmp")
        try Data("<xmp/>".utf8).write(to: sidecar)
        let trash = try FakeTrash()

        _ = await BatchConverter.run(job([png, jpg], out: dir, format: "heic") { $0.safety.trashOriginals = true },
                                     trash: trash.trash)

        #expect(Set(trash.names) == ["a.png", "a.jpg"])
        #expect(FileManager.default.fileExists(atPath: sidecar.path))
    }

    @Test func trashOriginalsLeavesSidecarsAnotherImageOfTheSameNameStillHas() async throws {
        // A RAW+JPEG pair: converting only the JPEG leaves a.xmp with the RAW.
        let dir = try Fixtures.makeTempDir(), out = try Fixtures.makeTempDir()
        let jpg = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 8, height: 8)
        try Data("raw".utf8).write(to: dir.appendingPathComponent("a.dng"))
        let sidecar = dir.appendingPathComponent("a.xmp")
        try Data("<xmp/>".utf8).write(to: sidecar)
        let trash = try FakeTrash()

        _ = await BatchConverter.run(job([jpg], out: out) { $0.safety.trashOriginals = true }, trash: trash.trash)

        #expect(trash.names == ["a.jpg"])
        #expect(FileManager.default.fileExists(atPath: sidecar.path))
    }

    @Test func trashOriginalsNotesAnOriginalItCouldNotTrash() async throws {
        let dir = try Fixtures.makeTempDir(), out = try Fixtures.makeTempDir()
        let input = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 8, height: 8)

        let results = await BatchConverter.run(job([input], out: out) { $0.safety.trashOriginals = true },
                                               trash: { _ in throw CocoaError(.fileWriteNoPermission) })

        #expect(results.first?.status == .converted)
        #expect(results.first?.message == "Can't move a.jpg to the Trash")
    }

    @Test func keepDatesCopiesModificationDate() async throws {
        let dir = try Fixtures.makeTempDir(), out = try Fixtures.makeTempDir()
        let input = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 8, height: 8)
        let date = Date(timeIntervalSince1970: 1_000_000_000)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: input.path)

        let output = try #require(await BatchConverter.run(job([input], out: out) { $0.safety.keepDates = true }).first?.output)

        let written = try FileManager.default.attributesOfItem(atPath: output.path)[.modificationDate] as? Date
        #expect(written == date)
    }

    @Test func keepDatesFollowsASymlinkedInput() async throws {
        let dir = try Fixtures.makeTempDir(), out = try Fixtures.makeTempDir()
        let real = try Fixtures.writeImage(to: dir.appendingPathComponent("real.jpg"), width: 8, height: 8)
        let date = Date(timeIntervalSince1970: 1_000_000_000)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: real.path)
        let link = dir.appendingPathComponent("link.jpg")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        let output = try #require(await BatchConverter.run(job([link], out: out) { $0.safety.keepDates = true }).first?.output)

        let written = try FileManager.default.attributesOfItem(atPath: output.path)[.modificationDate] as? Date
        #expect(written == date)
    }

    @Test func replaceExistingNeverTrashesAFolder() async throws {
        let out = try Fixtures.makeTempDir()
        let folder = out.appendingPathComponent("a.png", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("notes".utf8).write(to: folder.appendingPathComponent("notes.txt"))
        let trash = try FakeTrash()

        let results = await BatchConverter.run(job([URL(fileURLWithPath: "/in/a.jpg")], out: out) {
            $0.safety.replaceExisting = true
        }, trash: trash.trash, prepare: { _, _ in BatchConverter.Prepared(data: Data("new".utf8)) })

        #expect(trash.trashed.isEmpty)
        #expect(results.first?.output?.lastPathComponent == "a 2.png")
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("notes.txt").path))
    }

    @Test func trashOriginalsLeavesSidecarsWhenThePreferenceIsOff() async throws {
        let dir = try Fixtures.makeTempDir(), out = try Fixtures.makeTempDir()
        let input = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 8, height: 8)
        try Data("<xmp/>".utf8).write(to: dir.appendingPathComponent("a.xmp"))
        let trash = try FakeTrash()

        let results = await BatchConverter.run(job([input], out: out) { $0.safety.trashOriginals = true },
                                               trash: trash.trash, moveSidecars: false)

        #expect(results.first?.status == .converted)
        #expect(trash.names == ["a.jpg"])
    }

    @Test func counterSkipsFilesThatFailToSave() async throws {
        let root = try Fixtures.makeTempDir(), out = try Fixtures.makeTempDir()
        try Data().write(to: out.appendingPathComponent("sub"))  // input 2's subfolder can't be created
        let inputs = ["a.jpg", "sub/b.jpg", "c.jpg"].map { root.appendingPathComponent($0) }

        let results = await BatchConverter.run(job(inputs, out: out, root: root) {
            $0.renamePattern = "Holiday {n:3}"
            $0.safety.recreateSubfolders = true
        }, prepare: { _, _ in BatchConverter.Prepared(data: Data("x".utf8)) })

        #expect(results.map(\.status) == [.converted, .failed, .converted])
        #expect(results.map { $0.output?.lastPathComponent } == ["Holiday 001.png", nil, "Holiday 002.png"])
    }

    @Test func commitsOffTheCooperativeThreadPool() async throws {
        let dir = try Fixtures.makeTempDir(), out = try Fixtures.makeTempDir()
        let input = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 8, height: 8)
        let labels = Box([String]())
        let trash = try FakeTrash()

        _ = await BatchConverter.run(job([input], out: out) { $0.safety.trashOriginals = true }, trash: {
            labels.update { $0.append(String(cString: __dispatch_queue_get_label(nil))) }
            try trash.trash($0)
        })

        // Commits write and copy whole files; on the pool they would starve the viewer's decode tasks.
        #expect(labels.get.count == 1)
        #expect(!labels.get.contains { $0.contains("cooperative") })
    }

    @Test func recreateSubfolders() async throws {
        let root = try Fixtures.makeTempDir(), out = try Fixtures.makeTempDir()
        let sub = root.appendingPathComponent("2024/May", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let input = try Fixtures.writeImage(to: sub.appendingPathComponent("a.jpg"), width: 8, height: 8)

        let output = try #require(await BatchConverter.run(job([input], out: out, root: root) {
            $0.safety.recreateSubfolders = true
        }).first?.output)

        #expect(output.standardizedFileURL.path == out.appendingPathComponent("2024/May/a.png").standardizedFileURL.path)
        #expect(FileManager.default.fileExists(atPath: output.path))
    }

    // MARK: Stop, pause, memory

    @Test func stopFinishesInFlightAndStartsNoMore() async throws {
        let out = try Fixtures.makeTempDir()
        let control = BatchControl()
        let secondStarted = DispatchSemaphore(value: 0)
        let inputs = (1...10).map { URL(fileURLWithPath: "/in/\($0).jpg") }

        let results = await BatchConverter.run(job(inputs, out: out), control: control, workers: 2, prepare: { index, _ in
            if index == 0 { secondStarted.wait(); control.stop() }
            if index == 1 { secondStarted.signal(); Thread.sleep(forTimeInterval: 0.05) }
            return BatchConverter.Prepared(data: Data("\(index)".utf8))
        })

        #expect(results.count == 10)
        #expect(results.map(\.status) == [.converted, .converted] + Array(repeating: .notStarted, count: 8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: out.path).count == 2)
        #expect(BatchLog.text(results).hasSuffix("2 converted, 0 failed, 8 not converted"))
    }

    /// Time left leaves out time spent paused.
    @Test func pausedDurationAddsUpPauses() async throws {
        let control = BatchControl()
        #expect(control.pausedDuration() == .zero)
        control.pause()
        try await Task.sleep(for: .milliseconds(60))
        #expect(control.pausedDuration() >= .milliseconds(60))  // counts while still paused
        control.resume()
        let afterOne = control.pausedDuration()
        try await Task.sleep(for: .milliseconds(60))
        #expect(control.pausedDuration() == afterOne)  // not while running
        control.pause()
        control.pause()  // a second pause doesn't restart the clock
        try await Task.sleep(for: .milliseconds(30))
        control.stop()
        #expect(control.pausedDuration() >= afterOne + .milliseconds(30))
    }

    @Test func pauseHoldsThenResumes() async throws {
        let out = try Fixtures.makeTempDir()
        let control = BatchControl()
        let started = Box(0), committed = Box(0)
        let inputs = (1...4).map { URL(fileURLWithPath: "/in/\($0).jpg") }

        let run = Task {
            await BatchConverter.run(job(inputs, out: out), control: control, workers: 1,
                                     onResult: { _ in committed.update { $0 += 1 } }, prepare: { index, _ in
                started.update { $0 += 1 }
                if index == 0 { control.pause() }
                return BatchConverter.Prepared(data: Data("\(index)".utf8))
            })
        }
        while committed.get < 1 { try await Task.sleep(for: .milliseconds(10)) }
        try await Task.sleep(for: .milliseconds(200))
        #expect(control.isPaused)
        #expect(started.get == 1)  // the in-flight file finished and was written, nothing new started
        #expect(committed.get == 1)

        control.resume()
        let results = await run.value

        #expect(results.map(\.status) == Array(repeating: .converted, count: 4))
        #expect(started.get == 4)
    }

    @Test func commitWindowIsBounded() async throws {
        let out = try Fixtures.makeTempDir()
        let started = Box(0), committed = Box(0), most = Box(0)
        let inputs = (1...30).map { URL(fileURLWithPath: "/in/\($0).jpg") }

        _ = await BatchConverter.run(job(inputs, out: out), workers: 2, onResult: { _ in committed.update { $0 += 1 } },
                                     prepare: { index, _ in
            started.update { $0 += 1 }
            let ahead = started.get - committed.get
            most.update { $0 = max($0, ahead) }
            if index == 0 { Thread.sleep(forTimeInterval: 0.3) }  // everything after it waits for its commit
            return BatchConverter.Prepared(data: Data("\(index)".utf8))
        })

        #expect(most.get <= 2 * 2)
        #expect(committed.get == 30)
    }

    // MARK: Watermark, DPI, log

    @Test func watermarkMissingFailsEveryFileOnce() async throws {
        let dir = try Fixtures.makeTempDir(), out = try Fixtures.makeTempDir()
        let a = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 8, height: 8)
        let b = try Fixtures.writeImage(to: dir.appendingPathComponent("b.jpg"), width: 8, height: 8)
        let results = await BatchConverter.run(job([a, b], out: out) {
            $0.watermark.isOn = true
            $0.watermark.path = dir.appendingPathComponent("nope.png").path
        })
        #expect(results.map(\.status) == [.failed, .failed])
        #expect(results.map(\.message) == Array(repeating: "Can't read the watermark image nope.png", count: 2))
        #expect(try FileManager.default.contentsOfDirectory(atPath: out.path).isEmpty)
    }

    @Test(arguments: ["jpg", "png", "tiff"]) func dpiIsWritten(format: String) async throws {
        let dir = try Fixtures.makeTempDir()
        let input = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 8, height: 8)
        let output = try #require(await BatchConverter.run(job([input], out: dir, format: format) {
            $0.resize.isOn = true
            $0.resize.dpi = 300
        }).first?.output)
        let source = try #require(CGImageSourceCreateWithURL(output as CFURL, nil))
        let props = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect((props[kCGImagePropertyDPIWidth] as? Double)?.rounded() == 300)
        #expect((props[kCGImagePropertyDPIHeight] as? Double)?.rounded() == 300)
    }

    @Test func logTextSummary() {
        let results = [
            BatchResult(input: URL(fileURLWithPath: "/in/a.jpg"), output: URL(fileURLWithPath: "/out/a.png"),
                        status: .converted, message: nil),
            BatchResult(input: URL(fileURLWithPath: "/in/b.jpg"), output: nil, status: .failed, message: "Can't open b.jpg"),
        ]
        #expect(BatchLog.text(results) == "a.jpg → a.png\nCan't open b.jpg\n1 converted, 1 failed")
    }

    // MARK: Frames, pages, tiles and the date taken

    func names(_ folder: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
    }

    /// Red of the top-leading pixel.
    func red(_ url: URL) throws -> Int {
        Int(try #require(RGBAImage(ImageDecoder.decode(url)))[0, 0].r)
    }

    /// A PNG whose top-leading quarter is red and the rest blue.
    func writeQuarterRed(to url: URL, width: Int, height: Int) throws -> URL {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: height / 2, width: width / 2, height: height / 2))  // y counts from the bottom
        let png = try #require(FormatRegistry.format(id: "png"))
        try ImageEncoder.encode([context.makeImage()!], as: png, options: FormatOptions()).write(to: url)
        return url
    }

    func exifDate(_ url: URL) -> String? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return DateTaken.exifValue(source, kCGImagePropertyExifDateTimeOriginal)
    }

    @Test func framesOfGIF() async throws {
        let dir = try Fixtures.makeTempDir(), out = try Fixtures.makeTempDir()
        let gif = try Fixtures.writeAnimatedGIF(to: dir.appendingPathComponent("a.gif"), delays: [0.1, 0.1, 0.1], width: 8, height: 6)

        let result = try #require(await BatchConverter.run(job([gif], out: out) { $0.frames.isOn = true }).first)

        #expect(result.status == .converted)
        #expect(result.outputs.map(\.lastPathComponent) == ["a-1.png", "a-2.png", "a-3.png"])
        #expect(try names(out) == ["a-1.png", "a-2.png", "a-3.png"])
        #expect(result.outputs.allSatisfy { ImageDecoder.displaySize(of: $0) == CGSize(width: 8, height: 6) })
        // Frame n is red 40·n (through the GIF palette and colour management): each its own frame, in order.
        let reds = try result.outputs.map(red)
        #expect(reds[0] < 10 && reds[0] + 20 < reds[1] && reds[1] + 20 < reds[2])
    }

    @Test func pagesOfTIFFToJPEG() async throws {
        let dir = try Fixtures.makeTempDir(), out = try Fixtures.makeTempDir()
        let tiff = try Fixtures.writeMultiPageTIFF(to: dir.appendingPathComponent("scan.tiff"), pages: 3)

        let result = try #require(await BatchConverter.run(job([tiff], out: out, format: "jpg") { $0.frames.isOn = true }).first)

        #expect(result.status == .converted)
        #expect(result.message == nil)
        #expect(result.outputs.map(\.lastPathComponent) == ["scan-1.jpg", "scan-2.jpg", "scan-3.jpg"])
        #expect(result.outputs.map { ImageDecoder.displaySize(of: $0)?.width } == [8, 9, 10])
    }

    @Test func pdfOutputGetsOnePagePerFile() async throws {
        let dir = try Fixtures.makeTempDir(), out = try Fixtures.makeTempDir()
        let tiff = try Fixtures.writeMultiPageTIFF(to: dir.appendingPathComponent("scan.tiff"), pages: 3)

        let result = try #require(await BatchConverter.run(job([tiff], out: out, format: "pdf") { $0.frames.isOn = true }).first)

        #expect(result.outputs.count == 3)
        #expect(result.outputs.map { ImageDecoder.pageCount(of: $0) } == [1, 1, 1])
    }

    @Test func stillWithFramesStepIsOneOutput() async throws {
        let dir = try Fixtures.makeTempDir(), out = try Fixtures.makeTempDir()
        let still = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 8, height: 8)

        let result = try #require(await BatchConverter.run(job([still], out: out, format: "jpg") { $0.frames.isOn = true }).first)

        #expect(result.outputs.map(\.lastPathComponent) == ["a.jpg"])
        #expect(try names(out) == ["a.jpg"])
    }

    @Test func stillWithFramesStepKeepingFormatIsCopied() async throws {
        let dir = try Fixtures.makeTempDir(), out = try Fixtures.makeTempDir()
        let still = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 8, height: 8)

        let output = try #require(await BatchConverter.run(job([still], out: out) {
            $0.changeFormat = false
            $0.frames.isOn = true
        }).first?.output)

        #expect(try Data(contentsOf: output) == Data(contentsOf: still))
    }

    @Test func stillWithFramesStepSetsDateLosslessly() async throws {
        let dir = try Fixtures.makeTempDir(), out = try Fixtures.makeTempDir()
        let still = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 8, height: 8)

        let output = try #require(await BatchConverter.run(job([still], out: out) {
            $0.changeFormat = false
            $0.frames.isOn = true
            $0.dateTaken.isOn = true
            $0.dateTaken.mode = .set
            $0.dateTaken.setTo = "2020:02:03 04:05:06"
        }).first?.output)

        #expect(try Data(contentsOf: output) == DateTaken.rewritten(still, date: "2020:02:03 04:05:06"))
    }

    @Test func tilesOfStill() async throws {
        let dir = try Fixtures.makeTempDir(), out = try Fixtures.makeTempDir()
        let input = try writeQuarterRed(to: dir.appendingPathComponent("a.png"), width: 1600, height: 900)

        let result = try #require(await BatchConverter.run(job([input], out: out) { $0.tiles.isOn = true }).first)

        #expect(result.outputs.map(\.lastPathComponent) == ["a-1-1.png", "a-1-2.png", "a-2-1.png", "a-2-2.png"])
        #expect(result.outputs.allSatisfy { ImageDecoder.displaySize(of: $0) == CGSize(width: 800, height: 450) })
        let reds = try result.outputs.map(red)
        #expect(reds[0] > 240 && reds.dropFirst().allSatisfy { $0 < 16 })
    }

    @Test func tilesOfMultiPageKeepNote() async throws {
        let dir = try Fixtures.makeTempDir(), out = try Fixtures.makeTempDir()
        let tiff = try Fixtures.writeMultiPageTIFF(to: dir.appendingPathComponent("scan.tiff"), pages: 3)

        let result = try #require(await BatchConverter.run(job([tiff], out: out, format: "jpg") {
            $0.tiles.isOn = true
            $0.tiles.columns = 2
            $0.tiles.rows = 1
        }).first)

        #expect(result.outputs.map(\.lastPathComponent) == ["scan-1-1.jpg", "scan-1-2.jpg"])
        #expect(result.message == "page 1 of 3")
        #expect(result.outputs.allSatisfy { ImageDecoder.displaySize(of: $0) == CGSize(width: 4, height: 4) })
    }

    @Test func framesAndTiles() async throws {
        let dir = try Fixtures.makeTempDir(), out = try Fixtures.makeTempDir()
        let gif = try Fixtures.writeAnimatedGIF(to: dir.appendingPathComponent("a.gif"), delays: [0.1, 0.1], width: 8, height: 6)

        let result = try #require(await BatchConverter.run(job([gif], out: out) {
            $0.frames.isOn = true
            $0.tiles.isOn = true
            $0.tiles.columns = 2
            $0.tiles.rows = 1
        }).first)

        #expect(result.outputs.map(\.lastPathComponent) == ["a-1-1-1.png", "a-1-1-2.png", "a-2-1-1.png", "a-2-1-2.png"])
        let reds = try result.outputs.map(red)
        #expect(reds[0] == reds[1] && reds[2] == reds[3] && reds[0] + 20 < reds[2])  // frame-major
    }

    @Test func counterSharedByParts() async throws {
        let dir = try Fixtures.makeTempDir(), out = try Fixtures.makeTempDir()
        let gif = try Fixtures.writeAnimatedGIF(to: dir.appendingPathComponent("a.gif"), delays: [0.1, 0.1])
        let still = try Fixtures.writeImage(to: dir.appendingPathComponent("b.jpg"), width: 8, height: 8)

        let results = await BatchConverter.run(job([gif, still], out: out) {
            $0.frames.isOn = true
            $0.renamePattern = "img-{n}"
        })

        #expect(results.flatMap(\.outputs).map(\.lastPathComponent) == ["img-1-1.png", "img-1-2.png", "img-2.png"])
    }

    /// A toy own format: 4 frames listed, frame 3 (index 2) unreadable. A truncated GIF can't stand in:
    /// ImageIO lists only its complete frames.
    static let brokenAnimation = OwnFormat(
        name: "TOYBROKEN", extensions: ["fvbroken"],
        size: { _, _ in CGSize(width: 4, height: 2) },
        pageCount: { _ in 1 },
        decode: { _, index, _ in
            guard index < 2 else { throw OwnDecodeError.corrupt }
            return RGBAImage(width: 4, height: 2).makeCGImage()!
        },
        delays: { _ in [0.04, 0.04, 0.04, 0.04] })

    @Test func failedPartLeavesNothing() async throws {
        OwnDecoders.register(Self.brokenAnimation)
        let dir = try Fixtures.makeTempDir(), out = try Fixtures.makeTempDir()
        let cut = dir.appendingPathComponent("cut.fvbroken")
        try Data([0]).write(to: cut)
        let still = try Fixtures.writeImage(to: dir.appendingPathComponent("b.jpg"), width: 8, height: 8)

        let results = await BatchConverter.run(job([cut, still], out: out) {
            $0.frames.isOn = true
            $0.renamePattern = "{n}"
        })

        #expect(results.map(\.status) == [.failed, .converted])
        #expect(results[0].outputs.isEmpty)
        #expect(try names(out) == ["1.png"])
    }

    @Test func commitFailureRemovesMovedParts() throws {
        let out = try Fixtures.makeTempDir()
        let parts = try (1...3).map { n -> (file: URL, label: String) in
            let temp = out.appendingPathComponent(".featherview-\(UUID().uuidString).tmp")
            try Data("\(n)".utf8).write(to: temp)
            return (temp, "\(n)")
        }
        var settings = BatchSettings()
        settings.outputFolder = out.path
        settings.formatID = "png"
        let input = BatchInput(url: URL(fileURLWithPath: "/in/a.gif"), root: nil)
        var namer = BatchNamer(settings: settings, inputs: [input])
        var calls = 0

        let result = BatchConverter.commit(BatchConverter.Prepared(parts: parts), input: input, settings: settings,
                                           namer: &namer, trash: { _ in }, move: { from, to in
            calls += 1
            return calls == 2 ? EIO : BatchConverter.moveExclusive(from, to)
        })

        #expect(result.status == .failed)
        #expect(result.outputs.isEmpty)
        #expect(try names(out).isEmpty)  // the first part removed again, no temp left
        #expect(namer.next(for: input, date: nil).lastPathComponent == "a.png")  // the name wasn't spent
    }

    @Test func secondRunNeverOverwritesParts() async throws {
        let dir = try Fixtures.makeTempDir(), out = try Fixtures.makeTempDir()
        let gif = try Fixtures.writeAnimatedGIF(to: dir.appendingPathComponent("a.gif"), delays: [0.1, 0.1])
        let job = job([gif], out: out) { $0.frames.isOn = true }
        _ = await BatchConverter.run(job)
        let first = try Data(contentsOf: out.appendingPathComponent("a-1.png"))

        let second = try #require(await BatchConverter.run(job).first)

        #expect(second.outputs.map(\.lastPathComponent) == ["a-1 2.png", "a-2 2.png"])
        #expect(try Data(contentsOf: out.appendingPathComponent("a-1.png")) == first)
        #expect(try names(out) == ["a-1 2.png", "a-1.png", "a-2 2.png", "a-2.png"])
    }

    @Test func partsAreOnDiskBeforeCommit() throws {
        let dir = try Fixtures.makeTempDir(), out = try Fixtures.makeTempDir()
        let gif = try Fixtures.writeAnimatedGIF(to: dir.appendingPathComponent("a.gif"), delays: [0.1, 0.1, 0.1])
        let job = job([gif], out: out) { $0.frames.isOn = true }

        let prepared = BatchConverter.prepare(job.inputs[0], index: 0, settings: job.settings, watermark: .success(nil))

        #expect(prepared.error == nil)
        #expect(prepared.data == nil)
        #expect(prepared.parts.map(\.label) == ["1", "2", "3"])
        #expect(prepared.parts.allSatisfy { FileManager.default.fileExists(atPath: $0.file.path) })
        #expect(prepared.parts.allSatisfy { $0.file.deletingLastPathComponent().standardizedFileURL == out.standardizedFileURL })
        #expect(prepared.parts.allSatisfy { $0.file.lastPathComponent.hasPrefix(".featherview-") })
    }

    @Test func keepFormatSplitsPDF() async throws {
        let dir = try Fixtures.makeTempDir(), out = try Fixtures.makeTempDir()
        let pdf = try Fixtures.writePDF(to: dir.appendingPathComponent("a.pdf"), pages: Array(repeating: CGSize(width: 20, height: 10), count: 2))

        let result = try #require(await BatchConverter.run(job([pdf], out: out) {
            $0.changeFormat = false
            $0.frames.isOn = true
        }).first)

        #expect(result.status == .converted)
        #expect(result.outputs.map(\.lastPathComponent) == ["a-1.pdf", "a-2.pdf"])
        #expect(result.outputs.map { ImageDecoder.pageCount(of: $0) } == [1, 1])
    }

    @Test func dateSetOnReencode() async throws {
        let dir = try Fixtures.makeTempDir(), out = try Fixtures.makeTempDir()
        let input = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 8, height: 8, properties: [
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2024:05:01 12:00:00"]])
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000_000_000)], ofItemAtPath: input.path)

        let output = try #require(await BatchConverter.run(job([input], out: out) {
            $0.safety.keepDates = true
            $0.dateTaken.isOn = true
            $0.dateTaken.mode = .set
            $0.dateTaken.setTo = "2020:02:03 04:05:06"
        }).first?.output)

        #expect(output.pathExtension == "png")
        #expect(exifDate(output) == "2020:02:03 04:05:06")
        let modified = try FileManager.default.attributesOfItem(atPath: output.path)[.modificationDate] as? Date
        #expect(modified == DateTaken.instant("2020:02:03 04:05:06", offset: nil))
    }

    @Test(arguments: [true, false]) func dateSetInJXL(keepMetadata: Bool) async throws {
        _ = Fixtures.jxl
        let dir = try Fixtures.makeTempDir(), out = try Fixtures.makeTempDir()
        let input = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 8, height: 8, properties: [
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:05:01 12:00:00",
                                             kCGImagePropertyExifDateTimeDigitized: "2026:05:01 12:00:00"],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFDateTime: "2026:05:01 12:00:00"]])

        let result = try #require(await BatchConverter.run(job([input], out: out, format: "jxl") {
            $0.options.keepMetadata = keepMetadata
            $0.dateTaken.isOn = true
            $0.dateTaken.mode = .set
            $0.dateTaken.setTo = "2020:02:03 04:05:06"
        }).first)

        #expect(result.status == .converted)
        let output = try #require(result.output)
        let source = try #require(CGImageSourceCreateWithURL(output as CFURL, nil))
        let p = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let exif = p[kCGImagePropertyExifDictionary] as? [CFString: Any]
        #expect(exif?[kCGImagePropertyExifDateTimeOriginal] as? String == "2020:02:03 04:05:06")
        #expect(exif?[kCGImagePropertyExifDateTimeDigitized] as? String == "2020:02:03 04:05:06")
        #expect((p[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFDateTime] as? String
                == "2020:02:03 04:05:06")
    }

    @Test func dateShiftLosslessCopy() async throws {
        let dir = try Fixtures.makeTempDir(), out = try Fixtures.makeTempDir()
        let input = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 16, height: 8, properties: [
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2024:05:01 12:00:00"]])
        let before = try Data(contentsOf: input)

        let output = try #require(await BatchConverter.run(job([input], out: out) {
            $0.changeFormat = false
            $0.dateTaken.isOn = true
            $0.dateTaken.shiftSeconds = 3600
        }).first?.output)

        #expect(output.lastPathComponent == "a.jpg")
        #expect(exifDate(output) == "2024:05:01 13:00:00")
        #expect(RGBAImage(try ImageDecoder.decode(output)) == RGBAImage(try ImageDecoder.decode(input)))
        #expect(try Data(contentsOf: input) == before)
    }

    @Test func dateOnGIFCopyFails() async throws {
        let dir = try Fixtures.makeTempDir(), out = try Fixtures.makeTempDir()
        let gif = try Fixtures.writeImage(to: dir.appendingPathComponent("a.gif"), width: 8, height: 8, type: .gif)
        let jpeg = try Fixtures.writeImage(to: dir.appendingPathComponent("b.jpg"), width: 8, height: 8)

        let results = await BatchConverter.run(job([gif, jpeg], out: out) {
            $0.changeFormat = false
            $0.dateTaken.isOn = true
            $0.dateTaken.mode = .set
            $0.dateTaken.setTo = "2020:02:03 04:05:06"
        })

        #expect(results.map(\.status) == [.failed, .converted])
        #expect(results[0].message == "Can't change the date taken of a.gif")
        #expect(try names(out) == ["b.jpg"])
    }

    @Test func dateSetWithoutADateFails() async throws {
        let dir = try Fixtures.makeTempDir(), out = try Fixtures.makeTempDir()
        let input = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 8, height: 8)
        let result = try #require(await BatchConverter.run(job([input], out: out) {
            $0.dateTaken.isOn = true
            $0.dateTaken.mode = .set
        }).first)
        #expect(result.message == "Choose a date for the Date Taken step")
    }

    @Test func dateSetToAnUnreadableDateFails() async throws {
        let dir = try Fixtures.makeTempDir(), out = try Fixtures.makeTempDir()
        let input = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 8, height: 8)
        let result = try #require(await BatchConverter.run(job([input], out: out, format: "jpg") {
            $0.dateTaken.isOn = true
            $0.dateTaken.mode = .set
            $0.dateTaken.setTo = "not a date"
        }).first)
        #expect(result.status == .failed)
        #expect(result.message == "Choose a date for the Date Taken step")
        #expect(try names(out).isEmpty)
    }

    @Test func dateShiftOutOfRangeFails() async throws {
        let dir = try Fixtures.makeTempDir(), out = try Fixtures.makeTempDir()
        let input = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 8, height: 8, properties: [
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2024:05:01 12:00:00"]])
        let result = try #require(await BatchConverter.run(job([input], out: out, format: "jpg") {
            $0.dateTaken.isOn = true
            $0.dateTaken.shiftSeconds = .max
        }).first)
        #expect(result.status == .failed)
        #expect(result.message == "Can't change the date taken of a.jpg")
        #expect(try names(out).isEmpty)
    }

    @Test func dateRenamesByNewDate() async throws {
        let dir = try Fixtures.makeTempDir(), out = try Fixtures.makeTempDir()
        let input = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 8, height: 8)

        let output = try #require(await BatchConverter.run(job([input], out: out, format: "jpg") {
            $0.renamePattern = "{date}"
            $0.dateTaken.isOn = true
            $0.dateTaken.mode = .set
            $0.dateTaken.setTo = "2020:02:03 04:05:06"
        }).first?.output)

        #expect(output.lastPathComponent == "2020-02-03.jpg")
    }
}

// Moved from the old BatchPlannerTests: RenamePattern stays.
@Suite struct RenamePatternTests {
    @Test func tokens() {
        #expect(RenamePattern("{name}_{n:3}").baseName(original: "IMG", index: 7) == "IMG_007")
        #expect(RenamePattern("x{n}").baseName(original: "a", index: 12) == "x12")
        #expect(RenamePattern("{n:2}").baseName(original: "a", index: 123) == "123")
    }

    @Test func padWidthIsCapped() {
        // A typo like {n:200000000} must not build a huge string for every file.
        #expect(RenamePattern("{n:20}").baseName(original: "a", index: 1) == "0000000001")
        #expect(RenamePattern("{n:200000000}").baseName(original: "a", index: 1).count == 10)
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
