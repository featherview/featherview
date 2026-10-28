import Foundation

/// A photo's place in both forms: `short` for the info panel's header, `full` for its Location group.
public struct PlaceName: Equatable, Sendable {
    public var short: String
    public var full: String

    public init(short: String, full: String) {
        self.short = short
        self.full = full
    }

    /// The spec's four rules ("Info panel", "Place names"), in order; nil when none applies.
    public static func describe(latitude: Double, longitude: Double, in table: PlaceTable,
                                countryName: (String) -> String = { Locale.current.localizedString(forRegionCode: $0) ?? $0 }) -> PlaceName? {
        if let (place, _) = table.nearest(latitude: latitude, longitude: longitude, within: 25) {
            let country = countryName(place.country)
            let full = if let admin1 = place.admin1 {
                String(localized: "near \(place.name), \(admin1), \(country)", comment: "Info panel place: town, state or province, country")
            } else {
                String(localized: "near \(place.name), \(country)", comment: "Info panel place: town, country")
            }
            return PlaceName(short: String(localized: "Place, country", defaultValue: "\(place.name), \(country)",
                                           comment: "Info panel header: town, country"),
                             full: full)
        }
        guard let region = table.region(latitude: latitude, longitude: longitude) else { return nil }
        let reach: Double = region.kind == .sea ? 200 : 500
        guard let (place, _) = table.nearest(latitude: latitude, longitude: longitude, within: reach) else {
            return PlaceName(short: region.name, full: region.name)
        }
        let country = countryName(place.country)
        switch region.kind {
        case .sea:
            let sea = region.name.hasSuffix(" Ocean") ? String(region.name.dropLast(" Ocean".count)) : region.name
            return PlaceName(short: String(localized: "\(sea), off \(country)", comment: "Info panel place: sea, off country"),
                             full: String(localized: "\(region.name), off \(place.name), \(country)",
                                          comment: "Info panel place: sea, off nearest town, country"))
        case .region:
            let text = String(localized: "\(region.name), near \(country)", comment: "Info panel place: desert or mountain range, near country")
            return PlaceName(short: text, full: text)
        }
    }
}
