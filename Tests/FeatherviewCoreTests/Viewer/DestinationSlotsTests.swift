import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct DestinationSlotsTests {
    @Test(arguments: [("1", 0), ("9", 8), ("0", 9), ("b", 10), ("E", 13), ("f", nil), ("a", nil)] as [(Character, Int?)])
    func keysPickSlots(_ key: Character, _ slot: Int?) {
        #expect(DestinationSlots.slot(forKey: key) == slot)
    }

    @Test func persistsAndPadsToFourteen() {
        let name = testDefaultsName()
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(DestinationSlots(defaults: defaults).folders == Array(repeating: nil, count: 14))

        var slots = DestinationSlots()
        slots[2] = URL(fileURLWithPath: "/Users/x/Pictures/Keep", isDirectory: true)
        slots.lastUsed = 2
        slots.save(to: defaults)
        let loaded = DestinationSlots(defaults: defaults)
        #expect(loaded == slots)
        #expect(loaded[2]?.path == "/Users/x/Pictures/Keep")
    }

    @Test func lastUsedClampsToTheLastSlot() {
        #expect(DestinationSlots(lastUsed: 99).lastUsed == 13)
    }

    /// Two holders of a stale copy (Settings, another viewer window) must not undo each other's slots.
    @Test func updateKeepsChangesMadeMeanwhile() {
        let name = testDefaultsName()
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let keep = URL(fileURLWithPath: "/Users/x/Keep", isDirectory: true)
        let other = URL(fileURLWithPath: "/Users/x/Other", isDirectory: true)
        DestinationSlots.update(in: defaults) { $0[0] = keep }
        let updated = DestinationSlots.update(in: defaults) { $0[1] = other; $0.lastUsed = 1 }
        #expect(updated[0] == keep && updated[1] == other)
        #expect(DestinationSlots(defaults: defaults) == updated)
    }
}
