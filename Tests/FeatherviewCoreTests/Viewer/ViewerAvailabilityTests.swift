import Testing
@testable import FeatherviewCore

@Suite struct ViewerAvailabilityTests {
    /// The third of five images of a listed folder, a JPEG.
    private func viewing(_ change: (inout ViewerState) -> Void = { _ in }) -> ViewerAvailability {
        var state = ViewerState(hasCurrent: true, index: 2, count: 5, hasFolder: true, desktopCanShow: true)
        change(&state)
        return ViewerAvailability(state)
    }

    @Test func plainViewerAllowsEverythingButCompareActions() {
        let a = viewing()
        #expect(a.canGoBack && a.canGoForward)
        #expect(a.canChangeFile && a.canShowGrid && a.canCompare && a.canSetDesktop)
        #expect(a.canShowInfo && a.canAdjustDate && a.hasOperationTargets && a.canShowInFinder)
        #expect(a.canSaveAs && a.canBatch && a.canCopy && a.canZoom && a.canToggleSlideshow && a.canFollow)
        #expect(!a.hasPages && !a.canSwap && !a.canShowDifference && !a.canToggleDifference && !a.canCompareSelection)
    }

    @Test func desktopPictureOnlyForFilesTheSystemShows() {
        #expect(!viewing { $0.desktopCanShow = false }.canSetDesktop)
    }

    @Test func pastEndStopEndsAtTheFolderEnds() {
        #expect(!viewing { $0.pastEnd = .stop; $0.index = 0 }.canGoBack)
        #expect(viewing { $0.pastEnd = .stop; $0.index = 0 }.canGoForward)
        #expect(!viewing { $0.pastEnd = .stop; $0.index = 4 }.canGoForward)
        #expect(viewing { $0.pastEnd = .loop; $0.index = 4 }.canGoForward)
        #expect(viewing { $0.pastEnd = .folderChooser; $0.index = 0 }.canGoBack)
    }

    @Test func holdingARemovedFileOnlyBrowsesAndZooms() {
        let a = viewing { $0.isHolding = true }
        #expect(a.canGoBack && a.canGoForward && a.canShowInFinder && a.canShowGrid && a.canZoom)
        #expect(!a.canChangeFile && !a.canCompare && !a.canSetDesktop && !a.canAdjustDate && !a.hasOperationTargets)
        #expect(!a.canSaveAs)
        #expect(!viewing { $0.isHolding = true; $0.pageCount = 3 }.hasPages)
    }

    @Test func openingTreatsTheFolderEndsAsUnknown() {
        let a = viewing { $0.isOpening = true; $0.pastEnd = .stop; $0.index = 0; $0.count = 1 }
        #expect(a.canGoBack && a.canGoForward)
        #expect(!a.canToggleSlideshow && !a.canShowGrid)
        #expect(a.canChangeFile && a.canCompare)
    }

    @Test func emptyFolderStillLeavesWithArrows() {
        let a = ViewerAvailability(ViewerState(count: 0, hasFolder: true))
        #expect(a.canGoBack && a.canGoForward && a.canFollow)
        #expect(!a.canChangeFile && !a.canShowGrid && !a.canToggleSlideshow)
        #expect(!a.canShowInfo && !a.canShowInFinder && !a.canSaveAs && !a.canZoom && !a.hasOperationTargets)
    }

    @Test func nothingOpenAllowsNothing() {
        let a = ViewerAvailability(ViewerState(count: 0))
        #expect(!a.canGoBack && !a.canGoForward && !a.canFollow && !a.canShowGrid)
        #expect(a.canBatch && a.canCopy)
    }

    @Test func gridActsOnItsSelection() {
        for selected in [0, 1, 2] {
            let a = viewing { $0.isGrid = true; $0.gridSelectionCount = selected }
            #expect(!a.canGoBack && !a.canGoForward)
            #expect(a.canShowGrid)  // T leaves the grid
            #expect(!a.canChangeFile && !a.hasPages && !a.canCompare && !a.canSetDesktop && !a.canShowInfo)
            #expect(!a.canShowInFinder && !a.canCopy && !a.canZoom && !a.canSaveAs)
            #expect(a.canToggleSlideshow)
            #expect(a.canAdjustDate == (selected > 0))
            #expect(a.hasOperationTargets == (selected > 0))
            #expect(a.canBatch == (selected > 0))
            #expect(a.canCompareSelection == (selected == 2))
        }
    }

    @Test func gridWhileOpeningStillLeaves() {
        #expect(viewing { $0.isGrid = true; $0.isOpening = true }.canShowGrid)
    }

    @Test func compareSwapsOnceTheSecondFileOpened() {
        let decoding = viewing { $0.isComparing = true }
        #expect(decoding.canSwap && !decoding.canShowDifference && !decoding.canToggleDifference)
        #expect(!decoding.canShowInfo && decoding.canCompare && decoding.canChangeFile)
        let decoded = viewing { $0.isComparing = true; $0.compareDecoded = true }
        #expect(decoded.canSwap && decoded.canShowDifference && decoded.canToggleDifference)
        let showing = viewing { $0.isComparing = true; $0.compareDecoded = true; $0.showsDifference = true }
        #expect(showing.canToggleDifference)
        #expect(!viewing { $0.isComparing = true; $0.isHolding = true }.canSwap)
    }

    @Test func compareFailedSecondFileNeitherSwapsNorDiffers() {
        let a = viewing { $0.isComparing = true; $0.compareFailed = true; $0.compareDecoded = true }
        #expect(!a.canSwap && !a.canShowDifference && !a.canToggleDifference && !a.canShowInfo)
        // Turning the difference off stays possible.
        #expect(viewing { $0.isComparing = true; $0.compareFailed = true; $0.showsDifference = true }.canToggleDifference)
    }

    @Test func slideshowStepsInItsOwnOrder() {
        let a = viewing { $0.isSlideshow = true; $0.pastEnd = .stop; $0.index = 0 }
        #expect(a.canGoBack && a.canGoForward && a.canToggleSlideshow)
        #expect(viewing { $0.isSlideshow = true; $0.isOpening = true }.canToggleSlideshow)  // to end it
        #expect(!viewing { $0.isSlideshow = true; $0.isGrid = true }.canGoForward)
    }

    @Test func unsavedPictureAsksBeforeLeavingAndHasNoFile() {
        // The covered list is put aside: the window's list is empty while it shows.
        let state = ViewerState(count: 0, hasUnsaved: true, hasFolder: true)
        let a = ViewerAvailability(state)
        #expect(a.canGoBack && a.canGoForward)  // they ask to save first
        #expect(a.canZoom && a.canSaveAs && a.canCopy)
        #expect(!a.canChangeFile && !a.hasOperationTargets && !a.canShowGrid && !a.canToggleSlideshow && !a.canCompare)
        #expect(!a.canShowInfo && !a.canShowInFinder && !a.canSetDesktop && !a.canAdjustDate)
        // With "Past the end: Stop" an empty list has no step either way, so ← / → are off then.
        var stop = state
        stop.pastEnd = .stop
        #expect(!ViewerAvailability(stop).canGoBack && !ViewerAvailability(stop).canGoForward)
    }

    @Test func pagesAndFramesStep() {
        #expect(viewing { $0.pageCount = 3 }.hasPages)
        #expect(viewing { $0.frameCount = 12 }.hasPages)
        #expect(!viewing { $0.pageCount = 1; $0.frameCount = 1 }.hasPages)
        #expect(!viewing { $0.frameCount = 12; $0.isGrid = true }.hasPages)
    }
}
