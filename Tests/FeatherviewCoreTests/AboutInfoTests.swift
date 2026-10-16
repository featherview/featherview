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
}
