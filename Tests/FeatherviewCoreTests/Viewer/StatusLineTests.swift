import CoreGraphics
import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct StatusLineTests {
    @Test func fieldsInOrderLeavingOutWhatIsUnknown() {
        let line = StatusLine.make(pixelSize: CGSize(width: 4000, height: 3000), zoomPercent: 46, fileBytes: nil,
                                   index: 2, count: 120, page: 0, pageCount: 1, modified: nil)
        #expect(line.fields == ["\(4000.formatted()) × \(3000.formatted())", 0.46.formatted(.percent), "3 / 120"])
    }

    @Test func pageOnlyForMultiPageFiles() {
        let line = StatusLine.make(pixelSize: nil, zoomPercent: nil, fileBytes: nil, index: 0, count: 1,
                                   page: 1, pageCount: 3, modified: nil)
        #expect(line.fields == ["1 / 1", "page 2 / 3"])
    }

    @Test func fileSizeAndDateAreFormatted() {
        let date = Date(timeIntervalSince1970: 0)
        let line = StatusLine.make(pixelSize: nil, zoomPercent: nil, fileBytes: 333_509, index: 0, count: 1,
                                   page: 0, pageCount: 1, modified: date)
        #expect(line.fields.contains(ByteCountFormatter.string(fromByteCount: 333_509, countStyle: .file)))
        #expect(line.fields.contains(date.formatted(date: .abbreviated, time: .shortened)))
    }

    @Test func framesWhilePlaying() {
        let line = StatusLine.make(pixelSize: nil, zoomPercent: nil, fileBytes: nil, index: 0, count: 1,
                                   page: 0, pageCount: 1, frame: nil, frameCount: 6, modified: nil)
        #expect(line.fields == ["1 / 1", "6 frames"])
    }

    @Test func frameWhilePaused() {
        let line = StatusLine.make(pixelSize: nil, zoomPercent: nil, fileBytes: nil, index: 0, count: 1,
                                   page: 0, pageCount: 1, frame: 2, frameCount: 6, modified: nil)
        #expect(line.fields == ["1 / 1", "frame 3 / 6"])
    }

    @Test func stillHasNoFrameField() {
        let line = StatusLine.make(pixelSize: nil, zoomPercent: nil, fileBytes: nil, index: 0, count: 1,
                                   page: 0, pageCount: 1, frame: 0, frameCount: 1, modified: nil)
        #expect(line.fields == ["1 / 1"])
    }

    @Test func selectionField() {
        #expect(StatusLine.selection(count: 12, total: 120).fields == ["12 of 120 selected"])
        // Counts are formatted for the locale, as the other fields.
        #expect(StatusLine.selection(count: 1200, total: 10000).fields
                == ["\(1200.formatted()) of \(10000.formatted()) selected"])
    }

    @Test func paneFieldsInOrder() {
        let date = Date(timeIntervalSince1970: 0)
        let line = StatusLine.pane(name: "IMG_1.jpg", pixelSize: CGSize(width: 4032, height: 3024), zoomPercent: 25,
                                   fileBytes: 333_509, modified: date)
        #expect(line.fields == ["IMG_1.jpg", "\(4032.formatted()) × \(3024.formatted())", 0.25.formatted(.percent),
                                ByteCountFormatter.string(fromByteCount: 333_509, countStyle: .file),
                                date.formatted(date: .abbreviated, time: .shortened)])
        let bare = StatusLine.pane(name: "IMG_1.jpg", pixelSize: nil, zoomPercent: nil, fileBytes: nil, modified: nil)
        #expect(bare.fields == ["IMG_1.jpg"])
    }

    @Test func unsavedStatusLine() {
        // Formatted for the test's locale, as `make` does: "1,200 × 800" and "50%" under en.
        let line = StatusLine.unsaved(pixelSize: CGSize(width: 1200, height: 800), zoomPercent: 50)
        #expect(line.fields == ["\(1200.formatted()) × \(800.formatted())", 0.5.formatted(.percent)])
    }

    @Test func statusNoteIsLast() {
        let line = StatusLine.make(pixelSize: CGSize(width: 40, height: 30), zoomPercent: nil, fileBytes: nil,
                                   index: 0, count: 2, page: 0, pageCount: 1, modified: Date(timeIntervalSince1970: 0),
                                   note: "Downloading from iCloud…")
        #expect(line.fields.count == 4)
        #expect(line.fields.last == "Downloading from iCloud…")
    }
}
