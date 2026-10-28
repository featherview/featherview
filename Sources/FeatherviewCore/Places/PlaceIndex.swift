import Foundation

/// The app's place table, read from disk on the first lookup (never at launch) and kept until quit.
public actor PlaceIndex {
    public static let shared = PlaceIndex()

    private var url: URL?
    /// nil until the first lookup tries to read the file; `.some(nil)` when it can't be read.
    private var table: PlaceTable??

    public init() {}

    /// The app passes its bundled places.fvpl at launch, nil if absent. Reads nothing.
    public func configure(url: URL?) {
        self.url = url
        table = nil
    }

    public func name(latitude: Double, longitude: Double) async -> PlaceName? {
        if table == nil {
            table = .some(url.flatMap { try? PlaceTable(data: Data(contentsOf: $0, options: .mappedIfSafe)) })
        }
        guard let loaded = table ?? nil else { return nil }
        return PlaceName.describe(latitude: latitude, longitude: longitude, in: loaded)
    }
}
