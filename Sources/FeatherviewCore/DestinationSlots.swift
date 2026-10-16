import Foundation

/// The 14 remembered folders for F7 (move) and F8 (copy), picked by a single key.
public struct DestinationSlots: Equatable, Sendable {
    public static let count = 14
    /// The key for each slot: 1–9, 0 for the 10th, then B, C, D, E.
    public static let keys: [Character] = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "B", "C", "D", "E"]
    static let defaultsKey = "destinationSlots"
    static let lastUsedKey = "destinationSlotLastUsed"

    public private(set) var folders: [URL?]
    /// The highlighted slot when the panel opens; Return uses it.
    public var lastUsed: Int

    public init(folders: [URL?] = [], lastUsed: Int = 0) {
        self.folders = Array((folders + Array(repeating: nil, count: Self.count)).prefix(Self.count))
        self.lastUsed = min(max(lastUsed, 0), Self.count - 1)
    }

    /// The slot a typed character picks (case-insensitive), or nil.
    public static func slot(forKey character: Character) -> Int? {
        keys.firstIndex { $0.lowercased() == character.lowercased() }
    }

    public subscript(slot: Int) -> URL? {
        get { folders[slot] }
        set { folders[slot] = newValue }
    }

    /// Reads the slots saved by `save(to:)`; missing or damaged data gives empty slots.
    public init(defaults: UserDefaults) {
        let paths = defaults.stringArray(forKey: Self.defaultsKey) ?? []
        self.init(folders: paths.map { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) },
                  lastUsed: defaults.integer(forKey: Self.lastUsedKey))
    }

    /// Re-reads the saved slots, changes them and saves them: a copy held since then (Settings,
    /// another viewer window) would otherwise overwrite slots set elsewhere meanwhile.
    @discardableResult
    public static func update(in defaults: UserDefaults, _ change: (inout DestinationSlots) -> Void) -> DestinationSlots {
        var slots = DestinationSlots(defaults: defaults)
        change(&slots)
        slots.save(to: defaults)
        return slots
    }

    public func save(to defaults: UserDefaults) {
        defaults.set(folders.map { $0?.path ?? "" }, forKey: Self.defaultsKey)
        defaults.set(lastUsed, forKey: Self.lastUsedKey)
    }
}
