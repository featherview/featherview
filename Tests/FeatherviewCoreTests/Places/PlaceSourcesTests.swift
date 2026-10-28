import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct PlaceSourcesTests {
    static let andermattLine = "2661750\tAndermatt\tAndermatt\tAndermat,Andermatt,Orsera,Ursera\t46.63565\t8.59388\tP\tPPL\tCH\t\tUR\t400\t1202\t\t1258\t\t1441\tEurope/Zurich\t2013-03-05"
    static let admin1 = "CH.UR\tUri\tUri\t2658226\nGM.01\tBanjul\tBanjul\t2413875\n"

    /// A FeatureCollection; each feature is (property key for the class, class, property key for the name, name, rings).
    static func geoJSON(_ features: [(String, String, String, String, [[(Double, Double)]])]) -> Data {
        let items = features.map { classKey, cls, nameKey, name, rings in
            let coordinates = rings.map { "[" + $0.map { "[\($0.0),\($0.1)]" }.joined(separator: ",") + "]" }.joined(separator: ",")
            return #"{"type":"Feature","properties":{"\#(classKey)":"\#(cls)","\#(nameKey)":"\#(name)"},"geometry":{"type":"Polygon","coordinates":[\#(coordinates)]}}"#
        }
        return Data(#"{"type":"FeatureCollection","features":[\#(items.joined(separator: ","))]}"#.utf8)
    }

    static let empty = geoJSON([])

    @Test func parsesGeoNamesLine() {
        let places = PlaceSources.places(geonamesTSV: Self.andermattLine, admin1TSV: Self.admin1)
        #expect(places == [PlaceRecord(name: "Andermatt", admin1: "Uri", country: "CH", latitude: 46.63565, longitude: 8.59388)])
    }

    @Test func unknownAdmin1IsNil() {
        let line = Self.andermattLine.replacingOccurrences(of: "\tUR\t", with: "\tZZ\t")
        #expect(PlaceSources.places(geonamesTSV: line, admin1TSV: Self.admin1).first?.admin1 == nil)
    }

    /// Inside a city a district is nearer than the city's point, and German addresses never name it alone. The city
    /// shares the district's administrative areas: Spandau is nearer Falkensee (Brandenburg) than Berlin's point.
    @Test func districtsCarryTheirCity() {
        func line(_ name: String, _ lat: String, _ lon: String, _ code: String, _ country: String, _ people: String,
                  _ areas: String) -> String {
            "1\t\(name)\t\(name)\t\t\(lat)\t\(lon)\tP\t\(code)\t\(country)\t\t\(areas)\t\(people)\t\t\t\t"
        }
        let tsv = [line("Wetzendorf", "49.47056", "11.04148", "PPLX", "DE", "8268", "02\t095\t09564\t09564000"),
                   line("Nuremberg", "49.45421", "11.07752", "PPLA3", "DE", "515543", "02\t095\t09564\t09564000"),
                   line("Fürth", "49.47593", "10.98856", "PPL", "DE", "132036", "02\t095\t09563\t09563000"),
                   line("Spandau", "52.5511", "13.19921", "PPLX", "DE", "39653", "16\t00\t11000\t11000000"),
                   line("Falkensee", "52.56014", "13.09270", "PPLA4", "DE", "44000", "11\t00\t12063\t12063080"),
                   line("Berlin", "52.52437", "13.41053", "PPLC", "DE", "3426354", "16\t00\t11000\t11000000"),
                   line("Camden", "51.54057", "-0.14334", "PPLX", "GB", "26122", "ENG\tGLA\tC4\t"),
                   line("London", "51.50853", "-0.12574", "PPLC", "GB", "8961989", "ENG\tGLA\t\t"),
                   line("Lonely", "10.0", "10.0", "PPLX", "NG", "2000", "05\t\t\t")].joined(separator: "\n")
        let names = PlaceSources.places(geonamesTSV: tsv, admin1TSV: Self.admin1).map(\.name)
        #expect(names == ["Nuremberg-Wetzendorf", "Nuremberg", "Fürth", "Berlin-Spandau", "Falkensee", "Berlin",
                          "Camden, London", "London", "Lonely"])
    }

    @Test func skipsMalformedLines() {
        let bad = [
            "",
            "2661750\tAndermatt\tAndermatt",                                               // too few columns
            Self.andermattLine.replacingOccurrences(of: "46.63565", with: "north"),       // latitude not a number
            Self.andermattLine.replacingOccurrences(of: "46.63565", with: "123.0"),       // latitude out of range
            Self.andermattLine.replacingOccurrences(of: "\tAndermatt\tAndermatt\t", with: "\t\tAndermatt\t"),  // no name
            Self.andermattLine.replacingOccurrences(of: "\tCH\t", with: "\t\t"),          // no country
        ]
        let tsv = (bad + [Self.andermattLine]).joined(separator: "\n")
        #expect(PlaceSources.places(geonamesTSV: tsv, admin1TSV: Self.admin1).map(\.name) == ["Andermatt"])
    }

    /// Spec: places with at least 1,000 people. Population 0 means unknown and stays; abandoned,
    /// historical and destroyed places go.
    @Test func skipsSmallAndGonePlaces() {
        let small = Self.andermattLine.replacingOccurrences(of: "\t1258\t", with: "\t300\t")
        let unknown = Self.andermattLine.replacingOccurrences(of: "\t1258\t", with: "\t0\t")
        let gone = ["PPLQ", "PPLH", "PPLW"].map { Self.andermattLine.replacingOccurrences(of: "\tPPL\t", with: "\t\($0)\t") }
        let tsv = ([small] + gone + [unknown]).joined(separator: "\n")
        #expect(PlaceSources.places(geonamesTSV: tsv, admin1TSV: Self.admin1).count == 1)
    }

    @Test func keepsOnlyListedFeatureClasses() throws {
        let square = [PlaceFixtures.box(lat: 0...10, lon: 0...10)]
        let marine = Self.geoJSON([("featurecla", "ocean", "name", "North Atlantic Ocean", square),
                                   ("featurecla", "sea", "name", "Black Sea", square),
                                   ("featurecla", "bay", "name", "Bay of Biscay", square),
                                   ("featurecla", "gulf", "name", "Gulf of Guinea", square),
                                   ("featurecla", "strait", "name", "Strait of Dover", square)])
        let regions = Self.geoJSON([("FEATURECLA", "Desert", "NAME", "Sahara", square),
                                    ("FEATURECLA", "Range/mtn", "NAME", "Alps", square),
                                    ("FEATURECLA", "Plateau", "NAME", "Tibetan Plateau", square)])
        let result = try PlaceSources.regions(marineGeoJSON: marine, regionsGeoJSON: regions, toleranceKm: 1)
        #expect(result.map(\.name) == ["North Atlantic Ocean", "Black Sea", "Bay of Biscay", "Gulf of Guinea", "Sahara", "Alps"])
        #expect(result.map(\.kind) == [.sea, .sea, .sea, .sea, .region, .region])
    }

    /// Natural Earth writes two ocean names in capitals; the English name reads like the others.
    @Test func capitalisedNameFallsBackToEnglish() throws {
        let marine = Data(#"{"type":"FeatureCollection","features":[{"type":"Feature","properties":{"featurecla":"ocean","name":"INDIAN OCEAN","name_en":"Indian Ocean"},"geometry":{"type":"MultiPolygon","coordinates":[[[[60,-10],[70,-10],[70,0],[60,0],[60,-10]]]]}}]}"#.utf8)
        let result = try PlaceSources.regions(marineGeoJSON: marine, regionsGeoJSON: Self.empty, toleranceKm: 1)
        #expect(result.map(\.name) == ["Indian Ocean"])
        #expect(result.first?.rings.count == 1)
    }

    /// Natural Earth's regions file writes many names in capitals, and its English name often names another
    /// feature ("AHAGGAR MTS." → "Ahag"): the English name counts only when it spells the same name.
    @Test func capitalisedRegionNameKeepsItsOwnWords() throws {
        func feature(_ name: String, _ english: String) -> String {
            #"{"type":"Feature","properties":{"FEATURECLA":"Range/mtn","NAME":"\#(name)","NAME_EN":"\#(english)"},"geometry":{"type":"Polygon","coordinates":[[[0,0],[10,0],[10,10],[0,10],[0,0]]]}}"#
        }
        let regions = Data(#"{"type":"FeatureCollection","features":[\#(feature("AHAGGAR MTS.", "Ahag")),\#(feature("CORD. CENTRAL", "Cordillera Blanca")),\#(feature("TAKLIMAKAN DESERT", "Taklimakan Desert"))]}"#.utf8)
        let result = try PlaceSources.regions(marineGeoJSON: Self.empty, regionsGeoJSON: regions, toleranceKm: 1)
        #expect(result.map(\.name) == ["Ahaggar Mts.", "Cord. Central", "Taklimakan Desert"])
    }

    @Test func rejectsNonGeoJSON() {
        #expect(throws: (any Error).self) {
            try PlaceSources.regions(marineGeoJSON: Data("nope".utf8), regionsGeoJSON: Self.empty, toleranceKm: 1)
        }
    }

    @Test func splitsRingsAtAntimeridian() throws {
        // 170 E … 170 W, written the way GeoJSON does: longitudes jump from 170 to -170.
        let ring = [(170.0, -20.0), (-170.0, -20.0), (-170.0, -10.0), (170.0, -10.0), (170.0, -20.0)]
        let marine = Self.geoJSON([("featurecla", "ocean", "name", "South Pacific Ocean", [ring])])
        let result = try PlaceSources.regions(marineGeoJSON: marine, regionsGeoJSON: Self.empty, toleranceKm: 1)
        let rings = try #require(result.first?.rings)
        #expect(rings.count == 2)
        for ring in rings {
            let lons = ring.map(\.0)
            #expect(lons.allSatisfy { (-180...180).contains($0) })
            #expect(lons.allSatisfy { $0 >= 170 } || lons.allSatisfy { $0 <= -170 })
        }
        let table = PlaceTable(places: [], regions: result)
        #expect(table.region(latitude: -15, longitude: 179.9)?.name == "South Pacific Ocean")
        #expect(table.region(latitude: -15, longitude: -179.9)?.name == "South Pacific Ocean")
        #expect(table.region(latitude: -15, longitude: 0) == nil)
    }

    /// A ring around a pole runs once round the globe; it stays as it is.
    @Test func keepsRingAroundPole() throws {
        let ring = [(-180.0, -60.0), (0.0, -60.0), (180.0, -60.0), (180.0, -90.0), (-180.0, -90.0), (-180.0, -60.0)]
        let marine = Self.geoJSON([("featurecla", "ocean", "name", "Southern Ocean", [ring])])
        let result = try PlaceSources.regions(marineGeoJSON: marine, regionsGeoJSON: Self.empty, toleranceKm: 1)
        #expect(result.first?.rings.count == 1)
        #expect(PlaceTable(places: [], regions: result).region(latitude: -70, longitude: 40)?.name == "Southern Ocean")
    }

    @Test func simplifiesRings() throws {
        // A circle of radius 0.5° (about 55 km) at the equator, 1,000 points.
        let circle = (0 ... 1000).map { i -> (Double, Double) in
            let a = Double(i % 1000) / 1000 * 2 * .pi
            return (10 + 0.5 * cos(a), 0.5 * sin(a))
        }
        let marine = Self.geoJSON([("featurecla", "sea", "name", "Round Sea", [circle])])
        let result = try PlaceSources.regions(marineGeoJSON: marine, regionsGeoJSON: Self.empty, toleranceKm: 1)
        let ring = try #require(result.first?.rings.first)
        #expect(ring.count < 100)
        #expect(ring.count > 8)
        let table = PlaceTable(places: [], regions: result)
        #expect(table.region(latitude: 0, longitude: 10)?.name == "Round Sea")
        #expect(table.region(latitude: 0.45, longitude: 10) != nil)
        #expect(table.region(latitude: 0.6, longitude: 10) == nil)
    }
}
