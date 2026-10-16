import Foundation
import Testing
@testable import FeatherviewCore

@MainActor @Suite struct ViewerWindowsTests {
    let a = URL(fileURLWithPath: "/tmp/a.jpg")
    let b = URL(fileURLWithPath: "/tmp/b.jpg")

    @Test func requestsBeforeAnyWindowAreSentWhenOneInstallsTheOpeners() {
        // Launch with only the Batch window restored: Finder's files arrive before any opener exists.
        let windows = ViewerWindows()
        windows.revealMain()
        windows.openExtra(a)
        windows.openExtra(b)
        var reveals = 0
        var extras: [URL] = []
        windows.install(revealMain: { reveals += 1 }, openExtra: { extras.append($0.url) })
        #expect(reveals == 1)
        #expect(extras == [a, b])
        windows.install(revealMain: { reveals += 1 }, openExtra: { extras.append($0.url) })
        #expect(reveals == 1)  // sent once, not again by the next window
        #expect(extras == [a, b])
    }

    @Test func requestsAfterInstallGoStraightThrough() {
        let windows = ViewerWindows()
        var reveals = 0
        var extras: [URL] = []
        windows.install(revealMain: { reveals += 1 }, openExtra: { extras.append($0.url) })
        windows.openExtra(a)
        windows.revealMain()
        #expect(extras == [a])
        #expect(reveals == 1)
    }

    @Test func theSameFileTwiceGetsTwoWindows() throws {
        // SwiftUI only raises a window whose value is already open.
        let first = ExtraWindow(url: a)
        let second = ExtraWindow(url: a)
        #expect(first != second)
        // Restored at launch from the encoded value.
        let decoded = try JSONDecoder().decode(ExtraWindow.self, from: JSONEncoder().encode(first))
        #expect(decoded == first)
        #expect(decoded.url == a)
    }
}
