import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct CrashReportsTests {
    /// An `.ips` report: one JSON header line, then the JSON body.
    static func ips(app: String = "Featherview", frames: Int = 3, imagePath: String = "/Applications/Featherview.app/Contents/MacOS/Featherview") -> String {
        let header = #"{"app_name":"\#(app)","name":"\#(app)","bug_type":"309","timestamp":"2026-10-23 10:11:12.00 +0200"}"#
        let crashed = (0..<frames).map { #"{"imageIndex":\#($0 % 2),"symbol":"frame\#($0)","imageOffset":\#($0)}"# }
        let body = """
            {"exception":{"type":"EXC_BAD_ACCESS","signal":"SIGSEGV"},"faultingThread":1,
             "threads":[{"frames":[{"imageIndex":0,"symbol":"idle"}]},{"frames":[\(crashed.joined(separator: ","))]}],
             "usedImages":[{"name":"Featherview","path":"\(imagePath)"},{"name":"libsystem_kernel.dylib"}]}
            """
        return header + "\n" + body
    }

    static func write(_ text: String, _ name: String, in folder: URL, date: Date) throws -> URL {
        let url = folder.appending(path: name)
        try Data(text.utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        return url
    }

    @Test func onlyOwnReportsAreOffered() throws {
        let folder = try Fixtures.makeTempDir()
        let now = Date.now
        // Another app whose report names Featherview's path, and a Featherview extension.
        _ = try Self.write(Self.ips(app: "Preview"), "Featherview-2026-10-23-101112.ips", in: folder, date: now)
        _ = try Self.write(Self.ips(app: "FeatherviewThumbnail"), "FeatherviewThumbnail-2026-10-23-101112.ips", in: folder, date: now)
        #expect(CrashReports.newest(in: folder, newerThan: nil) == nil)
        let own = try Self.write(Self.ips(), "Featherview-2026-10-22-101112.ips", in: folder, date: now.addingTimeInterval(-60))
        #expect(CrashReports.newest(in: folder, newerThan: nil)?.lastPathComponent == own.lastPathComponent)
    }

    @Test func newestAfterDateWins() throws {
        let folder = try Fixtures.makeTempDir()
        let now = Date.now
        _ = try Self.write(Self.ips(), "Featherview-1.ips", in: folder, date: now.addingTimeInterval(-300))
        let newer = try Self.write(Self.ips(), "Featherview-2.ips", in: folder, date: now.addingTimeInterval(-100))
        #expect(CrashReports.newest(in: folder, newerThan: nil)?.lastPathComponent == newer.lastPathComponent)
        #expect(CrashReports.newest(in: folder, newerThan: now.addingTimeInterval(-200))?.lastPathComponent == newer.lastPathComponent)
        #expect(CrashReports.newest(in: folder, newerThan: now.addingTimeInterval(-100)) == nil)
    }

    @Test func malformedReportIsIgnored() throws {
        let folder = try Fixtures.makeTempDir()
        let report = Self.ips()
        let truncated = String(report.prefix(report.count - 40))
        #expect(CrashReports.summary(of: Data(truncated.utf8)) == nil)
        #expect(CrashReports.summary(of: Data("not a report".utf8)) == nil)
        let older = try Self.write(report, "Featherview-1.ips", in: folder, date: .now.addingTimeInterval(-100))
        _ = try Self.write(truncated, "Featherview-2.ips", in: folder, date: .now)
        #expect(CrashReports.newest(in: folder, newerThan: nil)?.lastPathComponent == older.lastPathComponent)
    }

    @Test func summaryHasExceptionAndFrames() throws {
        let summary = try #require(CrashReports.summary(of: Data(Self.ips(frames: 20).utf8)))
        let lines = summary.components(separatedBy: "\n")
        #expect(lines.first == "EXC_BAD_ACCESS (SIGSEGV)")
        #expect(lines.count == 16)
        #expect(lines[1] == "Featherview  frame0")
        #expect(lines[2] == "libsystem_kernel.dylib  frame1")
        #expect(lines[15] == "Featherview  frame14")
    }
}
