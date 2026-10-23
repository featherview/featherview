import Foundation
import UniformTypeIdentifiers

/// What View › Sort By sorts the viewer's list by.
public enum SortKey: String, CaseIterable, Sendable {
    case name, dateModified, dateTaken, size, kind
}

/// The global sort order (`AppSettings.sortKey`, `sortAscending`).
public struct SortOrder: Equatable, Sendable {
    public var key: SortKey
    public var ascending: Bool

    public init(key: SortKey, ascending: Bool) {
        self.key = key
        self.ascending = ascending
    }

    /// Finder's name order, ascending: the default.
    public static let finder = SortOrder(key: .name, ascending: true)

    public static func stored(in defaults: UserDefaults = .standard) -> SortOrder {
        SortOrder(key: SortKey(rawValue: AppSettings.sortKey.value(in: defaults)) ?? .name,
                  ascending: AppSettings.sortAscending.value(in: defaults))
    }

    /// Date Taken reads every file's header: too slow for the open budget, so it sorts after the first image.
    public var readsFileHeaders: Bool { key == .dateTaken }
}

/// One file's value for a sort key.
public enum SortValue: Equatable, Sendable {
    case date(Date), bytes(Int), text(String)

    fileprivate func compare(_ other: SortValue) -> ComparisonResult {
        switch (self, other) {
        case let (.date(a), .date(b)): a == b ? .orderedSame : (a < b ? .orderedAscending : .orderedDescending)
        case let (.bytes(a), .bytes(b)): a == b ? .orderedSame : (a < b ? .orderedAscending : .orderedDescending)
        case let (.text(a), .text(b)): a.localizedStandardCompare(b)
        default: .orderedSame
        }
    }
}

/// The viewer's list in a sort order: values read off the main thread, the sort itself pure.
public enum ImageSort {
    /// Each file's value for `key`; a file it can't read has no entry. Reads the disk: call off the main thread.
    public static func values(of urls: [URL], key: SortKey) -> [URL: SortValue] {
        var values: [URL: SortValue] = [:]
        switch key {
        case .name:
            break
        case .dateModified, .size:
            // One stat per file, read fresh (a save changes size and date), following a symlink to the image:
            // URL resource values cost ~4x as much, ~90 ms for 10,000 files ahead of a folder's first image.
            for url in urls {
                values[url] = key == .size ? url.fileSize.map(SortValue.bytes) : url.modificationDate.map(SortValue.date)
            }
        case .kind:
            // Looked up once per extension, as the scanner does.
            var kinds: [String: String] = [:]
            for url in urls {
                let ext = url.pathExtension.lowercased()
                let kind = kinds[ext] ?? UTType(filenameExtension: ext)?.localizedDescription ?? ext.uppercased()
                kinds[ext] = kind
                values[url] = .text(kind)
            }
        case .dateTaken:
            for url in urls { values[url] = MetadataReader.dateTaken(of: url).map(SortValue.date) }
        }
        return values
    }

    /// `urls` in `order`. Ties and missing values fall back to Finder name order, ascending;
    /// missing values go last in both directions.
    public static func sorted(_ urls: [URL], by order: SortOrder, values: [URL: SortValue]) -> [URL] {
        guard order.key != .name else {
            let byName = FolderScanner.inFinderOrder(urls)
            return order.ascending ? byName : byName.reversed()
        }
        // Names and values ranked once, so the sort compares numbers: comparing text per pair (Kind, and every
        // tie) made 10,000 files take ~3x as long as the name sort.
        let ranks = textRanks(values)
        let keyed = FolderScanner.inFinderOrder(urls).enumerated().map { (index, url) in
            (url: url, name: index, key: values[url].map { rank($0, ranks) })
        }
        return keyed.sorted { a, b in
            switch (a.key, b.key) {
            case let (x?, y?) where x != y: order.ascending ? x < y : x > y
            case (_?, nil): true
            case (nil, _?): false
            default: a.name < b.name
            }
        }.map(\.url)
    }

    /// `sorted` with `added` put in at their place in the order, in a few comparisons each: a rename or a new file
    /// doesn't sort the whole list again.
    public static func inserting(_ added: [URL], into sorted: [URL], by order: SortOrder,
                                 values: [URL: SortValue]) -> [URL] {
        var result = sorted
        for url in added {
            let new = (url: url, name: url.lastPathComponent, value: values[url])
            var (low, high) = (0, result.count)
            while low < high {
                let mid = (low + high) / 2
                let other = result[mid]
                let otherEntry = (url: other, name: other.lastPathComponent, value: values[other])
                let after = order.key == .name
                    ? (order.ascending ? FolderScanner.finderPrecedes(otherEntry.name, new.name)
                                       : FolderScanner.finderPrecedes(new.name, otherEntry.name))
                    : precedes(otherEntry, new, ascending: order.ascending)
                if after { low = mid + 1 } else { high = mid }
            }
            result.insert(url, at: low)
        }
        return result
    }

    /// A re-sort of the open list (a new order, Date Taken after an open): reads the values and sorts. Reads the
    /// disk: call off the main thread. Dates and sizes are read again (a save or lossless rotate rewrites a file);
    /// only Date Taken keeps `cached`, reading files it lacks, since it reads every header.
    /// shortcut: a file without EXIF whose date taken falls back to its modification date keeps the date read
    /// first, re-read Date Taken for files changed since if that shows.
    public static func resorted(_ urls: [URL], by order: SortOrder,
                                cached: [URL: SortValue]) -> (urls: [URL], values: [URL: SortValue]) {
        var values = order.readsFileHeaders ? cached : [:]
        values.merge(self.values(of: urls.filter { values[$0] == nil }, key: order.key)) { $1 }
        return (sorted(urls, by: order, values: values), values)
    }

    /// The first of `sorted`, in one pass.
    public static func first(_ urls: [URL], by order: SortOrder, values: [URL: SortValue]) -> URL? {
        if order == .finder { return FolderScanner.firstInFinderOrder(urls) }
        if order.key == .name {
            return urls.map { ($0.lastPathComponent, $0) }
                .max { FolderScanner.finderPrecedes($0.0, $1.0) }?.1
        }
        return entries(urls, values: values).min { precedes($0, $1, ascending: order.ascending) }?.url
    }

    private typealias Entry = (url: URL, name: String, value: SortValue?)

    /// Each distinct text value's place in `localizedStandardCompare` order: a few kinds, so a few comparisons.
    private static func textRanks(_ values: [URL: SortValue]) -> [String: Int] {
        var texts = Set<String>()
        for case let .text(text) in values.values { texts.insert(text) }
        let ordered = texts.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        return Dictionary(uniqueKeysWithValues: ordered.enumerated().map { ($1, $0) })
    }

    /// A value as a number that orders as `SortValue.compare` does (one key's values are all one case).
    private static func rank(_ value: SortValue, _ textRanks: [String: Int]) -> Double {
        switch value {
        case let .date(date): date.timeIntervalSinceReferenceDate
        case let .bytes(bytes): Double(bytes)
        case let .text(text): Double(textRanks[text] ?? 0)
        }
    }

    private static func entries(_ urls: [URL], values: [URL: SortValue]) -> [Entry] {
        urls.map { ($0, $0.lastPathComponent, values[$0]) }
    }

    private static func precedes(_ a: Entry, _ b: Entry, ascending: Bool) -> Bool {
        switch (a.value, b.value) {
        case let (x?, y?):
            let result = x.compare(y)
            if result != .orderedSame { return ascending ? result == .orderedAscending : result == .orderedDescending }
        case (_?, nil): return true
        case (nil, _?): return false
        case (nil, nil): break
        }
        return FolderScanner.finderPrecedes(a.name, b.name)
    }
}
