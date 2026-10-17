import Foundation

/// Named batch settings (spec "Batch window": presets) and the window's own settings between launches.
/// Presets are one JSON dictionary of name → encoded settings, so one preset that fails to decode
/// (e.g. written by a future version) is skipped without losing the others.
public enum BatchPresets {
    static let presetsKey = "batchPresets"
    static let currentKey = "batchSettings"

    private static func stored(in defaults: UserDefaults) -> [String: Data] {
        defaults.data(forKey: presetsKey).flatMap { try? JSONDecoder().decode([String: Data].self, from: $0) } ?? [:]
    }

    /// Names of the presets that load, in Finder order.
    public static func names(in defaults: UserDefaults = .standard) -> [String] {
        stored(in: defaults)
            .filter { (try? JSONDecoder().decode(BatchSettings.self, from: $0.value)) != nil }
            .keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    public static func load(_ name: String, in defaults: UserDefaults = .standard) -> BatchSettings? {
        stored(in: defaults)[name].flatMap { try? JSONDecoder().decode(BatchSettings.self, from: $0) }
    }

    /// Saving under an existing name replaces that preset. Blank names are ignored.
    public static func save(_ name: String, _ settings: BatchSettings, in defaults: UserDefaults = .standard) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let data = try? JSONEncoder().encode(settings) else { return }
        var all = stored(in: defaults)
        all[name] = data
        defaults.set(try? JSONEncoder().encode(all), forKey: presetsKey)
    }

    public static func delete(_ name: String, in defaults: UserDefaults = .standard) {
        var all = stored(in: defaults)
        all[name] = nil
        defaults.set(try? JSONEncoder().encode(all), forKey: presetsKey)
    }

    /// The window's own settings between launches.
    public static func current(in defaults: UserDefaults = .standard) -> BatchSettings {
        defaults.data(forKey: currentKey).flatMap { try? JSONDecoder().decode(BatchSettings.self, from: $0) } ?? BatchSettings()
    }

    public static func saveCurrent(_ settings: BatchSettings, in defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(settings), forKey: currentKey)
    }
}
