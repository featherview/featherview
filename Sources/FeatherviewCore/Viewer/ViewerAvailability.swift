/// What a viewer window shows at one moment, built by the window each time any of it changes.
public struct ViewerState: Sendable {
    public var hasCurrent: Bool
    /// The current file was removed (trashed, moved) and still shows.
    public var isHolding: Bool
    /// The folder is being listed: the list holds only the opened file.
    public var isOpening: Bool
    public var index: Int
    public var count: Int
    public var pageCount: Int
    public var frameCount: Int
    public var isGrid: Bool
    public var gridSelectionCount: Int
    public var isComparing: Bool
    /// Pane 2's file can't be read.
    public var compareFailed: Bool
    /// Both compared pictures are decoded.
    public var compareDecoded: Bool
    public var showsDifference: Bool
    public var isSlideshow: Bool
    /// A picture from the clipboard covers the list, not saved yet.
    public var hasUnsaved: Bool
    /// A folder is known, even an empty one.
    public var hasFolder: Bool
    /// The setting "Past the end of a folder".
    public var pastEnd: PastEndBehavior
    /// The current file is one the system can set as its desktop picture.
    public var desktopCanShow: Bool

    public init(hasCurrent: Bool = false, isHolding: Bool = false, isOpening: Bool = false,
                index: Int = 0, count: Int = 1, pageCount: Int = 1, frameCount: Int = 1,
                isGrid: Bool = false, gridSelectionCount: Int = 0,
                isComparing: Bool = false, compareFailed: Bool = false, compareDecoded: Bool = false,
                showsDifference: Bool = false, isSlideshow: Bool = false, hasUnsaved: Bool = false,
                hasFolder: Bool = false, pastEnd: PastEndBehavior = .folderChooser, desktopCanShow: Bool = false) {
        self.hasCurrent = hasCurrent
        self.isHolding = isHolding
        self.isOpening = isOpening
        self.index = index
        self.count = count
        self.pageCount = pageCount
        self.frameCount = frameCount
        self.isGrid = isGrid
        self.gridSelectionCount = gridSelectionCount
        self.isComparing = isComparing
        self.compareFailed = compareFailed
        self.compareDecoded = compareDecoded
        self.showsDifference = showsDifference
        self.isSlideshow = isSlideshow
        self.hasUnsaved = hasUnsaved
        self.hasFolder = hasFolder
        self.pastEnd = pastEnd
        self.desktopCanShow = desktopCanShow
    }
}

/// When toolbar buttons and menu items can act; the methods they call guard on the same.
public struct ViewerAvailability: Equatable, Sendable {
    /// ← / → work with no images too, as long as a folder is known (the chooser leaves it);
    /// with "Past the end: Stop" not past the folder's ends.
    public var canGoBack = false
    public var canGoForward = false
    /// Rotate, Trash, F2, F7 / F8: not on a held (already removed) image.
    public var canChangeFile = false
    public var hasPages = false
    /// T: the window has a list to show as thumbnails (also while the grid shows, to leave it).
    public var canShowGrid = false
    /// File › Compare With…: an image shows (not the grid).
    public var canCompare = false
    /// X: comparing, and pane 2's file opened.
    public var canSwap = false
    /// D: comparing, both pictures decoded, pane 2's file opened.
    public var canShowDifference = false
    /// Set as Desktop Picture: a file the system itself can show.
    public var canSetDesktop = false
    /// I, the menu item and the toolbar button: an image is shown, not the grid or two compared.
    public var canShowInfo = false
    /// Adjust Date Taken…: the viewed image, or the grid's selection.
    public var canAdjustDate = false
    /// Move, Copy, Trash from the File menu: the grid's selection, else the viewed image (not a held one).
    public var hasOperationTargets = false
    /// Show in Finder, Open With: the viewed image; in the grid they'd act on the one viewed before T.
    public var canShowInFinder = false
    /// Save As…: a file that is still there, or an unsaved picture.
    public var canSaveAs = false
    /// Batch Convert…: in the grid only with a selection, which joins the batch's list.
    public var canBatch = false
    /// Copy: the grid has no image to copy.
    public var canCopy = false
    /// Zoom to Fit, Width, Height, Actual Size, Zoom In / Out: a picture shows, not the grid (+ and − size its cells).
    public var canZoom = false
    /// Compare in the grid: exactly two cells selected.
    public var canCompareSelection = false
    /// D: shows the difference, or hides it again.
    public var canToggleDifference = false
    /// W, ⇧A: start a slideshow, or end the one playing.
    public var canToggleSlideshow = false
    /// Follow New Files: a folder is known.
    public var canFollow = false

    public init() {}

    public init(_ s: ViewerState) {
        // While the folder is listed its ends aren't known yet.
        let pastEnd = s.isOpening ? .loop : s.pastEnd
        // In the grid → moves between cells, not images (Decision 8).
        let canBrowse = s.hasFolder && !s.isGrid
        // A slideshow steps in its play order, which has no Finder ends.
        canGoBack = canBrowse && (s.isSlideshow || pastEnd.canStep(forward: false, index: s.index, count: s.count))
        canGoForward = canBrowse && (s.isSlideshow || pastEnd.canStep(forward: true, index: s.index, count: s.count))
        // W, ⇧A: an image shows and its folder is listed.
        let canStartSlideshow = Slideshow.mayStart(hasCurrent: s.hasCurrent, isOpening: s.isOpening)
        // Zoom: a file's image or an unsaved one.
        let hasPicture = s.hasCurrent || s.hasUnsaved
        // In the grid these act on one viewed image (Decision 13).
        canChangeFile = s.hasCurrent && !s.isHolding && !s.isGrid
        hasPages = (s.pageCount > 1 || s.frameCount > 1) && !s.isHolding && !s.isGrid
        canShowGrid = s.isGrid || (s.count > 0 && !s.isOpening)
        canCompare = canChangeFile
        canSwap = s.isComparing && !s.compareFailed && s.hasCurrent && !s.isHolding
        canShowDifference = s.isComparing && !s.compareFailed && s.compareDecoded
        canSetDesktop = canChangeFile && s.desktopCanShow
        canShowInfo = s.hasCurrent && !s.isGrid && !s.isComparing
        canAdjustDate = s.isGrid ? s.gridSelectionCount > 0 : canChangeFile
        hasOperationTargets = canAdjustDate
        canShowInFinder = s.hasCurrent && !s.isGrid
        canSaveAs = canChangeFile || s.hasUnsaved
        canBatch = !s.isGrid || s.gridSelectionCount > 0
        canCopy = !s.isGrid
        canZoom = hasPicture && !s.isGrid
        canCompareSelection = s.isGrid && s.gridSelectionCount == 2
        canToggleDifference = canShowDifference || s.showsDifference
        canToggleSlideshow = s.isSlideshow || canStartSlideshow
        canFollow = s.hasFolder
    }
}
