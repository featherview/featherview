import AppKit
import Testing
@testable import Featherview

/// A closed All Metadata window must not keep its view alive: the view follows the current image and
/// would read every image's metadata while browsing, for a window nobody sees.
@MainActor @Suite struct AllMetadataWindowTests {
    @Test func closingReleasesTheViewAndReopeningRestoresIt() {
        let panel = AllMetadataWindow.makePanel()   // never ordered on screen
        #expect(panel.contentViewController != nil)
        panel.close()
        #expect(panel.contentViewController == nil)
        AllMetadataWindow.attachContent(panel)
        #expect(panel.contentViewController != nil)
    }
}
