import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct AppearanceModeTests {
    @Test func unknownValueFallsBackToSystem() {
        let name = testDefaultsName()
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("sepia", forKey: AppSettings.appearance.key)
        #expect(AppearanceMode(stored: AppSettings.appearance.value(in: defaults)) == .system)
        defaults.set("dark", forKey: AppSettings.appearance.key)
        #expect(AppearanceMode(stored: AppSettings.appearance.value(in: defaults)) == .dark)
    }
}
