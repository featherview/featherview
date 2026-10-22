import Foundation
import Testing
@testable import FeatherviewCore

/// The test bundle has no compiled catalog, so `String(localized:)` returns the English key with its
/// arguments filled in; the singular forms are checked in the shipped catalog's `en` plural variations.
@Suite struct GridTextTests {
    private let folder = URL(filePath: "/Users/me/Pictures/Keep", directoryHint: .isDirectory)
    private let a = URL(filePath: "/tmp/a.jpg"), b = URL(filePath: "/tmp/b.jpg")

    private func englishOne(_ key: String) throws -> String? {
        let entry = try StringCatalog.load(StringCatalog.shippedURL).strings[key]
        return entry?.localizations?["en"]?.variations?.plural?["one"]?.stringUnit?.value
    }

    @Test func counterSingularAndPlural() throws {
        #expect(GridText.counter(120) == "120 images")
        #expect(try englishOne("%lld images") == "%lld image")
    }

    @Test func oneFailureNamesTheFile() {
        #expect(GridText.trashFailed([a]) == "Couldn't move a.jpg to the Trash")
        #expect(GridText.transferFailed([a], operation: .move, folder: folder) == "Couldn't move a.jpg to Keep")
        #expect(GridText.transferFailed([a], operation: .copy, folder: folder) == "Couldn't copy a.jpg to Keep")
    }

    @Test func severalFailuresCount() throws {
        #expect(GridText.trashFailed([a, b]) == "Couldn't move 2 images to the Trash")
        #expect(GridText.transferFailed([a, b], operation: .move, folder: folder) == "Couldn't move 2 images to Keep")
        #expect(GridText.transferFailed([a, b], operation: .copy, folder: folder) == "Couldn't copy 2 images to Keep")
        #expect(try englishOne("Couldn't move %lld images to the Trash") == "Couldn't move %lld image to the Trash")
        #expect(try englishOne("Couldn't move %lld images to %@") == "Couldn't move %lld image to %@")
        #expect(try englishOne("Couldn't copy %lld images to %@") == "Couldn't copy %lld image to %@")
    }

    @Test func confirmOneAndSeveral() throws {
        #expect(GridText.confirm([a], operation: .move, folder: folder) == "Move a.jpg to Keep?")
        #expect(GridText.confirm([a], operation: .copy, folder: folder) == "Copy a.jpg to Keep?")
        #expect(GridText.confirm([a, b], operation: .move, folder: folder) == "Move 2 images to Keep?")
        #expect(GridText.confirm([a, b], operation: .copy, folder: folder) == "Copy 2 images to Keep?")
        #expect(try englishOne("Move %lld images to %@?") == "Move %lld image to %@?")
        #expect(try englishOne("Copy %lld images to %@?") == "Copy %lld image to %@?")
    }
}
