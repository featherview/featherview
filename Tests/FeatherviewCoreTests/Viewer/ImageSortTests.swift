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

    @Test func equalKindsAndSizesFallBackToFinderOrder() {
        // Ties are the common case (one kind, camera files of one size): they must keep Finder's name order.
        let urls = ["IMG_10.jpg", "IMG_2.jpg", "img_1.jpg", "IMG_3.png", "IMG_20.png"].map(url)
        let kinds = Dictionary(uniqueKeysWithValues: urls.map {
            ($0, SortValue.text($0.pathExtension == "png" ? "PNG image" : "JPEG image"))
        })
        #expect(names(ImageSort.sorted(urls.shuffled(), by: SortOrder(key: .kind, ascending: true), values: kinds))
                == ["img_1.jpg", "IMG_2.jpg", "IMG_10.jpg", "IMG_3.png", "IMG_20.png"])
        #expect(names(ImageSort.sorted(urls.shuffled(), by: SortOrder(key: .kind, ascending: false), values: kinds))
                == ["IMG_3.png", "IMG_20.png", "img_1.jpg", "IMG_2.jpg", "IMG_10.jpg"])
        let sizes = Dictionary(uniqueKeysWithValues: urls.map { ($0, SortValue.bytes(500)) })
        #expect(names(ImageSort.sorted(urls.shuffled(), by: SortOrder(key: .size, ascending: false), values: sizes))
                == ["img_1.jpg", "IMG_2.jpg", "IMG_3.png", "IMG_10.jpg", "IMG_20.png"])
    }

    /// Values with many ties and some missing, for comparing the fast paths with `sorted`.
    private func mixedValues(_ urls: [URL], key: SortKey) -> [URL: SortValue] {
        var values: [URL: SortValue] = [:]
        for (i, u) in urls.enumerated() where i % 7 != 0 {
            switch key {
            case .name: break
            case .dateModified, .dateTaken: values[u] = .date(Date(timeIntervalSince1970: Double(i % 11)))
            case .size: values[u] = .bytes(i % 13)
            case .kind: values[u] = .text("kind \(i % 5)")
            }
        }
        return values
    }

    @Test func insertingMatchesSorted() {
        let urls = (0..<200).map { url("img\($0 % 37)-\($0).jpg") }
        for key in SortKey.allCases {
            let values = mixedValues(urls, key: key)
            for ascending in [true, false] {
                let order = SortOrder(key: key, ascending: ascending)
                let listed = ImageSort.sorted(Array(urls.shuffled().prefix(150)), by: order, values: values)
                let added = urls.filter { !listed.contains($0) }
                #expect(ImageSort.inserting(added, into: listed, by: order, values: values)
                        == ImageSort.sorted(urls, by: order, values: values), "\(key) \(ascending)")
            }
        }
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

    @Test func valuesRereadFilesChangedOnDisk() throws {
        // The same URL values are read again after a save or Follow New Files: their cached values must not win.
        let dir = try Fixtures.makeTempDir()
        let file = dir.appendingPathComponent("a.jpg")
        let link = dir.appendingPathComponent("link.jpg")
        try Data(count: 10).write(to: file)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 0)], ofItemAtPath: file.path)
        #expect(ImageSort.values(of: [file, link], key: .size) == [file: .bytes(10), link: .bytes(10)])
        #expect(ImageSort.values(of: [file], key: .dateModified)[file] == .date(Date(timeIntervalSince1970: 0)))
        try Data(count: 1_000).write(to: file)
        let later = Date(timeIntervalSince1970: 1_000_000_000)
        try FileManager.default.setAttributes([.modificationDate: later], ofItemAtPath: file.path)
        #expect(ImageSort.values(of: [file, link], key: .size) == [file: .bytes(1_000), link: .bytes(1_000)])
        #expect(ImageSort.values(of: [file], key: .dateModified)[file] == .date(later))
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

    @Test func sizeAndDateCostAboutAStatAndResolveOnlySymlinks() throws {
        // A folder opens on its first image by date or size: all values are read before that image decodes.
        // Resolving every path walks each of the 20 components with lstat, ~20x a stat.
        var dir = try Fixtures.makeTempDir()
        for i in 0..<20 { dir.appendPathComponent("d\(i)") }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let names = (0..<2_000).map { "\($0).jpg" }
        for name in names { FileManager.default.createFile(atPath: dir.appendingPathComponent(name).path, contents: Data(count: 1)) }
        let fresh = { names.map { URL(fileURLWithPath: dir.appendingPathComponent($0).path) } }
        // Fastest of five, fresh URLs each time (a URL caches its resource values).
        func fastest(_ body: ([URL]) -> Void) -> Duration {
            (0..<5).map { _ in
                let urls = fresh()
                let start = ContinuousClock.now
                body(urls)
                return ContinuousClock.now - start
            }.min()!
        }
        let plain = fastest { for url in $0 { var info = stat(); _ = stat(url.path, &info) } }
        for key in [SortKey.size, .dateModified] {
            var values: [URL: SortValue] = [:]
            let read = fastest { values = ImageSort.values(of: $0, key: key) }
            #expect(values.count == 2_000)
            #expect(read < plain * 5, "\(key): \(read) vs \(plain)")
        }
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
            let values = mixedValues(urls, key: key)
            for ascending in [true, false] {
                let order = SortOrder(key: key, ascending: ascending)
                #expect(ImageSort.first(urls, by: order, values: values)
                        == ImageSort.sorted(urls, by: order, values: values).first, "\(key) \(ascending)")
            }
        }
        #expect(ImageSort.first([], by: .finder, values: [:]) == nil)
    }

    @Test func resortedRereadsDatesAndSizes() throws {
        // A lossless rotate rewrites the file while the folder is open: its old date must not keep its place.
        let dir = try Fixtures.makeTempDir()
        let (a, b) = (dir.appendingPathComponent("a.jpg"), dir.appendingPathComponent("b.jpg"))
        try Data(count: 10).write(to: a)
        try Data(count: 20).write(to: b)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2_000)], ofItemAtPath: a.path)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000)], ofItemAtPath: b.path)
        let stale: [URL: SortValue] = [a: .date(Date(timeIntervalSince1970: 0)), b: .date(Date(timeIntervalSince1970: 1_000))]
        let byDate = ImageSort.resorted([a, b], by: SortOrder(key: .dateModified, ascending: false), cached: stale)
        #expect(byDate.urls == [a, b])
        #expect(byDate.values[a] == .date(Date(timeIntervalSince1970: 2_000)))
        let bySize = ImageSort.resorted([a, b], by: SortOrder(key: .size, ascending: true), cached: [a: .bytes(99), b: .bytes(1)])
        #expect(bySize.urls == [a, b])
    }

    @Test func resortedKeepsCachedDateTaken() {
        // Date Taken reads every header: a new direction reuses what the last sort read, and reads only new files.
        let (a, b) = (url("a.jpg"), url("b.jpg"))
        let cached: [URL: SortValue] = [a: .date(Date(timeIntervalSince1970: 200)), b: .date(Date(timeIntervalSince1970: 100))]
        let result = ImageSort.resorted([a, b], by: SortOrder(key: .dateTaken, ascending: true), cached: cached)
        #expect(result.urls == [b, a])
        #expect(result.values == cached)
    }

    @Test func readsFileHeadersOnlyForDateTaken() {
        for key in SortKey.allCases {
            #expect(SortOrder(key: key, ascending: true).readsFileHeaders == (key == .dateTaken))
        }
    }

    @Test func storedOrderRoundTripsAndDefaultsToName() {
        let name = "featherview-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(SortOrder.stored(in: defaults) == .finder)
        let order = SortOrder(key: .size, ascending: false)
        defaults.set(order.key.rawValue, forKey: AppSettings.sortKey.key)
        defaults.set(order.ascending, forKey: AppSettings.sortAscending.key)
        #expect(SortOrder.stored(in: defaults) == order)
        defaults.set("bogus", forKey: AppSettings.sortKey.key)
        #expect(SortOrder.stored(in: defaults).key == .name)
    }
}
