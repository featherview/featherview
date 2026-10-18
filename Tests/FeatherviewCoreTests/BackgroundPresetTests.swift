import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct BackgroundPresetTests {
    @Test func defaultIsGraphite() {
        #expect(AppSettings.backgroundColor.defaultValue == BackgroundPreset.graphite.hex)
        #expect(BackgroundPreset.graphite.hex == "#1c1c20")
    }

    @Test func presetsHaveTheSpecColours() {
        #expect(BackgroundPreset.allCases.map(\.hex) == ["#1c1c20", "#000000", "#e7e7ec", "#ffffff"])
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

@Suite struct BackgroundMenuTests {
    @Test func customColourLandingOnAPresetStaysCustom() {
        var menu = BackgroundMenu()
        #expect(menu.selection(for: "#123456") == nil)
        menu.pickedCustomColour()
        #expect(menu.selection(for: "#FFFFFF") == nil)
    }

    @Test func choosingAPresetLeavesCustom() {
        var menu = BackgroundMenu()
        menu.choose(nil)
        #expect(menu.selection(for: "#000000") == nil)
        menu.choose(.black)
        #expect(menu.selection(for: "#000000") == .black)
    }
}
