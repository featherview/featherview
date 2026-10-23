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
    }

    @Test func extrasOrder() {
        #expect(BatchCard.extras == [.frames, .crop, .orientation, .colour, .filters, .canvas, .border, .text, .watermark,
                                     .tiles, .dateTaken])
    }

    @Test func appliedLineListsStepsInProcessingOrder() {
        var s = BatchSettings()
        s.dateTaken.isOn = true
        s.tiles.isOn = true
        s.watermark.isOn = true
        s.resize.isOn = true
        s.crop.isOn = true
        s.frames.isOn = true
        #expect(BatchCard.appliedLine(s) == "Applied: frames and pages → crop → size → watermark → tiles → date taken")
    }

    @Test func tilesSummary() {
        var s = BatchSettings()
        s.tiles.columns = 3
        s.tiles.rows = 2
        #expect(BatchCard.tiles.summary(in: s) == "3 × 2")
        s.tiles.overlap = 20
        #expect(BatchCard.tiles.summary(in: s) == "3 × 2, overlap 20 px")
    }

    @Test func dateSummaries() {
        var s = BatchSettings()
        #expect(BatchCard.frames.summary(in: s) == "Every frame or page")
        s.dateTaken.mode = .set
        #expect(BatchCard.dateTaken.summary(in: s) == "Choose a date")
        s.dateTaken.setTo = "2024:07:01 18:30:00"
        let set = BatchCard.dateTaken.summary(in: s)
        #expect(set.hasPrefix("Set to") && set.contains("2024"))
        s.dateTaken.mode = .shift
        #expect(BatchCard.dateTaken.summary(in: s) == "No shift")
        s.dateTaken.shiftSeconds = -5400
        #expect(BatchCard.dateTaken.summary(in: s).hasPrefix("Earlier by"))
        s.dateTaken.shiftSeconds = 90
        #expect(BatchCard.dateTaken.summary(in: s).hasPrefix("Later by"))
        s.dateTaken.shiftSeconds = .min  // a decoded preset may hold any Int
        #expect(BatchCard.dateTaken.summary(in: s).hasPrefix("Earlier by"))
    }

    @Test(arguments: BatchCard.extras) func extraFollowsItsStepSwitch(card: BatchCard) throws {
        let switches: [BatchCard: KeyPath<BatchSettings, Bool>] = [
            .frames: \.frames.isOn, .crop: \.crop.isOn, .orientation: \.orientation.isOn, .colour: \.colour.isOn,
            .filters: \.filters.isOn, .canvas: \.canvas.isOn, .border: \.border.isOn, .text: \.text.isOn,
            .watermark: \.watermark.isOn, .tiles: \.tiles.isOn, .dateTaken: \.dateTaken.isOn,
        ]
        let isOn = try #require(switches[card])
        var s = BatchSettings()
        #expect(BatchCard.extras.allSatisfy { !$0.isAdded(in: s) })
        card.setAdded(true, in: &s)
        #expect(s[keyPath: isOn])
        #expect(BatchCard.extras.filter { $0.isAdded(in: s) } == [card])
        card.setAdded(false, in: &s)
        #expect(!s[keyPath: isOn] && !card.isAdded(in: s))
    }

    @Test func formatSummaryJPEGQuality() {
        var s = BatchSettings()
        s.formatID = "jpg"
        s.options.quality = 85
        #expect(BatchCard.format.summary(in: s) == "JPEG · 85")
        s.formatID = "png"
        #expect(BatchCard.format.summary(in: s) == "PNG")
    }

    @Test func formatSummaryShowsTargetSizeInsteadOfQuality() {
        var s = BatchSettings()
        s.formatID = "jpg"
        s.options.quality = 80
        s.options.targetSizeKB = 500
        #expect(BatchCard.format.summary(in: s) == "JPEG · 500 KB")
        s.options.targetSizeKB = 0
        #expect(BatchCard.format.summary(in: s) == "JPEG · 80")
    }

    @Test func canvasAndCropSummariesWritePixelsUngrouped() {
        var s = BatchSettings()
        s.canvas.method = .totalSize
        s.canvas.width = 1920
        s.canvas.height = 1080
        #expect(BatchCard.canvas.summary(in: s) == "1920 × 1080")
        s.crop.width = 3000
        s.crop.height = 2000
        #expect(BatchCard.crop.summary(in: s) == "3000 × 2000")
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
        s.resize.keepAspect = false
        s.resize.percentHeight = 25
        #expect(BatchCard.size.summary(in: s) == "\(0.5.formatted(.percent)) × \(0.25.formatted(.percent))")
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
        #expect(BatchCard.watermark.summary(in: s) == "Bottom right · \(0.6.formatted(.percent))")
        #expect(BatchCard.extras.allSatisfy { !$0.summary(in: BatchSettings()).isEmpty })
    }

    @Test func appliedLineNilWhenNothingOn() {
        var s = BatchSettings()
        s.changeFormat = false
        s.renamePattern = "x-{n}"
        #expect(BatchCard.appliedLine(s) == nil)
    }

    /// A batch starts with files, no scan running, and an absolute output folder or none (next to the originals).
    @Test(arguments: [
        (running: false, scans: 0, files: 1, folder: "/tmp/out", changeFormat: true, canStart: true),
        (running: true, scans: 0, files: 1, folder: "/tmp/out", changeFormat: true, canStart: false),
        (running: false, scans: 1, files: 1, folder: "/tmp/out", changeFormat: true, canStart: false),
        (running: false, scans: 0, files: 0, folder: "/tmp/out", changeFormat: true, canStart: false),
        (running: false, scans: 0, files: 1, folder: "out", changeFormat: true, canStart: false),
        (running: false, scans: 0, files: 1, folder: "~/Desktop/Out", changeFormat: true, canStart: true),
        (running: false, scans: 0, files: 1, folder: "", changeFormat: true, canStart: true),
        (running: false, scans: 0, files: 1, folder: "", changeFormat: false, canStart: true),
        (running: false, scans: 0, files: 1, folder: "relative", changeFormat: false, canStart: false),
    ])
    func canStartNeedsFilesNoScanAndAnAbsoluteOrEmptyFolder(
        running: Bool, scans: Int, files: Int, folder: String, changeFormat: Bool, canStart: Bool
    ) {
        var s = BatchSettings()
        s.outputFolder = folder
        s.changeFormat = changeFormat
        #expect(BatchProgress.canStart(isRunning: running, scans: scans, inputCount: files, settings: s) == canStart)
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
