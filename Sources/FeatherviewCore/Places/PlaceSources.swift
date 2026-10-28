// Reads the sources of places.fvpl (`featherview-bench places`): GeoNames' cities1000 and
// admin1CodesASCII tables and Natural Earth's marine and region outlines as GeoJSON.

import Foundation

public enum PlaceSources {
    public enum Failure: Error { case notGeoJSON }

    /// Natural Earth feature classes kept, compared without case: marine ones become `.sea`, the others `.region`.
    static let marineClasses: Set<String> = ["ocean", "sea", "bay", "gulf"]
    static let regionClasses: Set<String> = ["desert", "range/mtn"]

    /// GeoNames rows (tab-separated: 1 name, 4 latitude, 5 longitude, 8 country, 10 admin1 code), with the
    /// admin1 name joined from admin1CodesASCII ("CH.UR\tUri\t…"). Rows that don't parse are skipped.
    public static func places(geonamesTSV: String, admin1TSV: String) -> [PlaceRecord] {
        var admin1: [Substring: String] = [:]
        for line in admin1TSV.split(separator: "\n") {
            let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
            if columns.count >= 2, !columns[1].isEmpty { admin1[columns[0]] = String(columns[1]) }
        }
        return geonamesTSV.split(separator: "\n").compactMap { line in
            let c = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard c.count > 10, !c[1].isEmpty, c[8].count == 2,
                  let lat = Double(c[4]), let lon = Double(c[5]),
                  (-90...90).contains(lat), (-180...180).contains(lon) else { return nil }
            return PlaceRecord(name: String(c[1]), admin1: c[10].isEmpty ? nil : admin1["\(c[8]).\(c[10])"],
                               country: String(c[8]), latitude: lat, longitude: lon)
        }
    }

    /// Seas from the marine outlines, then deserts and mountain ranges from the region outlines, each ring
    /// simplified to `toleranceKm` (Douglas–Peucker) and split where it crosses ±180°.
    public static func regions(marineGeoJSON: Data, regionsGeoJSON: Data, toleranceKm: Double) throws -> [RegionRecord] {
        try regions(marineGeoJSON, classes: marineClasses, kind: .sea, toleranceKm: toleranceKm)
            + regions(regionsGeoJSON, classes: regionClasses, kind: .region, toleranceKm: toleranceKm)
    }

    private static func regions(_ data: Data, classes: Set<String>, kind: RegionRecord.Kind,
                                toleranceKm: Double) throws -> [RegionRecord] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let features = root["features"] as? [[String: Any]] else { throw Failure.notGeoJSON }
        return features.compactMap { feature in
            // Natural Earth writes the marine file's keys in lower case and the regions file's in upper case.
            let properties = (feature["properties"] as? [String: Any] ?? [:])
                .reduce(into: [String: String]()) { $0[$1.key.lowercased()] = $1.value as? String }
            guard let cls = properties["featurecla"], classes.contains(cls.lowercased()),
                  var name = properties["name"], !name.isEmpty,
                  let geometry = feature["geometry"] as? [String: Any] else { return nil }
            // Two oceans are named in capitals ("INDIAN OCEAN"); their English name reads like every other one.
            if name == name.uppercased(), let english = properties["name_en"], !english.isEmpty { name = english }
            let polygons: [[[[Double]]]]
            switch geometry["type"] as? String {
            case "Polygon": polygons = (geometry["coordinates"] as? [[[Double]]]).map { [$0] } ?? []
            case "MultiPolygon": polygons = geometry["coordinates"] as? [[[[Double]]]] ?? []
            default: polygons = []
            }
            let rings = polygons.joined()
                .map { $0.compactMap { $0.count >= 2 ? ($0[0], $0[1]) : nil } }
                .flatMap { prepare($0, toleranceKm: toleranceKm) }
            return rings.isEmpty ? nil : RegionRecord(name: name, kind: kind, rings: rings)
        }
    }

    /// One ring, simplified and split at ±180°; closed (last point = first).
    static func prepare(_ ring: [(Double, Double)], toleranceKm: Double) -> [[(Double, Double)]] {
        guard var ring = ring.first.map({ ring.last! == $0 ? ring : ring + [$0] }), ring.count > 3 else { return [] }
        // Longitudes made continuous, so a ring crossing ±180° runs past it instead of jumping.
        var unwrapped = ring
        for i in 1 ..< ring.count {
            var step = ring[i].0 - ring[i - 1].0
            if step > 180 { step -= 360 } else if step < -180 { step += 360 }
            unwrapped[i].0 = unwrapped[i - 1].0 + step
        }
        // A ring around a pole runs once round the globe (Natural Earth closes it along ±180°): kept as written.
        if abs(unwrapped.last!.0 - unwrapped.first!.0) > 180 { return [simplify(ring, toleranceKm: toleranceKm)] }
        ring = simplify(unwrapped, toleranceKm: toleranceKm)
        let lons = ring.map(\.0)
        let low = lons.min()!, high = lons.max()!
        if low >= -180, high <= 180 { return [ring] }
        // One part per 360° window the ring reaches, shifted back into -180…180.
        let first = Int(((low - 180) / 360).rounded(.up)), last = Int(((high + 180) / 360).rounded(.down))
        return (first ... last).compactMap { k -> [(Double, Double)]? in
            let shift = Double(k) * 360
            var part = clip(Array(ring.dropLast()), x: shift - 180, keepAbove: true)
            part = clip(part, x: shift + 180, keepAbove: false)
            guard part.count > 2 else { return nil }
            return (part + [part[0]]).map { ($0.0 - shift, $0.1) }
        }
    }

    /// Sutherland–Hodgman against one vertical line; `ring` open (no repeated first point).
    private static func clip(_ ring: [(Double, Double)], x: Double, keepAbove: Bool) -> [(Double, Double)] {
        func inside(_ p: (Double, Double)) -> Bool { keepAbove ? p.0 >= x : p.0 <= x }
        var out: [(Double, Double)] = []
        for i in ring.indices {
            let a = ring[i == 0 ? ring.count - 1 : i - 1], b = ring[i]
            if inside(b) != inside(a) {
                let t = (x - a.0) / (b.0 - a.0)
                out.append((x, a.1 + t * (b.1 - a.1)))
            }
            if inside(b) { out.append(b) }
        }
        return out
    }

    /// Douglas–Peucker on a closed ring, in km on a plane scaled to the ring's mean latitude.
    static func simplify(_ ring: [(Double, Double)], toleranceKm: Double) -> [(Double, Double)] {
        guard ring.count > 4 else { return ring }
        let meanLat = ring.reduce(0) { $0 + $1.1 } / Double(ring.count)
        let kx = 111.32 * cos(meanLat * .pi / 180), ky = 110.57
        let p = ring.map { ($0.0 * kx, $0.1 * ky) }
        func distance(_ i: Int, _ a: Int, _ b: Int) -> Double {
            let (dx, dy) = (p[b].0 - p[a].0, p[b].1 - p[a].1), length = dx * dx + dy * dy
            let t = length == 0 ? 0 : max(0, min(1, ((p[i].0 - p[a].0) * dx + (p[i].1 - p[a].1) * dy) / length))
            return hypot(p[i].0 - p[a].0 - t * dx, p[i].1 - p[a].1 - t * dy)
        }
        // The first and last point coincide, so the ring is split at the point farthest from them.
        let far = (1 ..< p.count - 1).max { distance($0, 0, 0) < distance($1, 0, 0) }!
        var keep = [Bool](repeating: false, count: p.count)
        keep[0] = true; keep[far] = true; keep[p.count - 1] = true
        var stack = [(0, far), (far, p.count - 1)]
        while let (a, b) = stack.popLast() {
            guard b - a > 1 else { continue }
            let (i, d) = (a + 1 ..< b).map { ($0, distance($0, a, b)) }.max { $0.1 < $1.1 }!
            if d > toleranceKm {
                keep[i] = true
                stack += [(a, i), (i, b)]
            }
        }
        return ring.indices.filter { keep[$0] }.map { ring[$0] }
    }
}
