// The place data behind the info panel's place names (spec "Info panel", "Place names").
//
// File format "places.fvpl", version 1, all integers little-endian:
//   "FVPL" (4 bytes), UInt16 version = 1, then the rest of the file is one LZFSE-compressed payload:
//   - string table: UInt32 count, then per string UInt32 byte length + UTF-8 bytes
//   - places: UInt32 count, then per place Int32 latitude × 10,000, Int32 longitude × 10,000,
//     UInt32 name index, UInt32 admin1 index (0xFFFF_FFFF = none), 2 bytes ISO 3166 alpha-2 country.
//     Places are sorted by 1° cell (row = ⌊lat + 90⌋ clamped to 0…179, column = ⌊lon + 180⌋ mod 360,
//     cell = row × 360 + column).
//   - cell start table: 360 × 180 UInt32, the index of each cell's first place; a cell ends where the
//     next one starts (the last at the place count).
//   - regions: UInt32 count, then per region UInt32 name index, UInt8 kind (0 sea, 1 region),
//     bounding box Int32 min lon, min lat, max lon, max lat × 10,000, UInt32 ring count, then per ring
//     UInt32 point count + Int32 lon, lat × 10,000 per point. A region's rings are tested even-odd
//     together (outer rings and holes alike); rings crossing ±180° are stored split there.

import Foundation

/// A town or village with at least 1,000 people.
public struct PlaceRecord: Equatable, Sendable {
    public var name: String
    public var admin1: String?
    /// ISO 3166 alpha-2.
    public var country: String
    public var latitude: Double
    public var longitude: Double

    public init(name: String, admin1: String?, country: String, latitude: Double, longitude: Double) {
        self.name = name
        self.admin1 = admin1
        self.country = country
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// A sea, ocean, desert or mountain range outline.
public struct RegionRecord: Equatable, Sendable {
    public enum Kind: UInt8, Sendable { case sea, region }
    public var name: String
    public var kind: Kind
    /// Points as (lon, lat); outer ring first.
    public var rings: [[(Double, Double)]]

    public init(name: String, kind: Kind, rings: [[(Double, Double)]]) {
        self.name = name
        self.kind = kind
        self.rings = rings
    }

    public static func == (a: RegionRecord, b: RegionRecord) -> Bool {
        a.name == b.name && a.kind == b.kind && a.rings.count == b.rings.count
            && zip(a.rings, b.rings).allSatisfy { $0.count == $1.count && zip($0, $1).allSatisfy { $0 == $1 } }
    }
}

public struct PlaceTable: Sendable {
    public enum Failure: Error { case notPlaceData, unsupportedVersion, damaged }

    private static let scale = 10_000.0
    private static let columns = 360, rows = 180
    private static let earthKm = 6371.0088

    /// Sorted by cell. Kept packed, with names as string table indices, so reading the file allocates
    /// nothing per place; a `PlaceRecord` is made only for a lookup's answer.
    private let places: [Packed]
    private let strings: StringTable
    /// `columns × rows + 1` entries: places of cell c are `cellStart[c]..<cellStart[c + 1]`.
    private let cellStart: [Int]
    /// Seas first, then regions, each with its bounding box (min lon, min lat, max lon, max lat).
    private let regions: [(record: RegionRecord, box: (Double, Double, Double, Double))]

    public init(places: [PlaceRecord], regions: [RegionRecord]) {
        func q(_ v: Double) -> Double { (v * Self.scale).rounded() / Self.scale }
        var strings = StringTable(), index: [String: UInt32] = [:]
        func id(_ s: String) -> UInt32 {
            if let i = index[s] { return i }
            let i = strings.append(s)
            index[s] = i
            return i
        }
        let packed = places.map { p in
            let c = Array(p.country.utf8.prefix(2)) + [0x20, 0x20]
            return Packed(lat: Self.fixed(p.latitude), lon: Self.fixed(p.longitude), name: id(p.name),
                          admin1: p.admin1.map(id) ?? .max, country: (c[0], c[1]))
        }
        // Rings of fewer than 3 points enclose nothing; a region left without rings has no bounding box.
        let regionsQ = regions.map { RegionRecord(name: $0.name, kind: $0.kind,
                                                  rings: $0.rings.filter { $0.count > 2 }.map { $0.map { (q($0.0), q($0.1)) } }) }
            .filter { !$0.rings.isEmpty }
        let sorted = packed.enumerated()
            .sorted { (Self.cell($0.element), $0.offset) < (Self.cell($1.element), $1.offset) }
            .map(\.element)
        var start = [Int](repeating: 0, count: Self.columns * Self.rows + 1)
        for place in sorted { start[Self.cell(place) + 1] += 1 }
        for i in 1 ..< start.count { start[i] += start[i - 1] }
        self.init(sorted: sorted, strings: strings, cellStart: start, regions: regionsQ.map { ($0, Self.boundingBox($0.rings)) })
    }

    private init(sorted: [Packed], strings: StringTable, cellStart: [Int],
                 regions: [(record: RegionRecord, box: (Double, Double, Double, Double))]) {
        self.places = sorted
        self.strings = strings
        self.cellStart = cellStart
        self.regions = regions.filter { $0.record.kind == .sea } + regions.filter { $0.record.kind == .region }
    }

    // MARK: Lookup

    /// The nearest place by great-circle distance, if one lies within `km`.
    public func nearest(latitude: Double, longitude: Double, within km: Double) -> (PlaceRecord, km: Double)? {
        guard Self.isValid(latitude, longitude) else { return nil }
        // Every cell the circle of radius `km` can touch: its latitude band, and in each the longitudes it spans.
        let radiusDeg = km / Self.earthKm * 180 / .pi
        let lowRow = Self.row(latitude - radiusDeg), highRow = Self.row(latitude + radiusDeg)
        let lonSpan: Double
        if abs(latitude) + radiusDeg >= 89.9 {
            lonSpan = 180
        } else {
            let s = sin(km / Self.earthKm) / cos(latitude * .pi / 180)
            lonSpan = s >= 1 ? 180 : asin(s) * 180 / .pi
        }
        let firstColumn = Int((longitude + 180 - lonSpan).rounded(.down))
        let columnCount = lonSpan >= 179 ? Self.columns : min(Self.columns, Int((longitude + 180 + lonSpan).rounded(.down)) - firstColumn + 1)

        var best: (Packed, km: Double)?
        for row in lowRow ... highRow {
            for c in 0 ..< columnCount {
                let column = ((firstColumn + c) % Self.columns + Self.columns) % Self.columns
                let cell = row * Self.columns + column
                for place in places[cellStart[cell] ..< cellStart[cell + 1]] {
                    let d = Self.distanceKm(latitude, longitude, Self.degrees(place.lat), Self.degrees(place.lon))
                    if d <= km, d < best?.km ?? .infinity { best = (place, d) }
                }
            }
        }
        return best.map { (record($0.0), $0.km) }
    }

    private func record(_ p: Packed) -> PlaceRecord {
        let country = [p.country.0, p.country.1].filter { $0 != 0x20 }
        return PlaceRecord(name: strings[p.name], admin1: p.admin1 == .max ? nil : strings[p.admin1],
                           country: String(decoding: country, as: UTF8.self),
                           latitude: Self.degrees(p.lat), longitude: Self.degrees(p.lon))
    }

    /// The sea or ocean containing the point, else the desert or mountain range.
    public func region(latitude: Double, longitude: Double) -> RegionRecord? {
        guard Self.isValid(latitude, longitude) else { return nil }
        // Rings are split at ±180 and the ray-cast test is strict, so +180 is only found as -180.
        let longitude = longitude == 180 ? -180 : longitude
        return regions.first { region in
            let (minLon, minLat, maxLon, maxLat) = region.box
            guard longitude >= minLon, longitude <= maxLon, latitude >= minLat, latitude <= maxLat else { return false }
            return Self.contains(region.record.rings, x: longitude, y: latitude)
        }?.record
    }

    // MARK: Geometry

    /// Coordinates come from a file's GPS tags: NaN, infinite or out-of-range values give no place.
    private static func isValid(_ latitude: Double, _ longitude: Double) -> Bool {
        latitude.isFinite && longitude.isFinite && abs(latitude) <= 90 && abs(longitude) <= 180
    }

    private static func row(_ latitude: Double) -> Int { min(rows - 1, max(0, Int((latitude + 90).rounded(.down)))) }

    private static func fixed(_ v: Double) -> Int32 { Int32((v * scale).rounded()) }
    private static func degrees(_ v: Int32) -> Double { Double(v) / scale }

    private static func cell(_ p: Packed) -> Int { cell(degrees(p.lat), degrees(p.lon)) }

    private static func cell(_ latitude: Double, _ longitude: Double) -> Int {
        let column = (Int((longitude + 180).rounded(.down)) % columns + columns) % columns
        return row(latitude) * columns + column
    }

    private static func distanceKm(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let r = Double.pi / 180
        let dLat = (lat2 - lat1) * r, dLon = (lon2 - lon1) * r
        let a = sin(dLat / 2) * sin(dLat / 2) + cos(lat1 * r) * cos(lat2 * r) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthKm * asin(min(1, a.squareRoot()))
    }

    /// Even-odd ray casting over all rings.
    private static func contains(_ rings: [[(Double, Double)]], x: Double, y: Double) -> Bool {
        var inside = false
        for ring in rings where ring.count > 2 {
            var j = ring.count - 1
            for i in ring.indices {
                let (xi, yi) = ring[i], (xj, yj) = ring[j]
                if (yi > y) != (yj > y), x < (xj - xi) * (y - yi) / (yj - yi) + xi { inside.toggle() }
                j = i
            }
        }
        return inside
    }

    private static func boundingBox(_ rings: [[(Double, Double)]]) -> (Double, Double, Double, Double) {
        var box = (Double.infinity, Double.infinity, -Double.infinity, -Double.infinity)
        for point in rings.joined() {
            box = (min(box.0, point.0), min(box.1, point.1), max(box.2, point.0), max(box.3, point.1))
        }
        return box
    }

    // MARK: Encoding

    public func encoded() -> Data {
        var strings = self.strings
        let fixed = Self.fixed
        var body = Writer()
        body.u32(UInt32(places.count))
        for p in places {
            body.i32(p.lat); body.i32(p.lon)
            body.u32(p.name); body.u32(p.admin1)
            body.bytes([p.country.0, p.country.1])
        }
        for start in cellStart.dropLast() { body.u32(UInt32(start)) }
        body.u32(UInt32(regions.count))
        for (r, box) in regions {
            body.u32(strings.append(r.name)); body.bytes([r.kind.rawValue])
            [box.0, box.1, box.2, box.3].forEach { body.i32(fixed($0)) }
            body.u32(UInt32(r.rings.count))
            for ring in r.rings {
                body.u32(UInt32(ring.count))
                for (lon, lat) in ring { body.i32(fixed(lon)); body.i32(fixed(lat)) }
            }
        }

        var payload = Writer()
        payload.u32(UInt32(strings.ranges.count))
        for range in strings.ranges { payload.u32(UInt32(range.count)); payload.bytes(Array(strings.bytes[range])) }
        payload.data.append(body.data)

        var file = Writer()
        file.bytes(Array("FVPL".utf8)); file.u16(1)
        // LZFSE of an in-memory buffer can't fail short of running out of memory.
        file.data.append(try! (payload.data as NSData).compressed(using: .lzfse) as Data)
        return file.data
    }

    public init(data: Data) throws {
        guard data.count >= 6, data.prefix(4) == Data("FVPL".utf8) else { throw Failure.notPlaceData }
        guard UInt16(data[data.startIndex + 4]) | UInt16(data[data.startIndex + 5]) << 8 == 1 else { throw Failure.unsupportedVersion }
        guard let payload = try? (data.dropFirst(6) as NSData).decompressed(using: .lzfse) as Data else { throw Failure.damaged }
        let bytes = [UInt8](payload)
        let (places, strings, cellStart, regions) = try bytes.withUnsafeBytes { try Self.parse($0, bytes) }
        self.init(sorted: places, strings: strings, cellStart: cellStart, regions: regions)
    }

    private static func parse(_ raw: UnsafeRawBufferPointer, _ payload: [UInt8]) throws
        -> ([Packed], StringTable, [Int], [(record: RegionRecord, box: (Double, Double, Double, Double))]) {
        var r = Reader(bytes: raw)
        var strings = StringTable()
        let stringCount = try r.count(each: 4)
        strings.ranges.reserveCapacity(stringCount)
        for _ in 0 ..< stringCount {
            let length = Int(try r.u32())
            try r.skip(length)
            strings.ranges.append(r.offset - length ..< r.offset)
        }
        strings.bytes = payload
        func string(_ i: UInt32) throws -> UInt32 {
            guard Int(i) < stringCount else { throw Failure.damaged }
            return i
        }

        let placeCount = try r.count(each: 18)
        var places: [Packed] = []
        places.reserveCapacity(placeCount)
        for _ in 0 ..< placeCount {
            let lat = try r.i32(), lon = try r.i32(), name = try string(r.u32()), admin1 = try r.u32()
            if admin1 != .max { _ = try string(admin1) }
            places.append(Packed(lat: lat, lon: lon, name: name, admin1: admin1, country: (try r.u8(), try r.u8())))
        }
        var cellStart: [Int] = []
        cellStart.reserveCapacity(columns * rows + 1)
        for _ in 0 ..< columns * rows { cellStart.append(Int(try r.u32())) }
        cellStart.append(places.count)
        guard zip(cellStart, cellStart.dropFirst()).allSatisfy({ $0 <= $1 }) else { throw Failure.damaged }

        var regions: [(record: RegionRecord, box: (Double, Double, Double, Double))] = []
        for _ in 0 ..< (try r.count(each: 25)) {
            let name = strings[try string(r.u32())]
            guard let kind = RegionRecord.Kind(rawValue: try r.u8()) else { throw Failure.damaged }
            let box = (degrees(try r.i32()), degrees(try r.i32()), degrees(try r.i32()), degrees(try r.i32()))
            var rings: [[(Double, Double)]] = []
            for _ in 0 ..< (try r.count(each: 4)) {
                let n = try r.count(each: 8)
                var ring: [(Double, Double)] = []
                ring.reserveCapacity(n)
                for _ in 0 ..< n { ring.append((degrees(try r.i32()), degrees(try r.i32()))) }
                rings.append(ring)
            }
            regions.append((RegionRecord(name: name, kind: kind, rings: rings), box))
        }
        return (places, strings, cellStart, regions)
    }
}

/// A place as stored: fixed-point degrees, string table indices (admin1 0xFFFF_FFFF = none), country bytes.
private struct Packed: Sendable {
    var lat, lon: Int32
    var name, admin1: UInt32
    var country: (UInt8, UInt8)
}

/// Strings as UTF-8 byte ranges in one buffer, made into `String`s only when asked for.
private struct StringTable: Sendable {
    var bytes: [UInt8] = []
    var ranges: [Range<Int>] = []

    /// Damaged UTF-8 comes out repaired (U+FFFD), never as a crash.
    subscript(i: UInt32) -> String { String(decoding: bytes[ranges[Int(i)]], as: UTF8.self) }

    mutating func append(_ s: String) -> UInt32 {
        let start = bytes.count
        bytes.append(contentsOf: s.utf8)
        ranges.append(start ..< bytes.count)
        return UInt32(ranges.count - 1)
    }
}

private struct Writer {
    var data = Data()
    mutating func bytes(_ b: [UInt8]) { data.append(contentsOf: b) }
    mutating func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
    mutating func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
    mutating func i32(_ v: Int32) { u32(UInt32(bitPattern: v)) }
}

private struct Reader {
    let bytes: UnsafeRawBufferPointer
    var offset = 0
    mutating func skip(_ n: Int) throws {
        guard n >= 0, n <= bytes.count - offset else { throw PlaceTable.Failure.damaged }
        offset += n
    }
    mutating func u8() throws -> UInt8 {
        try skip(1)
        return bytes[offset - 1]
    }
    mutating func u32() throws -> UInt32 {
        try skip(4)
        return bytes.loadUnaligned(fromByteOffset: offset - 4, as: UInt32.self).littleEndian
    }
    mutating func i32() throws -> Int32 { Int32(bitPattern: try u32()) }
    /// A count of items each at least `each` bytes long, never more than the rest of the data holds.
    mutating func count(each: Int) throws -> Int {
        let n = Int(try u32())
        guard n <= (bytes.count - offset) / each else { throw PlaceTable.Failure.damaged }
        return n
    }
}
