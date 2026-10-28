import Foundation
import Testing
@testable import FeatherviewCore

/// A hand-built table: a few towns, one sea, one desert and an ocean split at the antimeridian.
enum PlaceFixtures {
    static let andermatt = PlaceRecord(name: "Andermatt", admin1: "Uri", country: "CH", latitude: 46.6356, longitude: 8.5939)
    static let banjul = PlaceRecord(name: "Banjul", admin1: nil, country: "GM", latitude: 13.4549, longitude: -16.5790)
    static let tozeur = PlaceRecord(name: "Tozeur", admin1: nil, country: "TN", latitude: 33.9197, longitude: 8.1335)
    static let suva = PlaceRecord(name: "Suva", admin1: nil, country: "FJ", latitude: -18.1416, longitude: 178.4419)
    static let taveuni = PlaceRecord(name: "Taveuni", admin1: nil, country: "FJ", latitude: -16.85, longitude: -179.97)

    /// A closed rectangle as one ring of (lon, lat).
    static func box(lat: ClosedRange<Double>, lon: ClosedRange<Double>) -> [(Double, Double)] {
        [(lon.lowerBound, lat.lowerBound), (lon.upperBound, lat.lowerBound), (lon.upperBound, lat.upperBound),
         (lon.lowerBound, lat.upperBound), (lon.lowerBound, lat.lowerBound)]
    }

    static let table = PlaceTable(
        places: [andermatt, banjul, tozeur, suva, taveuni],
        regions: [
            RegionRecord(name: "North Atlantic Ocean", kind: .sea, rings: [box(lat: 0...40, lon: -40 ... -15)]),
            RegionRecord(name: "Sahara", kind: .region, rings: [box(lat: 18...32, lon: -10...25)]),
            RegionRecord(name: "North Pacific Ocean", kind: .sea,
                         rings: [box(lat: 10...50, lon: 150...180), box(lat: 10...50, lon: -180 ... -130)]),
        ])

    static let englishCountries = ["CH": "Switzerland", "GM": "Gambia", "TN": "Tunisia", "FJ": "Fiji"]
    static func english(_ code: String) -> String { englishCountries[code] ?? code }
}

@Suite struct PlaceTableTests {
    let table = PlaceFixtures.table

    @Test func roundTripsThroughData() throws {
        let decoded = try PlaceTable(data: table.encoded())
        let points: [(Double, Double)] = [(46.64, 8.60), (13.35, -17.40), (31.0, 9.0), (32, -160), (-16.9, 179.99), (-40, 60)]
        for (lat, lon) in points {
            let a = table.nearest(latitude: lat, longitude: lon, within: 500)
            let b = decoded.nearest(latitude: lat, longitude: lon, within: 500)
            #expect(a?.0 == b?.0)
            #expect(a?.km == b?.km)
            #expect(table.region(latitude: lat, longitude: lon) == decoded.region(latitude: lat, longitude: lon))
        }
    }

    @Test func nearestByDistanceNotPopulation() throws {
        // A city and a village: the village is nearer, so it wins whatever their size.
        let city = PlaceRecord(name: "Zürich", admin1: "Zurich", country: "CH", latitude: 47.3667, longitude: 8.55)
        let village = PlaceRecord(name: "Kilchberg", admin1: "Zurich", country: "CH", latitude: 47.3244, longitude: 8.5450)
        let t = PlaceTable(places: [city, village], regions: [])
        let hit = try #require(t.nearest(latitude: 47.33, longitude: 8.546, within: 25))
        #expect(hit.0.name == "Kilchberg")
        #expect(hit.km < 1)
    }

    @Test func namesInTheAppsLanguage() throws {
        var nuremberg = PlaceRecord(name: "Nuremberg", admin1: "Bavaria", country: "DE", latitude: 49.454, longitude: 11.078)
        nuremberg.names = ["de": "Nürnberg"]
        nuremberg.admin1Names = ["de": "Bayern"]
        let fuerth = PlaceRecord(name: "Fürth", admin1: "Bavaria", country: "DE", latitude: 49.476, longitude: 10.989)
        let decoded = try PlaceTable(data: PlaceTable(places: [fuerth, nuremberg], regions: []).encoded())
        let german = decoded.localized(to: "de")
        #expect(german.nearest(latitude: 49.45, longitude: 11.08, within: 25)?.0.name == "Nürnberg")
        #expect(german.nearest(latitude: 49.45, longitude: 11.08, within: 25)?.0.admin1 == "Bayern")
        #expect(german.nearest(latitude: 49.48, longitude: 10.99, within: 25)?.0.name == "Fürth")
        #expect(german.nearest(latitude: 49.48, longitude: 10.99, within: 25)?.0.admin1 == "Bayern")
        #expect(decoded.localized(to: "fr").nearest(latitude: 49.45, longitude: 11.08, within: 25)?.0.name == "Nuremberg")
        #expect(decoded.nearest(latitude: 49.45, longitude: 11.08, within: 25)?.0.admin1 == "Bavaria")
    }

    @Test func nothingWithinRadius() {
        #expect(table.nearest(latitude: -40, longitude: 60, within: 25) == nil)
    }

    @Test func nearestAcrossAntimeridian() throws {
        let hit = try #require(table.nearest(latitude: -16.9, longitude: 179.99, within: 25))
        #expect(hit.0.name == "Taveuni")
        #expect(hit.km < 10)
    }

    @Test func seaBeforeRegion() {
        #expect(table.region(latitude: 13.35, longitude: -17.40)?.name == "North Atlantic Ocean")
        #expect(table.region(latitude: 31.0, longitude: 9.0)?.name == "Sahara")
        #expect(table.region(latitude: 32, longitude: -160)?.name == "North Pacific Ocean")
        #expect(table.region(latitude: 32, longitude: 170)?.name == "North Pacific Ocean")
        #expect(table.region(latitude: -40, longitude: 60) == nil)
    }

    @Test func seaAtAntimeridian() {
        #expect(table.region(latitude: 32, longitude: 180)?.name == "North Pacific Ocean")
        #expect(table.region(latitude: 32, longitude: -180)?.name == "North Pacific Ocean")
    }

    @Test func seaAtPoles() {
        let polar = PlaceTable(places: [], regions: [
            RegionRecord(name: "Arctic Ocean", kind: .sea, rings: [PlaceFixtures.box(lat: 66...90, lon: -180...180)]),
            RegionRecord(name: "Southern Ocean", kind: .sea, rings: [PlaceFixtures.box(lat: -90 ... -60, lon: -180...180)]),
        ])
        for lon in [-180.0, 0, 45, 180] {
            #expect(polar.region(latitude: 90, longitude: lon)?.name == "Arctic Ocean")
            #expect(polar.region(latitude: -90, longitude: lon)?.name == "Southern Ocean")
        }
    }

    @Test func poleDoesNotCrash() {
        for lat in [90.0, -90.0] {
            _ = table.nearest(latitude: lat, longitude: 0, within: 500)
            _ = table.region(latitude: lat, longitude: 0)
            _ = PlaceName.describe(latitude: lat, longitude: 0, in: table, countryName: PlaceFixtures.english)
        }
        let polar = PlaceTable(places: [PlaceRecord(name: "Pole", admin1: nil, country: "AQ", latitude: -89.99, longitude: 120)], regions: [])
        #expect(polar.nearest(latitude: -90, longitude: 0, within: 25)?.0.name == "Pole")
    }

    @Test func badCoordinatesGiveNoPlace() {
        for (lat, lon) in [(Double.nan, 0.0), (10, .infinity), (.nan, .nan), (-.infinity, 0), (1e20, 0), (0, 1e20), (91, 0), (0, 181)] {
            #expect(table.nearest(latitude: lat, longitude: lon, within: 25) == nil)
            #expect(table.region(latitude: lat, longitude: lon) == nil)
            #expect(PlaceName.describe(latitude: lat, longitude: lon, in: table, countryName: PlaceFixtures.english) == nil)
        }
    }

    @Test func emptyRegionsAreDropped() throws {
        let table = PlaceTable(places: [], regions: [RegionRecord(name: "X", kind: .sea, rings: []),
                                                     RegionRecord(name: "Y", kind: .sea, rings: [[], [(0, 0), (1, 1)]])])
        let decoded = try PlaceTable(data: table.encoded())
        #expect(decoded.region(latitude: 0.5, longitude: 0.5) == nil)
    }

    @Test func rejectsBadData() {
        #expect(throws: (any Error).self) { try PlaceTable(data: Data("NOPE\u{1}\u{0}xxxx".utf8)) }
        #expect(throws: (any Error).self) { try PlaceTable(data: Data()) }
        var truncated = table.encoded()
        truncated.removeLast(truncated.count / 2)
        #expect(throws: (any Error).self) { try PlaceTable(data: truncated) }
    }

    // CI's virtual Macs take ~400 ms for the debug read; the budget is about real Macs (bench `places --time`).
    @Test(.disabled(if: ProcessInfo.processInfo.environment["CI"] != nil, "CI's virtual Macs are too slow to time"))
    func loadsAFullSizeTableQuickly() throws {
        // About GeoNames cities1000 (170,000 places) and the Natural Earth outlines (300 regions, 450,000 points).
        var g = SystemRandomNumberGenerator()
        let places = (0 ..< 170_000).map { i in
            PlaceRecord(name: "Place number \(i)", admin1: i % 3 == 0 ? nil : "Province \(i % 3000)", country: "CH",
                        latitude: .random(in: -89...89, using: &g), longitude: .random(in: -179...179, using: &g))
        }
        let regions = (0 ..< 300).map { i in
            RegionRecord(name: "Region \(i)", kind: i % 2 == 0 ? .sea : .region,
                         rings: [(0 ..< 1500).map { k in (Double(k % 360) - 180, Double(k % 170) - 85) }])
        }
        let data = PlaceTable(places: places, regions: regions).encoded()
        // The fastest of three reads: a parallel test run or build only ever slows one down.
        var decoded = try PlaceTable(data: data)
        var elapsed = Duration.seconds(60)
        for _ in 0 ..< 3 {
            let start = ContinuousClock.now
            decoded = try PlaceTable(data: data)
            elapsed = min(elapsed, ContinuousClock.now - start)
        }
        // The budget is 50 ms in a release build (measured ~10 ms); unoptimized, the same reading takes ~170 ms.
        #expect(elapsed < .milliseconds(_isDebugAssertConfiguration() ? 300 : 50), "took \(elapsed)")
        let hit = try #require(decoded.nearest(latitude: places[7].latitude, longitude: places[7].longitude, within: 1))
        #expect(hit.0.name == places[7].name || hit.km == 0)
    }

    @Test func indexLoadsLazily() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("places.fvpl")
        let index = PlaceIndex()
        // Configuring reads nothing: the file doesn't exist yet.
        await index.configure(url: url)
        try PlaceFixtures.table.encoded().write(to: url)
        let name = await index.name(latitude: 46.64, longitude: 8.60)
        #expect(name?.short.hasPrefix("Andermatt, ") == true)
    }

    @Test func indexWithoutDataHasNoNames() async {
        let index = PlaceIndex()
        await index.configure(url: nil)
        #expect(await index.name(latitude: 46.64, longitude: 8.60) == nil)
    }
}
