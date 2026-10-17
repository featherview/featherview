struct Row: Codable {
    let file: String
    let screen: String  // "full" for the full-size decode
    let width: Int, height: Int
    let megabytes: Double
    let firstMs: Double, medianMs: Double, p95Ms: Double, minMs: Double
}

/// What fails `--baseline`: a median more than 10 % slower, or a baseline row this run no longer has
/// (the file stopped decoding, or other screens were passed).
func baselineFailures(_ rows: [Row], baseline: [Row]) -> [String] {
    let now = Dictionary(rows.map { ("\($0.file) \($0.screen)", $0.medianMs) }, uniquingKeysWith: { a, _ in a })
    return baseline.compactMap { old in
        guard let new = now["\(old.file) \(old.screen)"] else {
            return "missing: \(old.file) \(old.screen) (no longer decodes, or not run on this screen)"
        }
        guard new > old.medianMs * 1.1 else { return nil }
        return "slower: \(old.file) \(old.screen) median \(f(old.medianMs)) → \(f(new)) ms"
    }
}
