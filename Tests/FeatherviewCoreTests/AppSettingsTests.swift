import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct AppSettingsTests {
    /// A private defaults domain per test, so tests never touch the user's settings or each other.
    private func freshDefaults() -> UserDefaults {
        let name = "featherview-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func defaultsMatchTheSpec() {
        let defaults = freshDefaults()
        AppSettings.registerDefaults(in: defaults)
        #expect(AppSettings.pastEnd.value(in: defaults) == "folderChooser")
        #expect(defaults.bool(forKey: AppSettings.showHiddenFiles.key) == false)
        #expect(defaults.bool(forKey: AppSettings.showNextAfterRemoval.key) == true)
        #expect(defaults.bool(forKey: AppSettings.moveSidecars.key) == true)
        #expect(defaults.string(forKey: AppSettings.backgroundColor.key) == "#000000")
        #expect(defaults.bool(forKey: AppSettings.checkerboard.key) == true)
        #expect(defaults.bool(forKey: AppSettings.rememberWindowFrame.key) == true)
        #expect(defaults.integer(forKey: AppSettings.zoomStepPercent.key) == 10)
        #expect(defaults.bool(forKey: AppSettings.showOverlay.key) == false)
        #expect(defaults.bool(forKey: AppSettings.hidePointer.key) == true)
        #expect(defaults.bool(forKey: AppSettings.askBeforeMoveCopy.key) == false)
        #expect(AppSettings.openWith.map { $0.value(in: defaults) } == ["", "", ""])
    }

    @Test func storedValueWinsAndWrongTypeFallsBack() {
        let defaults = freshDefaults()
        defaults.set(25, forKey: AppSettings.zoomStepPercent.key)
        defaults.set("yes", forKey: AppSettings.checkerboard.key)
        #expect(AppSettings.zoomStepPercent.value(in: defaults) == 25)
        #expect(AppSettings.checkerboard.value(in: defaults) == true)
    }

    @Test func unknownPastEndFallsBackToChooser() {
        #expect(PastEndBehavior(rawValue: "sideways") == nil)
        #expect(PastEndBehavior.allCases == [.folderChooser, .loop, .stop])
    }

    @Test func hexColorsRoundTrip() throws {
        let color = try #require(HexColor.parse("#FF8000"))
        #expect(color.red == 1)
        #expect(abs(color.green - 128.0 / 255) < 0.0001)
        #expect(color.blue == 0)
        #expect(HexColor.format(red: color.red, green: color.green, blue: color.blue) == "#FF8000")
    }

    @Test(arguments: ["", "000000", "#00000", "#GG0000", "#0000000"])
    func malformedHexIsRejected(_ hex: String) {
        #expect(HexColor.parse(hex) == nil)
    }
}

@Suite struct OverlayTemplateTests {
    @Test func replacesEveryPlaceholder() {
        let text = OverlayTemplate.render(
            "{name} in {folder}: {index}/{count}, {size}, {date}",
            values: ["name": "a.jpg", "folder": "Trip", "index": "3", "count": "9",
                     "size": "4032 × 3024", "date": "16.10.2026"])
        #expect(text == "a.jpg in Trip: 3/9, 4032 × 3024, 16.10.2026")
    }

    @Test func missingValuesBecomeEmptyAndUnknownPlaceholdersStay() {
        #expect(OverlayTemplate.render("{name} {date} {iso}", values: ["name": "a.jpg"]) == "a.jpg  {iso}")
    }
}
