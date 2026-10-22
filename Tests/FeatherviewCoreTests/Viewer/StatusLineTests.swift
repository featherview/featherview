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
}
