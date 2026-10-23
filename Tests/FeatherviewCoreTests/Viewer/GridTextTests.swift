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

    private func info(_ url: URL, modified: Date) -> FileInfo {
        FileInfo(url: url, page: 0, pixelSize: CGSize(width: 4032, height: 3024), bytes: 2_400_000,
                 modified: modified, values: [:])
    }

    @Test func tooltipWithDetails() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let tip = GridText.tooltip(name: "a.jpg", info: info(a, modified: date), index: 2, count: 120, failed: false)
        let details = StatusLine.make(pixelSize: CGSize(width: 4032, height: 3024), zoomPercent: nil, fileBytes: 2_400_000,
                                      index: 2, count: 120, page: 0, pageCount: 1, modified: date).fields
        #expect(tip == "a.jpg\n" + details.joined(separator: "  ·  "))
        #expect(tip.contains("3 / 120"))
        #expect(tip.contains("4,032 × 3,024") || tip.contains("4032 × 3024"))
    }

    @Test func tooltipWithoutInfo() {
        #expect(GridText.tooltip(name: "a.jpg", info: nil, index: 2, count: 120, failed: false) == "a.jpg")
    }

    @Test func tooltipForFailedFile() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(GridText.tooltip(name: "a.jpg", info: info(a, modified: date), index: 2, count: 120, failed: true)
                == "Can't open a.jpg")
        #expect(GridText.tooltip(name: "a.jpg", info: nil, index: 2, count: 120, failed: true) == "Can't open a.jpg")
    }
}
