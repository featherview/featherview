import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct BatchReportTests {
    private func result(_ name: String, _ status: BatchStatus, _ message: String? = nil) -> BatchResult {
        BatchResult(input: URL(fileURLWithPath: "/in/\(name)"),
                    output: status == .converted ? URL(fileURLWithPath: "/out/\(name)") : nil,
                    status: status, message: message)
    }

    @Test func reportCountsAndFolder() {
        let results = [result("a.jpg", .converted), result("b.jpg", .failed, "Can't open b.jpg"), result("c.jpg", .converted)]
        let summary = BatchReport.summary(results: results, seconds: 72, bytesIn: 0, bytesOut: 0, folder: "/Users/x/Out")
        #expect(summary.hasPrefix("2 of 3 "))
        #expect(summary.contains("Out"))
        let beside = BatchReport.summary(results: results, seconds: 72, bytesIn: 0, bytesOut: 0, folder: "")
        #expect(beside.hasSuffix("Saved next to the originals."))
    }

    @Test func allFailedSaysZeroBytes() {
        let results = [result("a.jpg", .failed, "Can't open a.jpg")]
        let summary = BatchReport.summary(results: results, seconds: 1, bytesIn: 0, bytesOut: 0, folder: "")
        #expect(summary.hasPrefix("0 of 1 "))
        #expect(!summary.localizedCaseInsensitiveContains("zero"))
    }

    @Test func folderToShow() throws {
        let dir = try Fixtures.makeTempDir()
        let converted = [result("a.jpg", .failed), result("b.jpg", .converted)]
        // {folder} became each input's folder name: the first output's folder.
        #expect(BatchReport.folderToShow(setting: dir.path + "/{folder}", results: converted)?.path == "/out")
        #expect(BatchReport.folderToShow(setting: "", results: converted)?.path == "/out")
        #expect(BatchReport.folderToShow(setting: dir.path, results: converted)?.standardizedFileURL == dir.standardizedFileURL)
        // Never created (every file failed): nothing to show.
        let missing = dir.appendingPathComponent("never").path
        #expect(BatchReport.folderToShow(setting: missing, results: [result("a.jpg", .failed)]) == nil)
        #expect(BatchReport.folderToShow(setting: dir.path + "/{folder}", results: [result("a.jpg", .failed)]) == nil)
    }

    @Test func durationEndsWithoutPeriod() {
        // The sentence adds its own period; German abbreviations ("Sek.") would double it.
        #expect(!BatchReport.duration(3725.6, locale: Locale(identifier: "de_DE")).hasSuffix("."))
    }

    @Test func failuresByName() {
        let results = [result("a.jpg", .converted), result("b.jpg", .failed, "Can't open b.jpg"),
                       result("c.jpg", .notStarted), result("d.cr3", .failed, "Can't save d.cr3 in its own format")]
        #expect(BatchReport.failures(results) == ["Can't open b.jpg", "Can't save d.cr3 in its own format"])
    }

    private func parts(_ name: String, _ outputs: [String], _ message: String? = nil) -> BatchResult {
        BatchResult(input: URL(fileURLWithPath: "/in/\(name)"), outputs: outputs.map { URL(fileURLWithPath: "/out/\($0)") },
                    status: .converted, message: message)
    }

    @Test func summaryCountsFiles() {
        let results = [parts("a.gif", ["a-1.png", "a-2.png"]), parts("b.tiff", ["b-1.png", "b-2.png", "b-3.png"])]
        let summary = BatchReport.summary(results: results, seconds: 3, bytesIn: 0, bytesOut: 0, folder: "/Users/x/Out")
        #expect(summary.hasPrefix("2 of 2 images converted into 5 files in "))
        #expect(summary.hasSuffix("Saved to /Users/x/Out."))
        let beside = BatchReport.summary(results: results, seconds: 3, bytesIn: 0, bytesOut: 0, folder: "")
        #expect(beside.hasSuffix("Saved next to the originals."))
        // One output per input: the plain sentence.
        let plain = BatchReport.summary(results: [parts("a.jpg", ["a.png"])], seconds: 3, bytesIn: 0, bytesOut: 0, folder: "")
        #expect(plain.hasPrefix("1 of 1 images converted in "))
    }

    @Test func logLineForManyOutputs() {
        let names = (1...12).map { String(format: "loop-%02d.png", $0) }
        #expect(parts("loop.gif", names).logLine == "loop.gif → loop-01.png … loop-12.png (12 files)")
        #expect(parts("scan.tiff", ["scan-1-1.jpg", "scan-1-2.jpg"], "page 1 of 3").logLine
            == "scan.tiff → scan-1-1.jpg … scan-1-2.jpg (2 files) · page 1 of 3")
        #expect(parts("a.gif", ["a.png"]).logLine == "a.gif → a.png")
        #expect(parts("a.gif", ["a-1.png", "a-2.png"]).output?.lastPathComponent == "a-1.png")
    }

    @Test func rowStateShowsFirstOutput() {
        let state = BatchProgress.rowState(result: parts("a.gif", ["a-1.png", "a-2.png"]), index: 0, isRunning: false,
                                           isPaused: false, committed: 1)
        #expect(state == .done("a-1.png"))
    }
}
