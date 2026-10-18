import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct BackgroundPresetTests {
    @Test func defaultIsGraphite() {
        #expect(AppSettings.backgroundColor.defaultValue == BackgroundPreset.graphite.hex)
        #expect(BackgroundPreset.graphite.hex == "#1c1c20")
    }

    @Test func presetsHaveTheSpecColours() {
        #expect(BackgroundPreset.allCases.map(\.hex) == ["#1c1c20", "#000000", "#808080", "#ffffff"])
    }

    @Test func matchingIgnoresCase() {
        #expect(BackgroundPreset.matching("#1C1C20") == .graphite)
        #expect(BackgroundPreset.matching("#FFFFFF") == .white)
    }

    @Test func customIsNil() {
        #expect(BackgroundPreset.matching("#123456") == nil)
    }

    @Test func storedBackgroundSurvivesNewDefault() {
        let name = "featherview-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("#000000", forKey: AppSettings.backgroundColor.key)
        AppSettings.registerDefaults(in: defaults)
        #expect(AppSettings.backgroundColor.value(in: defaults) == "#000000")
    }
}
