/// Light or dark for the whole app (spec "Settings"): System follows macOS, Light and Dark override it.
public enum AppearanceMode: String, CaseIterable, Sendable {
    case system, light, dark

    /// The stored setting, System for anything unknown.
    public init(stored: String) { self = AppearanceMode(rawValue: stored) ?? .system }
}
