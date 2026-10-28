import Foundation
import Testing
@testable import FeatherviewCore

/// The spec's four rules ("Info panel", "Place names"), country names stubbed to English.
@Suite struct PlaceNameTests {
    func describe(_ lat: Double, _ lon: Double) -> PlaceName? {
        PlaceName.describe(latitude: lat, longitude: lon, in: PlaceFixtures.table, countryName: PlaceFixtures.english)
    }

    @Test func townWithin25km() {
        #expect(describe(46.64, 8.60) == PlaceName(short: "Andermatt, Switzerland", full: "near Andermatt, Uri, Switzerland"))
    }

    @Test func townWithoutAdmin1() {
        #expect(describe(13.45, -16.58) == PlaceName(short: "Banjul, Gambia", full: "near Banjul, Gambia"))
    }

    @Test func seaOffCountry() {
        #expect(describe(13.35, -17.40) == PlaceName(short: "North Atlantic, off Gambia", full: "North Atlantic Ocean, off Banjul, Gambia"))
    }

    @Test func oneWordOceanKeepsOcean() {
        let table = PlaceTable(places: [PlaceRecord(name: "Galle", admin1: nil, country: "LK", latitude: 6.03, longitude: 80.22)],
                               regions: [RegionRecord(name: "Indian Ocean", kind: .sea, rings: [[(70, -10), (90, -10), (90, 5), (70, 5)]])])
        #expect(PlaceName.describe(latitude: 4.8, longitude: 80.2, in: table, countryName: { $0 == "LK" ? "Sri Lanka" : $0 })?.short
                == "Indian Ocean, off Sri Lanka")
    }

    @Test func regionNearCountry() {
        #expect(describe(31.0, 9.0) == PlaceName(short: "Sahara, near Tunisia", full: "Sahara, near Tunisia"))
    }

    @Test func openOcean() {
        #expect(describe(32, -160) == PlaceName(short: "North Pacific Ocean", full: "North Pacific Ocean"))
    }

    @Test func nothingNearby() {
        #expect(describe(-40, 60) == nil)
    }

    @Test func nearestAcrossAntimeridian() {
        #expect(describe(-16.9, 179.99)?.short == "Taveuni, Fiji")
    }
}
