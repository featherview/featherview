struct OptionError: Error, Equatable {
    let message: String
    init(_ message: String) { self.message = message }
}

/// The options each mode reads; anything else fails, so a typo can't fall back to a default unnoticed.
let knownOptions: [String: Set<String>] = [
    "corpus": [],
    "psdlayers": [],
    "places": ["--lookups", "--language"],
    "histogram": ["--screen", "--runs"],
    "decode": ["--raw", "--screen", "--runs", "--json", "--baseline"],
    "browse": ["--screen", "--interval-ms", "--loops"],
    "thumbnail": ["--out"],
    "fuzz": ["--out", "--seconds", "--seed"],
    "grid": ["--points", "--scale", "--cells", "--width", "--json", "--baseline"],
]

/// `--name value` pairs, each name's values in order.
func parseOptions(_ arguments: [String], mode: String) throws(OptionError) -> [String: [String]] {
    var options: [String: [String]] = [:]
    var rest = arguments[...]
    while let name = rest.popFirst() {
        guard name.hasPrefix("--"), let value = rest.popFirst() else { throw OptionError("Unexpected argument \(name).") }
        guard knownOptions[mode, default: []].contains(name) else { throw OptionError("Unknown option \(name) for \(mode).") }
        options[name, default: []].append(value)
    }
    return options
}
