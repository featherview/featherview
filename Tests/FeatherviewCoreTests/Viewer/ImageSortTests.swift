import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import FeatherviewCore

@Suite struct ImageSortTests {
    private func url(_ name: String) -> URL { URL(fileURLWithPath: "/x/\(name)") }
    private func names(_ urls: [URL]) -> [String] { urls.map(\.lastPathComponent) }

    @Test func nameIsFinderOrder() {
        let urls = ["img10.jpg", "img2.jpg", "Img1.jpg"].map(url)
        #expect(names(ImageSort.sorted(urls, by: .finder, values: [:])) == ["Img1.jpg", "img2.jpg", "img10.jpg"])
    }

    @Test func nameDescendingReverses() {
        let urls = ["img10.jpg", "img2.jpg", "Img1.jpg"].map(url)
        let order = SortOrder(key: .name, ascending: false)
        #expect(names(ImageSort.sorted(urls, by: order, values: [:])) == ["img10.jpg", "img2.jpg", "Img1.jpg"])
    }

    @Test func dateModifiedOldestFirst() {
        let (a, b, c) = (url("a.jpg"), url("b.jpg"), url("c.jpg"))
        let values: [URL: SortValue] = [a: .date(Date(timeIntervalSince1970: 300)),
                                        b: .date(Date(timeIntervalSince1970: 100)),
                                        c: .date(Date(timeIntervalSince1970: 200))]
        #expect(ImageSort.sorted([a, b, c], by: SortOrder(key: .dateModified, ascending: true), values: values) == [b, c, a])
        #expect(ImageSort.sorted([a, b, c], by: SortOrder(key: .dateModified, ascending: false), values: values) == [a, c, b])
    }

    @Test func tiesFallBackToNameAscending() {
        let (a, b) = (url("a.jpg"), url("b.jpg"))
        let same = SortValue.date(Date(timeIntervalSince1970: 100))
        let values: [URL: SortValue] = [a: same, b: same]
        for ascending in [true, false] {
            #expect(ImageSort.sorted([b, a], by: SortOrder(key: .dateModified, ascending: ascending), values: values) == [a, b])
        }
    }

    @Test func missingValuesSortLast() {
        let (a, b, c, d) = (url("a.jpg"), url("b.jpg"), url("c.jpg"), url("d.jpg"))
        let values: [URL: SortValue] = [b: .bytes(10), d: .bytes(20)]
        #expect(ImageSort.sorted([c, d, a, b], by: SortOrder(key: .size, ascending: true), values: values) == [b, d, a, c])
        #expect(ImageSort.sorted([c, d, a, b], by: SortOrder(key: .size, ascending: false), values: values) == [d, b, a, c])
    }

    @Test func sizeAndKindOrder() {
        let (a, b, c) = (url("a.png"), url("b.jpg"), url("c.tif"))
        let sizes: [URL: SortValue] = [a: .bytes(1_000), b: .bytes(20), c: .bytes(300)]
        #expect(ImageSort.sorted([a, b, c], by: SortOrder(key: .size, ascending: true), values: sizes) == [b, c, a])
        let kinds: [URL: SortValue] = [a: .text("PNG image"), b: .text("JPEG image"), c: .text("TIFF image")]
        #expect(ImageSort.sorted([a, b, c], by: SortOrder(key: .kind, ascending: true), values: kinds) == [b, a, c])
        #expect(ImageSort.sorted([a, b, c], by: SortOrder(key: .kind, ascending: false), values: kinds) == [c, a, b])
    }

    @Test func valuesReadModificationDateAndSize() throws {
        let dir = try Fixtures.makeTempDir()
        let small = dir.appendingPathComponent("small.jpg")
        let big = dir.appendingPathComponent("big.jpg")
        try Data(count: 10).write(to: small)
        try Data(count: 5_000).write(to: big)
        let date = Date(timeIntervalSince1970: 1_000_000)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: small.path)
        #expect(ImageSort.values(of: [small], key: .dateModified)[small] == .date(date))
        let sizes = ImageSort.values(of: [small, big], key: .size)
        #expect(sizes[small] == .bytes(10))
        #expect(sizes[big] == .bytes(5_000))
        #expect(ImageSort.values(of: [small], key: .name).isEmpty)
        #expect(ImageSort.values(of: [dir.appendingPathComponent("gone.jpg")], key: .size).isEmpty)
    }

    @Test func valuesFollowSymlinksToTheImage() throws {
        let dir = try Fixtures.makeTempDir()
        let png = try Fixtures.writeImage(to: dir.appendingPathComponent("big.png"), width: 4, height: 4, type: .png)
        let date = Date(timeIntervalSince1970: 1_000_000)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: png.path)
        let link = dir.appendingPathComponent("link.png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: png)
        let size = try #require(png.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        #expect(ImageSort.values(of: [link], key: .size)[link] == .bytes(size))
        #expect(ImageSort.values(of: [link], key: .dateModified)[link] == .date(date))
        #expect(ImageSort.values(of: [link], key: .dateTaken)[link] == .date(date))
    }

    @Test func sizeAndDateResolveOnlySymlinks() throws {
        // Resolving every path walks each component with lstat: ~20x the size lookup, over the folder-open budget.
        var dir = try Fixtures.makeTempDir()
        for i in 0..<20 { dir.appendPathComponent("d\(i)") }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let names = (0..<2_000).map { "\($0).jpg" }
        for name in names { FileManager.default.createFile(atPath: dir.appendingPathComponent(name).path, contents: Data(count: 1)) }
        let fresh = { names.map { URL(fileURLWithPath: dir.appendingPathComponent($0).path) } }
        // Fastest of five, fresh URLs each time (a URL caches its resource values).
        func fastest(_ body: ([URL]) throws -> Void) rethrows -> Duration {
            try (0..<5).map { _ in
                let urls = fresh()
                let start = ContinuousClock.now
                try body(urls)
                return ContinuousClock.now - start
            }.min()!
        }
        let plain = try fastest { for url in $0 { _ = try url.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey]) } }
        var values: [URL: SortValue] = [:]
        let sorted = fastest { values = ImageSort.values(of: $0, key: .size) }
        #expect(values.count == 2_000)
        #expect(sorted < plain * 2, "\(sorted) vs \(plain)")
    }

    @Test func kindIsPerExtensionIgnoringCase() {
        let (a, b, c) = (url("a.jpg"), url("b.JPG"), url("c.zzzq"))
        let values = ImageSort.values(of: [a, b, c], key: .kind)
        #expect(values[a] == .text(UTType(filenameExtension: "jpg")!.localizedDescription!))
        #expect(values[a] == values[b])
        if UTType(filenameExtension: "zzzq")?.localizedDescription == nil {
            #expect(values[c] == .text("ZZZQ"))
        }
    }

    @Test func dateTakenPrefersExif() throws {
        let dir = try Fixtures.makeTempDir()
        let jpeg = try Fixtures.writeImage(
            to: dir.appendingPathComponent("a.jpg"), width: 4, height: 4,
            properties: [kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2020:01:02 03:04:05"]])
        let png = try Fixtures.writeImage(to: dir.appendingPathComponent("b.png"), width: 4, height: 4, type: .png)
        let newer = Date(timeIntervalSince1970: 1_700_000_000)
        for file in [jpeg, png] {
            try FileManager.default.setAttributes([.modificationDate: newer], ofItemAtPath: file.path)
        }
        let exif = Calendar(identifier: .gregorian).date(from: DateComponents(
            year: 2020, month: 1, day: 2, hour: 3, minute: 4, second: 5))!
        let values = ImageSort.values(of: [jpeg, png], key: .dateTaken)
        #expect(values[jpeg] == .date(exif))
        #expect(values[png] == .date(newer))
    }

    @Test func firstMatchesSorted() {
        let urls = (0..<200).map { url("img\($0 % 37)-\($0).jpg") }.shuffled()
        for key in SortKey.allCases {
            var values: [URL: SortValue] = [:]
            for (i, u) in urls.enumerated() where i % 7 != 0 {  // some values missing
                switch key {
                case .name: break
                case .dateModified, .dateTaken: values[u] = .date(Date(timeIntervalSince1970: Double(i % 11)))
                case .size: values[u] = .bytes(i % 13)
                case .kind: values[u] = .text("kind \(i % 5)")
                }
            }
            for ascending in [true, false] {
                let order = SortOrder(key: key, ascending: ascending)
                #expect(ImageSort.first(urls, by: order, values: values)
                        == ImageSort.sorted(urls, by: order, values: values).first, "\(key) \(ascending)")
            }
        }
        #expect(ImageSort.first([], by: .finder, values: [:]) == nil)
    }

    @Test func readsFileHeadersOnlyForDateTaken() {
        for key in SortKey.allCases {
            #expect(SortOrder(key: key, ascending: true).readsFileHeaders == (key == .dateTaken))
        }
    }

    @Test func storedOrderRoundTripsAndDefaultsToName() {
        let name = "featherview-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        #expect(SortOrder.stored(in: defaults) == .finder)
        let order = SortOrder(key: .size, ascending: false)
        order.store(in: defaults)
        #expect(SortOrder.stored(in: defaults) == order)
        defaults.set("bogus", forKey: AppSettings.sortKey.key)
        #expect(SortOrder.stored(in: defaults).key == .name)
    }
}
