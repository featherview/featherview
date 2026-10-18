/// The named viewer background colours (spec "Look"); anything else is a custom colour.
public enum BackgroundPreset: String, CaseIterable, Sendable {
    case graphite, black, grey, white

    public var hex: String {
        switch self {
        case .graphite: "#1c1c20"
        case .black: "#000000"
        case .grey: "#808080"
        case .white: "#ffffff"
        }
    }

    /// The preset with this colour, or nil for a custom one. `HexColor.format` writes upper case.
    public static func matching(_ hex: String) -> BackgroundPreset? {
        allCases.first { $0.hex.caseInsensitiveCompare(hex) == .orderedSame }
    }
}
