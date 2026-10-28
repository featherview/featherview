// Reads the sources of places.fvpl (`featherview-bench places`): GeoNames' cities1000 and
// admin1CodesASCII tables and Natural Earth's marine and region outlines as GeoJSON.

import Foundation

public enum PlaceSources {
    public enum Failure: Error { case notGeoJSON }

    /// Natural Earth feature classes kept, compared without case: marine ones become `.sea`, the others `.region`.
    static let marineClasses: Set<String> = ["ocean", "sea", "bay", "gulf"]
    static let regionClasses: Set<String> = ["desert", "range/mtn"]

    /// The app's languages and the GeoNames language codes that name places in each, best first.
    static let languages: [String: [String]] = {
        var map = Dictionary(uniqueKeysWithValues: ["ar", "ca", "cs", "da", "de", "el", "en", "es", "fi", "fr", "he", "hi", "hu",
                                                    "id", "it", "ja", "ko", "ms", "nl", "pl", "ro", "ru", "sv", "th", "tr", "uk", "vi"]
            .map { ($0, [$0]) })
        map["pt-BR"] = ["pt-BR", "pt"]
        map["zh-Hans"] = ["zh-Hans", "zh-CN", "zh"]
        map["zh-Hant"] = ["zh-Hant", "zh-TW", "zh-HK"]
        return map
    }()

    /// Places this size or larger carry names in the app's languages; smaller ones rarely have any.
    static let translatedPopulation = 15_000

    /// GeoNames rows (tab-separated: 0 id, 1 name, 4 latitude, 5 longitude, 7 feature code, 8 country, 10 admin1 code,
    /// 14 population), with the admin1 name joined from admin1CodesASCII ("CH.UR\tUri\tUri\t2658226"). Rows that don't
    /// parse are skipped, and so are places under 1,000 people (0 means unknown and stays) and abandoned,
    /// historical or destroyed ones. A city district (PPLX) is named with its city: the nearest larger place within
    /// 25 km that isn't a district itself and is in the same state and, as far as both have them, the same
    /// administrative areas (in Germany the municipality, so Berlin-Spandau never takes Falkensee, which is nearer).
    /// "Nuremberg-Wetzendorf" in German-speaking countries, "Camden, London" elsewhere; inside a city a district is
    /// nearly always nearer than the city's point.
    /// `alternateNamesTSV` (alternateNamesV2: 1 id, 2 language, 3 name, 4 preferred, 5 short, 6 colloquial,
    /// 7 historic, 8 from, 9 to) gives the names in the app's languages: of places of 15,000 people or more, their
    /// districts and every state.
    public static func places(geonamesTSV: String, admin1TSV: String, alternateNamesTSV: String = "") -> [PlaceRecord] {
        var admin1: [Substring: (name: String, id: Substring)] = [:]
        for line in admin1TSV.split(separator: "\n") {
            let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
            if columns.count >= 2, !columns[1].isEmpty { admin1[columns[0]] = (String(columns[1]), columns.count > 3 ? columns[3] : "") }
        }
        let rows: [(record: PlaceRecord, id: Substring, admin1: Substring?, district: Bool, population: Int, areas: [Substring])] =
            geonamesTSV.split(separator: "\n").compactMap { line in
            let c = line.split(separator: "\t", omittingEmptySubsequences: false)
            let population = c.count > 14 ? Int(c[14]) ?? 0 : 0
            guard c.count > 14, !c[1].isEmpty, c[8].count == 2,
                  !["PPLQ", "PPLH", "PPLW"].contains(c[7]), !(1...999).contains(population),
                  let lat = Double(c[4]), let lon = Double(c[5]),
                  (-90...90).contains(lat), (-180...180).contains(lon) else { return nil }
            let state = c[10].isEmpty ? nil : admin1["\(c[8]).\(c[10])"]
            let record = PlaceRecord(name: String(c[1]), admin1: state?.name, country: String(c[8]), latitude: lat, longitude: lon)
            return (record, c[0], state?.id, c[7] == "PPLX", population, [c[10], c[11], c[12], c[13]])
        }
        // Places that aren't districts, by whole degree, to find a district's city among the cells around it.
        var cells: [Int: [Int]] = [:]
        func cell(_ lat: Double, _ lon: Double) -> Int { Int(lat.rounded(.down) + 90) * 400 + Int(lon.rounded(.down) + 180) }
        for (i, row) in rows.enumerated() where !row.district { cells[cell(row.record.latitude, row.record.longitude), default: []].append(i) }
        let cities: [Int?] = rows.map { row in
            guard row.district else { return nil }
            let lat = row.record.latitude, lon = row.record.longitude
            var city: (index: Int, km: Double)?
            for dLat in -1...1 { for dLon in -1...1 {
                for i in cells[cell(lat + Double(dLat), lon + Double(dLon))] ?? [] {
                    let other = rows[i]
                    guard other.record.country == row.record.country, other.population > row.population,
                          !row.areas[0].isEmpty, other.areas[0] == row.areas[0],
                          zip(row.areas, other.areas).allSatisfy({ $0.isEmpty || $1.isEmpty || $0 == $1 }) else { continue }
                    let km = PlaceTable.distanceKm(lat, lon, other.record.latitude, other.record.longitude)
                    if km <= 25, km < city?.km ?? .infinity { city = (i, km) }
                }
            } }
            return city?.index
        }

        let translated = rows.indices.filter { rows[$0].population >= translatedPopulation || cities[$0] != nil }
        let names = alternateNames(alternateNamesTSV, ids: Set(translated.map { rows[$0].id } + admin1.values.map(\.id)))
        func localized(_ i: Int) -> [String: String] {
            (names[rows[i].id] ?? [:]).filter { $0.value != rows[i].record.name }
        }
        func isLatin(_ s: String) -> Bool { s.applyingTransform(.toLatin, reverse: false) == s }
        func joined(_ city: String, _ district: String, _ country: String) -> String {
            ["DE", "AT", "CH"].contains(country) ? "\(city)-\(district)" : "\(district), \(city)"
        }
        var admin1Names: [Substring: [String: String]] = [:]
        for state in admin1.values where !state.id.isEmpty {
            admin1Names[state.id] = (names[state.id] ?? [:]).filter { $0.value != state.name }
        }

        return rows.indices.map { i in
            var record = rows[i].record
            record.admin1Names = rows[i].admin1.flatMap { admin1Names[$0] } ?? [:]
            guard let c = cities[i] else {
                if rows[i].population >= translatedPopulation { record.names = localized(i) }
                return record
            }
            let city = rows[c].record.name, cityNames = localized(c), districtNames = localized(i)
            record.name = joined(city, record.name, record.country)
            guard rows[c].population >= translatedPopulation else { return record }
            for language in Set(cityNames.keys).union(districtNames.keys) {
                let cityName = cityNames[language] ?? city, districtName = districtNames[language] ?? rows[i].record.name
                // "ニュルンベルク-Wetzendorf" mixes scripts: the district keeps its own name instead.
                if isLatin(cityName) == isLatin(districtName) { record.names[language] = joined(cityName, districtName, record.country) }
            }
            return record
        }
    }

    /// Per GeoNames id among `ids`, the best name in each of the app's languages.
    private static func alternateNames(_ tsv: String, ids: Set<Substring>) -> [Substring: [String: String]] {
        let codes = languages.flatMap { language, codes in codes.enumerated().map { ($1, (language, $0)) } }
        let rankOf = Dictionary(uniqueKeysWithValues: codes)
        var best: [Substring: [String: (rank: (Int, Int), name: Substring)]] = [:]
        for line in tsv.split(separator: "\n") {
            let c = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard c.count > 3, !c[3].isEmpty, ids.contains(c[1]), let (language, codeRank) = rankOf[String(c[2])] else { continue }
            // Colloquial, historic or dated names never name a place today.
            if c.count > 6, c[6] == "1" { continue }
            if c.count > 7, c[7] == "1" { continue }
            if c.count > 9, !c[8].isEmpty || !c[9].isEmpty { continue }
            let rank = (codeRank, c[4] == "1" ? 0 : c.count > 5 && c[5] == "1" ? 2 : 1)
            if let known = best[c[1], default: [:]][language], known.rank <= rank { continue }
            best[c[1], default: [:]][language] = (rank, c[3])
        }
        return best.mapValues { names in
            var result = names.mapValues { String($0.name) }
            if result["zh-Hant"] == nil, let simplified = result["zh-Hans"] {
                result["zh-Hant"] = simplified.applyingTransform(StringTransform("Hans-Hant"), reverse: false)
            }
            return result
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
            // Some names are in capitals ("INDIAN OCEAN", "AHAGGAR MTS."). The English name often names another
            // feature ("Ahag"), so it counts only when it spells the same name; otherwise the name is title-cased.
            if name == name.uppercased() {
                let english = properties["name_en"] ?? ""
                name = english.caseInsensitiveCompare(name) == .orderedSame ? english : name.capitalized
            }
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
