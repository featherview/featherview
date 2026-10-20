import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct BatchStepsTests {
    @Test func coreCardsAlwaysAdded() {
        var s = BatchSettings()
        #expect(BatchCard.core.allSatisfy { $0.isAdded(in: s) })
        BatchCard.size.setAdded(false, in: &s)
        BatchCard.name.setAdded(false, in: &s)
        #expect(BatchCard.core.allSatisfy { $0.isAdded(in: s) })
        #expect(BatchCard.core.map(\.number) == [2, 3, 4])
        #expect(BatchCard.extras.allSatisfy { $0.number == nil })
        #expect(BatchCard.extras == [.crop, .orientation, .colour, .filters, .canvas, .border, .text, .watermark])
    }

    @Test func extrasFollowTheirSwitch() {
        var s = BatchSettings()
        #expect(BatchCard.extras.allSatisfy { !$0.isAdded(in: s) })
        BatchCard.orientation.setAdded(true, in: &s)
        #expect(s.orientation.isOn)
        #expect(BatchCard.orientation.isAdded(in: s))
        BatchCard.watermark.setAdded(true, in: &s)
        BatchCard.watermark.setAdded(false, in: &s)
        #expect(!s.watermark.isOn)
        #expect(BatchCard.extras.filter { $0.isAdded(in: s) } == [.orientation])
    }

    @Test func formatSummaryJPEGQuality() {
        var s = BatchSettings()
        s.formatID = "jpg"
        s.options.quality = 85
        #expect(BatchCard.format.summary(in: s) == "JPEG · 85")
        s.formatID = "png"
        #expect(BatchCard.format.summary(in: s) == "PNG")
    }

    @Test func keepFormatSummarySaysCopied() {
        var s = BatchSettings()
        s.changeFormat = false
        #expect(BatchCard.format.summary(in: s) == "Keep format · copied unchanged")
    }

    @Test func keepFormatSummarySaysSavedAgain() {
        var s = BatchSettings()
        s.changeFormat = false
        s.resize.isOn = true
        #expect(BatchCard.format.summary(in: s) == "Keep format · saved again")
    }

    @Test func sizeSummaryOffIsOriginal() {
        var s = BatchSettings()
        #expect(BatchCard.size.summary(in: s) == "Original size")
        s.resize.isOn = true
        s.resize.side = 2048
        #expect(BatchCard.size.summary(in: s) == "Longest side 2048")
        s.resize.mode = .widthHeight
        s.resize.width = 2000
        #expect(BatchCard.size.summary(in: s) == "2000 × –")
        s.resize.mode = .megapixels
        s.resize.megapixels = 12
        #expect(BatchCard.size.summary(in: s) == "12 MP")
        s.resize.mode = .percent
        s.resize.percentWidth = 50
        #expect(BatchCard.size.summary(in: s) == 0.5.formatted(.percent))
    }

    @Test func nameSummaryNextToOriginals() {
        var s = BatchSettings()
        s.renamePattern = "trip-{n:3}"
        #expect(BatchCard.name.summary(in: s) == "trip-{n:3} · Next to the originals")
        s.outputFolder = "/Users/x/Desktop/Out"
        #expect(BatchCard.name.summary(in: s) == "trip-{n:3} · Out")
    }

    @Test func extraSummariesDescribeWhatIsSet() {
        var s = BatchSettings()
        #expect(BatchCard.colour.summary(in: s) == "On")
        s.colour.brightness = 10
        #expect(BatchCard.colour.summary(in: s) == "Brightness +10")
        s.colour = ColourSettings()
        s.colour.greyscale = true
        #expect(BatchCard.colour.summary(in: s) == "Greyscale")
        s.watermark.position = .bottomRight
        s.watermark.opacity = 0.6
        #expect(BatchCard.watermark.summary(in: s) == "Bottom right, \(0.6.formatted(.percent))")
        #expect(BatchCard.extras.allSatisfy { !$0.summary(in: BatchSettings()).isEmpty })
    }

    @Test func appliedLineInProcessingOrder() throws {
        var s = BatchSettings()
        s.watermark.isOn = true
        s.resize.isOn = true
        s.crop.isOn = true
        let line = try #require(BatchCard.appliedLine(s))
        let crop = try #require(line.range(of: "crop"))
        let size = try #require(line.range(of: "size"))
        let watermark = try #require(line.range(of: "watermark"))
        #expect(crop.upperBound <= size.lowerBound)
        #expect(size.upperBound <= watermark.lowerBound)
    }

    @Test func appliedLineNilWhenNothingOn() {
        var s = BatchSettings()
        s.changeFormat = false
        s.renamePattern = "x-{n}"
        #expect(BatchCard.appliedLine(s) == nil)
    }

    @Test func canStartNeedsFilesAFolderAndNoScan() {
        var s = BatchSettings()
        s.outputFolder = "/tmp/out"
        #expect(BatchProgress.canStart(isRunning: false, scans: 0, inputCount: 1, settings: s))
        #expect(!BatchProgress.canStart(isRunning: true, scans: 0, inputCount: 1, settings: s))
        #expect(!BatchProgress.canStart(isRunning: false, scans: 1, inputCount: 1, settings: s))
        #expect(!BatchProgress.canStart(isRunning: false, scans: 0, inputCount: 0, settings: s))
        s.outputFolder = ""  // next to the originals
    }

    @Test func canStartNeedsAnAbsoluteFolder() {
        var s = BatchSettings()
        s.outputFolder = "out"
        #expect(!BatchProgress.canStart(isRunning: false, scans: 0, inputCount: 1, settings: s))
        s.outputFolder = "~/Desktop/Out"
        #expect(BatchProgress.canStart(isRunning: false, scans: 0, inputCount: 1, settings: s))
    }

    @Test func secondsLeftTakesPausesOut() {
        #expect(BatchProgress.secondsLeft(elapsed: 10, paused: 4, done: 3, total: 6) == 6)
        #expect(BatchProgress.secondsLeft(elapsed: 10, paused: 0, done: 2, total: 6) == nil)
        #expect(BatchProgress.secondsLeft(elapsed: 10, paused: 0, done: 6, total: 6) == nil)
    }

    @Test func rowStates() {
        let url = URL(fileURLWithPath: "/a.jpg")
        let done = BatchResult(input: url, output: URL(fileURLWithPath: "/out/a.heic"), status: .converted, message: nil)
        let failed = BatchResult(input: url, output: nil, status: .failed, message: "Can't open a.jpg")
        let notStarted = BatchResult(input: url, output: nil, status: .notStarted, message: nil)
        func state(_ r: BatchResult?, _ i: Int?, running: Bool = true, paused: Bool = false) -> BatchRowState? {
            BatchProgress.rowState(result: r, index: i, isRunning: running, isPaused: paused, committed: 2, workers: 3)
        }
        #expect(state(done, 0) == .done("a.heic"))
        #expect(state(failed, 0) == .failed("Can't open a.jpg"))
        #expect(state(notStarted, 0) == nil)
        #expect(state(nil, 4) == .working)
        #expect(state(nil, 5) == .waiting)
        #expect(state(nil, 4, paused: true) == .waiting)
        #expect(state(nil, nil) == .waiting)
        #expect(state(nil, 4, running: false) == nil)
    }
}
