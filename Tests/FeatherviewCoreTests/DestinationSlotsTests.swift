import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct DestinationSlotsTests {
    @Test(arguments: [("1", 0), ("9", 8), ("0", 9), ("b", 10), ("E", 13), ("f", nil), ("a", nil)] as [(Character, Int?)])
    func keysPickSlots(_ key: Character, _ slot: Int?) {
        #expect(DestinationSlots.slot(forKey: key) == slot)
    }

    @Test func persistsAndPadsToFourteen() {
        let name = "featherview-tests-\(UUID().uuidString)"
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
        #expect(DestinationSlots(lastUsed: 99).lastUsed == 13)
    }
}
