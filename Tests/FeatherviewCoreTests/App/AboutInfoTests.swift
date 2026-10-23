import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct AboutInfoTests {
    @Test func reportTextForBugReports() {
        #expect(AboutInfo.reportText(version: "0.1.0", build: "1", macOS: "27.0.1 (26A434)", model: "Mac14,6")
                == "Featherview 0.1.0 (1)\nmacOS 27.0.1 (26A434)\nMac14,6")
    }

    @Test func modelIdentifierIsReadable() {
        #expect(AboutInfo.modelIdentifier().hasPrefix("Mac") || AboutInfo.modelIdentifier().contains(","))
    }

    @Test func bugReportOpensTheIssueFormWithTheDetailsFilledIn() {
        let url = AboutInfo.bugReportURL(version: "0.1.0", build: "1", macOS: "Version 27.0 (Build 26A434)", model: "Mac14,6")
        #expect(url.absoluteString == "https://github.com/featherview/featherview/issues/new?template=bug_report.yml"
                + "&version=0.1.0%20%281%29&macos=Version%2027.0%20%28Build%2026A434%29&mac=Mac14%2C6")
    }

    @Test func bugReportEncodingKeepsTheQueryIntact() {
        let url = AboutInfo.bugReportURL(version: "1&2=3+4", build: "#?", macOS: "ü", model: "")
        #expect(url.absoluteString.hasSuffix("&version=1%262%3D3%2B4%20%28%23%3F%29&macos=%C3%BC&mac="))
    }

    @Test func crashFieldIsInTheURL() throws {
        let url = AboutInfo.bugReportURL(version: "0.1.0", build: "1", macOS: "27.0", model: "Mac14,6",
                                         crash: "EXC_BAD_ACCESS (SIGSEGV)\nFeatherview  main")
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.first { $0.name == "crash" }?.value == "EXC_BAD_ACCESS (SIGSEGV)\nFeatherview  main")
        #expect(items.first { $0.name == "mac" }?.value == "Mac14,6")
    }

    @Test func longCrashIsCutToFitTheURL() throws {
        let crash = (0..<500).map { "SomeFramework  someLongSymbolName(with:arguments:) \($0)" }.joined(separator: "\n")
        let url = AboutInfo.bugReportURL(version: "0.1.0", build: "1", macOS: "27.0", model: "Mac14,6", crash: crash)
        #expect(url.absoluteString.count <= 8000)
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let cut = try #require(items.first { $0.name == "crash" }?.value)
        #expect(cut.count > 1000)
        #expect(crash.hasPrefix(cut + "\n"))
    }

    @Test func bugReportFieldIdsMatchTheIssueForm() throws {
        let form = try String(contentsOf: Fixtures.repo.appending(path: ".github/ISSUE_TEMPLATE/bug_report.yml"), encoding: .utf8)
        for id in AboutInfo.BugReportField.allCases {
            #expect(form.contains("id: \(id.rawValue)\n"), "missing \(id.rawValue)")
        }
    }
}
