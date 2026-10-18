import FeatherviewCore
import Testing

/// Back and forward at a folder's ends (docs/DESIGN.md "Toolbar › Disabled", with the chooser correction).
struct PastEndBehaviorTests {
    @Test func stopDisablesAtTheEnds() {
        #expect(!PastEndBehavior.stop.canStep(forward: false, index: 0, count: 4))
        #expect(PastEndBehavior.stop.canStep(forward: true, index: 0, count: 4))
        #expect(PastEndBehavior.stop.canStep(forward: false, index: 3, count: 4))
        #expect(!PastEndBehavior.stop.canStep(forward: true, index: 3, count: 4))
    }

    @Test func stopWithNoImagesCantStep() {
        #expect(!PastEndBehavior.stop.canStep(forward: true, index: 0, count: 0))
        #expect(!PastEndBehavior.stop.canStep(forward: false, index: 0, count: 0))
    }

    /// Past the end the chooser opens, or the folder starts again: the buttons stay enabled.
    @Test(arguments: [PastEndBehavior.folderChooser, .loop])
    func chooserAndLoopKeepBothEnabled(_ behavior: PastEndBehavior) {
        #expect(behavior.canStep(forward: true, index: 3, count: 4))
        #expect(behavior.canStep(forward: false, index: 0, count: 4))
    }
}
