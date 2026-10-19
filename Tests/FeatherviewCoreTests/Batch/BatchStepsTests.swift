import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct BatchStepsTests {
    @Test func renameIsUsedOnlyWhenTheModeRenames() {
        var s = BatchSettings()
        #expect(!BatchStep.rename.isUsed(in: s))
        #expect(BatchStep.resize.isUsed(in: s))
        s.mode = .rename
        #expect(BatchStep.rename.isUsed(in: s))
        #expect(BatchStep.operations.allSatisfy { !$0.isUsed(in: s) })
        #expect(BatchStep.output.isUsed(in: s) && BatchStep.safety.isUsed(in: s))
    }

    @Test func safetyIsOnWhenAnyFlagIsSet() {
        var s = BatchSettings()
        #expect(!BatchStep.safety.isOn(in: s))
        s.safety.keepDates = true
        #expect(BatchStep.safety.isOn(in: s))
    }

    @Test func operationsAreOnWhenTheirSettingsAre() {
        var s = BatchSettings()
        #expect(BatchStep.operations.allSatisfy { !$0.isOn(in: s) })
        s.crop.isOn = true
        s.orientation.flipVertical = true
        #expect(BatchStep.operations.filter { $0.isOn(in: s) } == [.crop, .orientation])
    }

    @Test func resizeSummaryFollowsItsMode() {
        var s = BatchSettings()
        #expect(BatchStep.resize.summary(in: s) == "")
        s.resize.isOn = true
        s.resize.side = 2048
        #expect(BatchStep.resize.summary(in: s) == "2048")
        s.resize.mode = .widthHeight
        s.resize.width = 800
        #expect(BatchStep.resize.summary(in: s) == "800 × –")
        s.resize.mode = .megapixels
        s.resize.megapixels = 12
        #expect(BatchStep.resize.summary(in: s) == "12 MP")
        s.resize.mode = .percent
        s.resize.percentWidth = 50
        #expect(BatchStep.resize.summary(in: s) == 0.5.formatted(.percent))
        s.mode = .rename
        #expect(BatchStep.resize.summary(in: s) == "")
    }

    @Test func otherSummaries() {
        var s = BatchSettings()
        #expect(BatchStep.output.summary(in: s) == s.format.name)
        #expect(BatchStep.border.summary(in: s) == "")
        s.border.isOn = true
        #expect(BatchStep.border.summary(in: s) == "on")
        s.mode = .rename
        #expect(BatchStep.output.summary(in: s) == "Same format")
        #expect(BatchStep.rename.summary(in: s) == "{name}")
    }

    @Test func canStartNeedsFilesAFolderAndNoScan() {
        var s = BatchSettings()
        s.outputFolder = "/tmp/out"
        #expect(BatchProgress.canStart(isRunning: false, scans: 0, inputCount: 1, settings: s))
        #expect(!BatchProgress.canStart(isRunning: true, scans: 0, inputCount: 1, settings: s))
        #expect(!BatchProgress.canStart(isRunning: false, scans: 1, inputCount: 1, settings: s))
        #expect(!BatchProgress.canStart(isRunning: false, scans: 0, inputCount: 0, settings: s))
        s.outputFolder = ""
        #expect(!BatchProgress.canStart(isRunning: false, scans: 0, inputCount: 1, settings: s))
        s.mode = .rename
        #expect(BatchProgress.canStart(isRunning: false, scans: 0, inputCount: 1, settings: s))
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
