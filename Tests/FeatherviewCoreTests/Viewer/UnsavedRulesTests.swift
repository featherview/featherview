import Testing
@testable import FeatherviewCore

@Suite struct UnsavedRulesTests {
    @Test(arguments: ViewerCommand.allCases)
    func everyLeavingCommandAsksWithAnUnsavedPicture(_ command: ViewerCommand) {
        #expect(UnsavedRules.asksFirst(command, hasUnsaved: true))
    }

    @Test(arguments: ViewerCommand.allCases)
    func nothingAsksWithoutOne(_ command: ViewerCommand) {
        #expect(!UnsavedRules.asksFirst(command, hasUnsaved: false))
    }

    @Test func coversEveryWayOutOfThePicture() {
        #expect(Set(ViewerCommand.allCases) == [.next, .previous, .first, .last, .open, .close, .newFromClipboard, .quit])
    }
}
