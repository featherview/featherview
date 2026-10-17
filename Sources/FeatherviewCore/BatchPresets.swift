import Foundation

/// Named batch settings (spec "Batch window": presets) and the window's own settings between launches.
/// Presets are one JSON dictionary of name → encoded settings, so one preset that fails to decode
/// (e.g. written by a future version) is skipped without losing the others.
public enum BatchPresets {
    static let presetsKey = "batchPresets"
    static let currentKey = "batchSettings"

    /// nil when something is stored but can't be read (e.g. a future version's format), so it's never overwritten.
    private static func stored(in defaults: UserDefaults) -> [String: Data]? {
        guard let object = defaults.object(forKey: presetsKey) else { return [:] }
        return (object as? Data).flatMap { try? JSONDecoder().decode([String: Data].self, from: $0) }
    }

    /// Names of the presets that load, in Finder order.
    public static func names(in defaults: UserDefaults = .standard) -> [String] {
        (stored(in: defaults) ?? [:])
            .filter { (try? JSONDecoder().decode(BatchSettings.self, from: $0.value)) != nil }
            .keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    public static func load(_ name: String, in defaults: UserDefaults = .standard) -> BatchSettings? {
        stored(in: defaults)?[name].flatMap { try? JSONDecoder().decode(BatchSettings.self, from: $0) }
    }

    /// Saving under an existing name replaces that preset. Blank names are ignored.
    /// Returns false when nothing was saved, also when the stored presets can't be read.
    @discardableResult
    public static func save(_ name: String, _ settings: BatchSettings, in defaults: UserDefaults = .standard) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let data = try? JSONEncoder().encode(settings) else { return false }
        return update(defaults) { $0[name] = data }
    }

    /// Returns false when the stored presets can't be read, so nothing was deleted.
    @discardableResult
    public static func delete(_ name: String, in defaults: UserDefaults = .standard) -> Bool {
        update(defaults) { $0[name] = nil }
    }

    private static func update(_ defaults: UserDefaults, _ change: (inout [String: Data]) -> Void) -> Bool {
        guard var all = stored(in: defaults) else { return false }
        change(&all)
        guard let encoded = try? JSONEncoder().encode(all) else { return false }
        defaults.set(encoded, forKey: presetsKey)
        return true
    }

    /// The window's own settings between launches.
    public static func current(in defaults: UserDefaults = .standard) -> BatchSettings {
        defaults.data(forKey: currentKey).flatMap { try? JSONDecoder().decode(BatchSettings.self, from: $0) } ?? BatchSettings()
    }

    public static func saveCurrent(_ settings: BatchSettings, in defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(settings), forKey: currentKey)
    }
}
