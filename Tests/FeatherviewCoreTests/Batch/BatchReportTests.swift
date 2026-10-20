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
        #expect(!beside.localizedCaseInsensitiveContains("zero"))
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
}
