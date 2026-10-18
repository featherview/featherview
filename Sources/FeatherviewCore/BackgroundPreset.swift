/// The named viewer background colours (spec "Look"); anything else is a custom colour.
public enum BackgroundPreset: String, CaseIterable, Sendable {
    case graphite, black, grey, white

    public var hex: String {
        switch self {
        case .graphite: "#1c1c20"
        case .black: "#000000"
        case .grey: "#e7e7ec"
        case .white: "#ffffff"
        }
    }

    /// The preset with this colour, or nil for a custom one. `HexColor.format` writes upper case.
    public static func matching(_ hex: String) -> BackgroundPreset? {
        allCases.first { $0.hex.caseInsensitiveCompare(hex) == .orderedSame }
    }
}

/// The background menu's selection: Custom stays chosen once the user picks it or a custom
/// colour, even when that colour lands on a preset, so the colour well doesn't vanish mid-pick.
public struct BackgroundMenu: Sendable {
    public private(set) var customChosen = false

    public init() {}

    /// The menu item to show; nil is Custom.
    public func selection(for hex: String) -> BackgroundPreset? {
        customChosen ? nil : BackgroundPreset.matching(hex)
    }

    /// The user picked a menu item (nil is Custom).
    public mutating func choose(_ preset: BackgroundPreset?) { customChosen = preset == nil }

    /// The user picked a colour in the colour well.
    public mutating func pickedCustomColour() { customChosen = true }
}
