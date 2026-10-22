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
        #expect(defaults.string(forKey: AppSettings.appearance.key) == "system")
        #expect(defaults.bool(forKey: AppSettings.hideBarsWhileViewing.key) == false)
        #expect(defaults.bool(forKey: AppSettings.checkerboard.key) == true)
        #expect(defaults.bool(forKey: AppSettings.rememberWindowFrame.key) == true)
        #expect(defaults.integer(forKey: AppSettings.zoomStepPercent.key) == 10)
        #expect(defaults.bool(forKey: AppSettings.showOverlay.key) == true)
        #expect(defaults.string(forKey: AppSettings.overlayTemplate.key) == "{path} — {index} / {count}")
        #expect(defaults.bool(forKey: AppSettings.hidePointer.key) == true)
        #expect(defaults.bool(forKey: AppSettings.askBeforeMoveCopy.key) == false)
        #expect(AppSettings.openWith.map { $0.value(in: defaults) } == ["", "", ""])
        #expect(defaults.object(forKey: AppSettings.offeredDefaultViewer.key) as? Bool == false)
        #expect(defaults.bool(forKey: AppSettings.checkForUpdates.key) == true)
        #expect(AppSettings.lastUpdateCheck.value(in: defaults) == .distantPast)
        #expect(AppSettings.skippedVersion.value(in: defaults) == "")
        #expect(defaults.double(forKey: AppSettings.thumbnailSize.key) == 128)
        #expect(defaults.string(forKey: AppSettings.fitMode.key) == "fit")
        #expect(defaults.object(forKey: AppSettings.keepZoom.key) as? Bool == false)
        #expect(defaults.object(forKey: AppSettings.slideshowSeconds.key) as? Int == 5)
        #expect(defaults.object(forKey: AppSettings.slideshowShuffle.key) as? Bool == false)
        #expect(defaults.object(forKey: AppSettings.slideshowRepeat.key) as? Bool == false)
    }

    @Test func slideshowOptionsFromSettings() {
        let defaults = freshDefaults()
        defaults.set(10, forKey: AppSettings.slideshowSeconds.key)
        defaults.set(true, forKey: AppSettings.slideshowShuffle.key)
        #expect(AppSettings.slideshowOptions(in: defaults)
                == Slideshow.Options(interval: .seconds(10), shuffle: true, repeats: false))
        defaults.set(7, forKey: AppSettings.slideshowSeconds.key)  // not a menu choice
        #expect(AppSettings.slideshowOptions(in: defaults).interval == .seconds(5))
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

    @Test func valuesThatLookLikePlaceholdersAreNotReplacedAgain() {
        let values = ["name": "{count} photos.jpg", "folder": "{date}", "index": "3", "count": "9",
                      "date": "16.10.2026"]
        #expect(OverlayTemplate.render("{name} — {index} / {count}", values: values) == "{count} photos.jpg — 3 / 9")
        #expect(OverlayTemplate.render("{folder}", values: values) == "{date}")
        #expect(OverlayTemplate.render("{name}", values: ["name": "{date}.jpg", "date": "16.10.2026"]) == "{date}.jpg")
    }

    @Test func pathIsTheFullPathWithTheHomeFolderAsTilde() {
        let home = URL(filePath: "/Users/ann")
        #expect(OverlayTemplate.path(of: URL(filePath: "/Users/ann/Pictures/a.jpg"), home: home) == "~/Pictures/a.jpg")
        #expect(OverlayTemplate.path(of: URL(filePath: "/Users/anna/a.jpg"), home: home) == "/Users/anna/a.jpg")
        #expect(OverlayTemplate.path(of: URL(filePath: "/Volumes/Card/DCIM/a.jpg"), home: home) == "/Volumes/Card/DCIM/a.jpg")
        #expect(OverlayTemplate.render("{path}", values: ["path": "~/a.jpg"]) == "~/a.jpg")
    }

    @Test func fileValuesUseTheFilesOwnPixelSizeAndDate() throws {
        // Fit mode shows a smaller decode; the overlay must still name the file's real size.
        let url = try Fixtures.writeImage(to: Fixtures.makeTempDir().appendingPathComponent("a.jpg"),
                                          width: 40, height: 30, orientation: 6)
        let values = OverlayTemplate.fileValues(of: url)
        #expect(values["size"] == "30 × 40")
        #expect(values["date"]?.isEmpty == false)
    }
}
