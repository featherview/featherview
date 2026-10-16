import Foundation

/// Each format's options and named profiles (spec "Format options": remembered per format, saved
/// as profiles), shared by Save As, the batch window and Settings › Formats.
public enum FormatSettings {
    /// The format Save As offers first: the one used last.
    public static let lastSaveFormat = Setting(key: "saveAsFormat", defaultValue: "jpg")

    /// The last Save As format, or JPEG when this Mac can't write the stored one (e.g. a newer macOS added it).
    public static func lastFormat(in defaults: UserDefaults = .standard) -> OutputFormat {
        FormatRegistry.format(id: lastSaveFormat.value(in: defaults)) ?? .jpeg
    }

    static func optionsKey(_ format: OutputFormat) -> String { "formatOptions.\(format.id)" }
    static func profilesKey(_ format: OutputFormat) -> String { "formatProfiles.\(format.id)" }

    public static func options(for format: OutputFormat, in defaults: UserDefaults = .standard) -> FormatOptions {
        defaults.data(forKey: optionsKey(format))
            .flatMap { try? JSONDecoder().decode(FormatOptions.self, from: $0) } ?? format.defaultOptions
    }

    public static func save(_ options: FormatOptions, for format: OutputFormat, in defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(options), forKey: optionsKey(format))
    }

    /// Profile names in Finder order, with their options.
    public static func profiles(for format: OutputFormat, in defaults: UserDefaults = .standard) -> [(name: String, options: FormatOptions)] {
        let stored = defaults.data(forKey: profilesKey(format))
            .flatMap { try? JSONDecoder().decode([String: FormatOptions].self, from: $0) } ?? [:]
        return stored.sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }.map { ($0.key, $0.value) }
    }

    /// Saving under an existing name replaces that profile. Blank names are ignored.
    public static func saveProfile(_ name: String, _ options: FormatOptions, for format: OutputFormat,
                                   in defaults: UserDefaults = .standard) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        var all = Dictionary(uniqueKeysWithValues: profiles(for: format, in: defaults).map { ($0.name, $0.options) })
        all[name] = options
        defaults.set(try? JSONEncoder().encode(all), forKey: profilesKey(format))
    }

    public static func deleteProfile(_ name: String, for format: OutputFormat, in defaults: UserDefaults = .standard) {
        var all = Dictionary(uniqueKeysWithValues: profiles(for: format, in: defaults).map { ($0.name, $0.options) })
        all[name] = nil
        defaults.set(try? JSONEncoder().encode(all), forKey: profilesKey(format))
    }
}
