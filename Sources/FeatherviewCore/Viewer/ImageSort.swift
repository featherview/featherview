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

    public func store(in defaults: UserDefaults = .standard) {
        defaults.set(key.rawValue, forKey: AppSettings.sortKey.key)
        defaults.set(ascending, forKey: AppSettings.sortAscending.key)
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
            let resourceKey: URLResourceKey = key == .size ? .fileSizeKey : .contentModificationDateKey
            for url in urls {
                // The scanner lists symlinked images: read the image's size and date, not the link's.
                // Resolving only links: a realpath walk on every file cost ~20x the lookup itself.
                guard var resources = try? url.resourceValues(forKeys: [resourceKey, .isSymbolicLinkKey]) else { continue }
                if resources.isSymbolicLink == true {
                    guard let target = try? url.resolvingSymlinksInPath().resourceValues(forKeys: [resourceKey]) else { continue }
                    resources = target
                }
                if key == .size {
                    values[url] = resources.fileSize.map(SortValue.bytes)
                } else {
                    values[url] = resources.contentModificationDate.map(SortValue.date)
                }
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
        // Keys taken once: lastPathComponent inside the comparator made the scanner's sort 190 ms.
        return entries(urls, values: values).sorted { precedes($0, $1, ascending: order.ascending) }.map(\.url)
    }

    /// The first of `sorted`, in one pass.
    public static func first(_ urls: [URL], by order: SortOrder, values: [URL: SortValue]) -> URL? {
        if order == .finder { return FolderScanner.firstInFinderOrder(urls) }
        if order.key == .name {
            return urls.map { ($0.lastPathComponent, $0) }
                .max { $0.0.localizedStandardCompare($1.0) == .orderedAscending }?.1
        }
        return entries(urls, values: values).min { precedes($0, $1, ascending: order.ascending) }?.url
    }

    private typealias Entry = (url: URL, name: String, value: SortValue?)

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
        return a.name.localizedStandardCompare(b.name) == .orderedAscending
    }
}
