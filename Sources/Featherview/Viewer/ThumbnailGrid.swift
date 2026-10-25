import AppKit
import FeatherviewCore
import os
import Quartz
import SwiftUI

/// The thumbnail grid (T): the viewer's list as cells, in its order, in place of the canvas. Visible cells ask the
/// model for their pictures; every change of the visible range refocuses the grid's decode queue, so a fling leaves
/// no decodes behind it.
struct ThumbnailGrid: NSViewRepresentable {
    let model: ViewerModel
    let urls: [URL]
    /// The slider's size in points: the target the columns come nearest to.
    let cellSize: Double
    /// The toolbar's and strip's room, as the canvas has; the grid scrolls under both.
    let insets: CanvasInsets
    /// False while the F7 / F8 panel takes the keys; the grid takes them back when it closes.
    let hasKeyboard: Bool
    /// The viewer's grid keys; Home and End are the grid's own.
    let onKey: (GridKey) -> Bool

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> NSScrollView {
        let coordinator = context.coordinator
        let layout = NSCollectionViewFlowLayout()
        layout.minimumInteritemSpacing = Theme.gridGap
        layout.minimumLineSpacing = Theme.gridGap
        let grid = GridCollectionView()
        grid.collectionViewLayout = layout
        grid.isSelectable = true
        grid.allowsMultipleSelection = true
        grid.backgroundColors = [.clear]
        grid.autoresizingMask = [.width]
        grid.register(ThumbnailCell.self, forItemWithIdentifier: ThumbnailCell.identifier)
        grid.dataSource = coordinator
        grid.delegate = coordinator
        grid.onKey = { [weak coordinator] in coordinator?.key($0) ?? false }
        grid.onOpen = { [weak model] in model?.viewFromGrid($0) }
        grid.onClick = { [weak coordinator] in coordinator?.clicked($0, $1) }
        grid.onWillLayout = { [weak coordinator] in coordinator?.applyColumns() }
        grid.onLayout = { [weak coordinator] in coordinator?.laidOut() }
        grid.onScaleChange = { [weak coordinator] in coordinator?.scaleChanged() }
        grid.onMenu = { [weak coordinator] in coordinator?.menu(at: $0) }
        grid.onPinch = { [weak model] steps in
            for _ in 0..<abs(steps) { model?.stepThumbnails(larger: steps > 0) }
        }
        let scroll = NSScrollView()
        scroll.documentView = grid
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentView.postsBoundsChangedNotifications = true
        scroll.contentView.postsFrameChangedNotifications = true
        for name in [NSView.boundsDidChangeNotification, NSView.frameDidChangeNotification] {
            NotificationCenter.default.addObserver(coordinator, selector: #selector(Coordinator.visibleRangeMayHaveChanged),
                                                   name: name, object: scroll.contentView)
        }
        coordinator.grid = grid
        coordinator.update(self)
        ViewerModel.afterFrame { [weak model] in model?.gridDrawn() }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) { context.coordinator.update(self) }

    @MainActor final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate {
        let model: ViewerModel
        weak var grid: GridCollectionView?
        private var onKey: (GridKey) -> Bool = { _ in false }
        private var urls: [URL] = []
        /// The slider's size; `cellSize` is what filling the width makes of it.
        private var target = 0.0
        private var cellSize = 0.0
        private var insets: CanvasInsets?
        private var hasKeyboard = true
        /// The cell to scroll to the middle once the grid has its width (entering).
        private var pendingScroll: Int?
        /// ⇧-click selects from this file's cell; a file, so it follows its cell when the list changes.
        private var anchor: URL?
        private var visible: Range<Int>?
        /// The way the user last scrolled: cells ahead of it are decoded first.
        private var forward = true
        /// What the queue's window holds now: a cell outside it asks for a refocus first.
        private var wanted: Set<URL> = []
        private var failed: Set<URL> = []
        /// The running `GridFill` signpost: visible cells still without a picture or the can't-open look.
        private var fill: (state: OSSignpostIntervalState, started: ContinuousClock.Instant, cells: Int, pending: Set<URL>)?
        /// The range and decode side the running (or last) `GridFill` measures.
        private var fillKey: (range: Range<Int>, side: Int)?
        private static let log = Logger(subsystem: "net.mynetx.featherview", category: "grid")

        init(model: ViewerModel) { self.model = model }

        /// The decode side for the current cell size and screen (`ThumbnailSize.decodeSide`).
        var side: Int { ThumbnailSize.decodeSide(points: cellSize, scale: Double(grid?.window?.backingScaleFactor ?? 2)) }

        func update(_ view: ThumbnailGrid) {
            onKey = view.onKey
            guard let grid, let scroll = grid.enclosingScrollView,
                  let layout = grid.collectionViewLayout as? NSCollectionViewFlowLayout else { return }
            if insets != view.insets {
                insets = view.insets
                scroll.contentInsets = NSEdgeInsets(top: view.insets.top, left: 0, bottom: view.insets.bottom, right: 0)
                // Full screen has no bars: the cells keep the window edge's margin.
                let top = max(view.insets.top, CanvasInsets.side) - view.insets.top
                let bottom = max(view.insets.bottom, CanvasInsets.side) - view.insets.bottom
                layout.sectionInset = NSEdgeInsets(top: top, left: CanvasInsets.side, bottom: bottom, right: CanvasInsets.side)
            }
            if target != view.cellSize {
                target = view.cellSize
                applyColumns()
            }
            if urls != view.urls { reload(view.urls) }
            if hasKeyboard != view.hasKeyboard {
                hasKeyboard = view.hasKeyboard
                if hasKeyboard { grid.window?.makeFirstResponder(grid) }
            }
        }

        /// The list changed (or the grid opened): every cell again, the selection kept by URL.
        private func reload(_ new: [URL]) {
            guard let grid else { return }
            let entering = urls.isEmpty
            // The model's: the grid's own, or the cell after a removal (`GridSelection.focusAfterRemoval`).
            let selected = Set(model.gridSelection)
            urls = new
            grid.urls = new
            grid.reloadData()
            grid.selectionIndexPaths = Self.paths(GridSelection.indices(of: selected, in: new))
            if entering, let focus = model.gridFocus {
                pendingScroll = new.firstIndex(of: focus)
                anchor = focus
            }
            syncSelection(focus: nil)
            fillKey = nil
            refocus(force: true)
        }

        private static func paths<S: Sequence<Int>>(_ items: S) -> Set<IndexPath> {
            Set(items.map { IndexPath(item: $0, section: 0) })
        }

        /// Whole columns fill the room between the side margins (spec "Size"). Runs before each layout pass, so the
        /// pass already has the final cell size.
        func applyColumns() {
            guard let grid, let scroll = grid.enclosingScrollView,
                  let layout = grid.collectionViewLayout as? NSCollectionViewFlowLayout else { return }
            let width = scroll.contentView.bounds.width - 2 * CanvasInsets.side
            model.gridWidth = width
            let cell = ThumbnailSize.columns(width: width, target: target, gap: Theme.gridGap).cell
            guard cell != cellSize else { return }
            let oldSide = side
            cellSize = cell
            layout.itemSize = NSSize(width: cell, height: cell + Theme.gridNameGap + Theme.gridNameHeight)
            if side != oldSide { refocus(force: true) }
        }

        func laidOut() {
            if let index = pendingScroll, let grid, grid.bounds.width > 0, index < urls.count {
                pendingScroll = nil
                grid.scrollToItems(at: [IndexPath(item: index, section: 0)], scrollPosition: .centeredVertically)
            }
            refocus(force: false)
        }

        // MARK: Decode order

        /// Another screen's scale: another decode side.
        func scaleChanged() { refocus(force: true) }

        @objc func visibleRangeMayHaveChanged() { refocus(force: false) }

        /// Focuses the queue on the visible cells, then those ahead, when the visible range changed; `force`: also when
        /// it didn't (a new list or decode side, or a cell the layout made before the bounds notification came).
        private func refocus(force: Bool) {
            guard let grid, let clip = grid.enclosingScrollView?.contentView, let layout = grid.collectionViewLayout else { return }
            let items = layout.layoutAttributesForElements(in: clip.documentVisibleRect).compactMap { $0.indexPath?.item }
            guard let low = items.min(), let high = items.max(), high < urls.count else { return }
            let range = low..<high + 1
            guard force || range != visible else { return }
            if let visible, range != visible { forward = range.lowerBound >= visible.lowerBound }
            visible = range
            let order = GridWindow.wanted(visible: range, count: urls.count, forward: forward).map { urls[$0] }
            wanted = Set(order)
            model.focusThumbnails(order)
            let side = side
            model.prefetchThumbnails(order.dropFirst(range.count).filter { model.shownThumbnail($0, side: side) == nil }, side: side)
            if fillKey?.range != range || fillKey?.side != side { startFill(range, side: side) }
            // Cells whose decode a refocus dropped, or that need a larger picture, ask again.
            for case let cell as ThumbnailCell in grid.visibleItems() { cell.load() }
        }

        /// A cell's picture; refocuses first when its cell isn't in the queue's window yet (the layout made it
        /// before the bounds notification came), so its decode isn't dropped at once. A cell outside the window
        /// even then decodes nothing: it is asked again once it shows.
        func picture(for url: URL, side: Int) async throws -> CGImage {
            if !wanted.contains(url) {
                refocus(force: false)
                // Still not wanted: a cell laid out before the grid scrolled to the current image, off screen now.
                guard wanted.contains(url) else { throw CancellationError() }
            }
            return try await model.thumbnail(url, side: side)
        }

        // MARK: GridFill

        private func startFill(_ range: Range<Int>, side: Int) {
            if let fill { Signposts.poster.endInterval("GridFill", fill.state, "superseded") }
            fill = nil
            fillKey = (range, side)
            let pending = Set(range.map { urls[$0] }.filter { !failed.contains($0) && model.shownThumbnail($0, side: side) == nil })
            guard !pending.isEmpty else { return }
            fill = (Signposts.poster.beginInterval("GridFill", id: Signposts.poster.makeSignpostID()), .now, range.count, pending)
        }

        /// A cell has its picture, or the can't-open look.
        func resolved(_ url: URL, failed: Bool) {
            if failed { self.failed.insert(url) }
            guard var fill, fill.pending.remove(url) != nil else { return }
            guard fill.pending.isEmpty else { return self.fill = fill }
            self.fill = nil
            Signposts.poster.endInterval("GridFill", fill.state)
            let ms = Int(fill.started.duration(to: .now).milliseconds)
            Self.log.debug("grid fill \(fill.cells) cells: \(ms) ms")
        }

        func isFailed(_ url: URL) -> Bool { failed.contains(url) }

        // MARK: Selection and keys

        /// Click, ⇧-click range, ⌘-click toggle (Decision 10); the clicked cell takes the focus.
        func clicked(_ index: Int, _ flags: NSEvent.ModifierFlags) {
            guard let grid else { return }
            let click = GridSelection.click(index, in: urls, selection: Set(grid.selectionIndexPaths.map(\.item)), anchor: anchor,
                                            shift: flags.contains(.shift), command: flags.contains(.command))
            anchor = click.anchor
            grid.selectionIndexPaths = Self.paths(click.selection)
            syncSelection(focus: index)
        }

        func key(_ key: GridKey) -> Bool {
            switch key {
            case .first: select(0)
            case .last: select(urls.count - 1)
            case .quickLook: grid?.toggleQuickLook()
            default: return onKey(key)
            }
            return true
        }

        // MARK: Right-click menu

        /// The selection's menu (spec "Right-click"): a cell outside the selection becomes it first; the clicked cell
        /// takes the focus, so Show Image views it.
        func menu(at index: Int) -> NSMenu {
            if let grid {
                let selection = Set(grid.selectionIndexPaths.map(\.item))
                let next = GridSelection.contextClick(index, selection: selection)
                if next != selection {
                    anchor = urls[index]
                    grid.selectionIndexPaths = Self.paths(next)
                }
                syncSelection(focus: index)
            }
            let menu = NSMenu()
            let groups: [[(String, Selector)]] = [
                [(String(localized: "Show Image"), #selector(menuView))],
                [(String(localized: "Copy"), #selector(menuCopy)), (String(localized: "Show in Finder"), #selector(menuShowInFinder))],
                [(String(localized: "Move to Folder…"), #selector(menuMove)), (String(localized: "Copy to Folder…"), #selector(menuCopyTo)),
                 (String(localized: "Batch Convert…"), #selector(menuBatch))],
                [(String(localized: "Move to Trash"), #selector(menuTrash))],
            ]
            for group in groups {
                if !menu.items.isEmpty { menu.addItem(.separator()) }
                for (title, action) in group {
                    let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
                    item.target = self
                    menu.addItem(item)
                }
            }
            return menu
        }

        @objc private func menuView() { _ = onKey(.view) }
        @objc private func menuCopy() { model.copyGridSelection() }
        @objc private func menuShowInFinder() { model.showInFinder() }
        @objc private func menuMove() { _ = onKey(.move) }
        @objc private func menuCopyTo() { _ = onKey(.copy) }
        @objc private func menuBatch() { _ = onKey(.batch) }
        @objc private func menuTrash() { _ = onKey(.trash) }

        func select(_ index: Int) {
            guard let grid, urls.indices.contains(index) else { return }
            anchor = urls[index]
            let path = IndexPath(item: index, section: 0)
            grid.selectionIndexPaths = [path]
            grid.scrollToItems(at: [path], scrollPosition: .nearestHorizontalEdge)
            syncSelection(focus: index)
        }

        /// Tells the model what is selected, in list order, and which cell has the focus.
        private func syncSelection(focus: Int?) {
            guard let grid else { return }
            let selection = grid.selectionIndexPaths.map(\.item).sorted().map { urls[$0] }
            if selection != model.gridSelection { model.gridSelection = selection }
            if let focus { model.gridFocus = urls[focus] }
            grid.selectionChanged()
        }

        // MARK: Data source and delegate

        func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { urls.count }

        func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
            let item = collectionView.makeItem(withIdentifier: ThumbnailCell.identifier, for: indexPath)
            (item as? ThumbnailCell)?.configure(url: urls[indexPath.item], index: indexPath.item, count: urls.count, grid: self)
            return item
        }

        /// The keyboard's selection (arrows, ⇧-arrows, ⌘A): a single cell added takes the focus; only a plain arrow
        /// (the selection is that cell) moves the ⇧-click anchor.
        func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
            let single = indexPaths.count == 1 ? indexPaths.first?.item : nil
            if let single, collectionView.selectionIndexPaths.count == 1 { anchor = urls[single] }
            syncSelection(focus: single)
        }

        func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
            syncSelection(focus: nil)
        }
    }
}

/// The grid's collection view: its own clicks (no rubber band), double-click, keys, Quick Look of the selection and
/// dragging the selection out as files.
final class GridCollectionView: NSCollectionView, @preconcurrency QLPreviewPanelDataSource, @preconcurrency QLPreviewPanelDelegate {
    var urls: [URL] = []
    /// Keys `GridKey` maps; false sends the key on up the responder chain.
    var onKey: (GridKey) -> Bool = { _ in false }
    /// Return is a key; this is the double-click.
    var onOpen: (URL) -> Void = { _ in }
    var onClick: (Int, NSEvent.ModifierFlags) -> Void = { _, _ in }
    var onWillLayout: () -> Void = {}
    var onLayout: () -> Void = {}
    var onScaleChange: () -> Void = {}
    /// The right-clicked cell's menu.
    var onMenu: (Int) -> NSMenu? = { _ in nil }
    /// Whole column steps of a pinch (positive: larger).
    var onPinch: (Int) -> Void = { _ in }
    private var pinch = PinchSteps()
    /// The cell the mouse went down on; `deferred`: its plain click waits for mouse-up, a drag takes the selection.
    private var down: (point: NSPoint, index: Int, deferred: Bool)?

    /// The selected files, in list order: what Quick Look shows.
    private var previewed: [URL] = []

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil, controlsPreviewPanel { QLPreviewPanel.shared().orderOut(nil) }  // the grid leaves
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func layout() {
        onWillLayout()
        super.layout()
        onLayout()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        onScaleChange()
    }

    /// Right-click and Control-click on a cell; none between cells.
    override func menu(for event: NSEvent) -> NSMenu? {
        window?.makeFirstResponder(self)
        guard let index = indexPathForItem(at: convert(event.locationInWindow, from: nil))?.item, index < urls.count else { return nil }
        return onMenu(index)
    }

    override func magnify(with event: NSEvent) {
        let steps = pinch.add(event.magnification)
        if steps != 0 { onPinch(steps) }
        if event.phase == .ended || event.phase == .cancelled { pinch.end() }
    }

    override func keyDown(with event: NSEvent) {
        if let key = GridKey.action(characters: event.charactersIgnoringModifiers ?? "", modifiers: event.modifierFlags.menuKey),
           onKey(key) { return }
        super.keyDown(with: event)
    }

    /// No rubber band (spec "Mouse": no selection rectangle): a click between cells does nothing, a drag selects nothing.
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        down = nil
        let point = convert(event.locationInWindow, from: nil)
        guard let index = indexPathForItem(at: point)?.item, index < urls.count else { return }
        if event.clickCount == 2 { return onOpen(urls[index]) }
        let flags = event.modifierFlags
        let deferred = GridSelection.defersClick(index, selection: Set(selectionIndexPaths.map(\.item)),
                                                 shift: flags.contains(.shift), command: flags.contains(.command))
        if !deferred { onClick(index, flags) }
        down = (point, index, deferred)
    }

    /// Past the drag distance from a selected cell: the selected files, in list order (spec "Dragging").
    override func mouseDragged(with event: NSEvent) {
        guard let start = down else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - start.point.x, point.y - start.point.y) >= 3 else { return }
        down = nil
        let selected = selectionIndexPaths.map(\.item).sorted()
        guard selected.contains(start.index) else { return }
        // Cells off screen start from the dragged one, without a picture: ⌘A in a big folder makes no thousands of images.
        let origin = cellImage(start.index)?.1 ?? NSRect(origin: point, size: .zero)
        let items = selected.map { index in
            let item = NSDraggingItem(pasteboardWriter: urls[index] as NSURL)
            if let (image, frame) = cellImage(index) { item.setDraggingFrame(frame, contents: image) } else { item.draggingFrame = origin }
            return item
        }
        beginDraggingSession(with: items, event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        if let start = down, start.deferred { onClick(start.index, []) }
        down = nil
    }

    /// A visible cell's picture and its frame here.
    private func cellImage(_ index: Int) -> (NSImage, NSRect)? {
        guard let cell = item(at: IndexPath(item: index, section: 0)) as? ThumbnailCell, let url = cell.url else { return nil }
        let (image, frame) = cell.dragImage(for: url)
        return (image, convert(frame, from: cell.view))
    }

    /// Copy only: Finder copies even on the same disk, the Trash takes nothing, and no Featherview window takes the drop.
    override func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : []
    }

    // MARK: Quick Look (Space)

    private var controlsPreviewPanel: Bool {
        QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().dataSource === self
    }

    func toggleQuickLook() {
        if controlsPreviewPanel, QLPreviewPanel.shared().isVisible { return QLPreviewPanel.shared().orderOut(nil) }
        guard !selectionIndexPaths.isEmpty else { return }
        window?.makeFirstResponder(self)  // the panel asks the responder chain for its controller
        QLPreviewPanel.shared().makeKeyAndOrderFront(nil)
    }

    /// The panel follows the selection, at the focused cell.
    func selectionChanged() {
        guard controlsPreviewPanel else { return }
        let panel = QLPreviewPanel.shared()!
        updatePreviewed(panel)
        guard previewed.isEmpty else { return panel.reloadData() }
        // An arrow deselects before it selects: close only if the selection is still empty after this event.
        DispatchQueue.main.async { [weak self] in
            if let self, selectionIndexPaths.isEmpty, controlsPreviewPanel { QLPreviewPanel.shared().orderOut(nil) }
        }
    }

    private func updatePreviewed(_ panel: QLPreviewPanel) {
        let focus = (delegate as? ThumbnailGrid.Coordinator)?.model.gridFocus
        previewed = selectionIndexPaths.map(\.item).sorted().compactMap { urls.indices.contains($0) ? urls[$0] : nil }
        panel.currentPreviewItemIndex = focus.flatMap(previewed.firstIndex(of:)) ?? 0
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    // The panel calls these on the main thread; AppKit declares them nonisolated.
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = self
            panel.delegate = self
            updatePreviewed(panel)
        }
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = nil
            panel.delegate = nil
        }
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { previewed.count }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        previewed[index] as NSURL
    }

    /// One cell selected: arrows move the selection, as in the grid. Several: the panel steps through them itself.
    /// Space closes it.
    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard event.type == .keyDown else { return false }
        if event.charactersIgnoringModifiers == " " {
            panel.orderOut(nil)
            return true
        }
        guard previewed.count <= 1, let arrow = event.charactersIgnoringModifiers?.unicodeScalars.first?.value,
              Self.arrows.contains(arrow) else { return false }
        step(arrow)
        return true
    }

    /// With the panel as key window, the collection view's own arrow moves start from a stale cell each time, so the
    /// grid steps itself: a row is as many cells as share the first cell's line.
    private func step(_ arrow: UInt32) {
        guard let coordinator = delegate as? ThumbnailGrid.Coordinator, let current = selectionIndexPaths.first?.item else { return }
        let top = { (item: Int) in self.layoutAttributesForItem(at: IndexPath(item: item, section: 0))?.frame.minY }
        let columns = max(1, urls.indices.prefix { top($0) == top(0) }.count)
        let rtl = userInterfaceLayoutDirection == .rightToLeft
        let delta = switch Int(arrow) {
        case NSLeftArrowFunctionKey: rtl ? 1 : -1
        case NSRightArrowFunctionKey: rtl ? -1 : 1
        case NSUpArrowFunctionKey: -columns
        default: columns
        }
        if urls.indices.contains(current + delta) { coordinator.select(current + delta) }
    }

    private static let arrows: Set<UInt32> = [UInt32(NSUpArrowFunctionKey), UInt32(NSDownArrowFunctionKey),
                                              UInt32(NSLeftArrowFunctionKey), UInt32(NSRightArrowFunctionKey)]

    /// The panel zooms from the cell's square.
    func previewPanel(_ panel: QLPreviewPanel!, sourceFrameOnScreenFor item: (any QLPreviewItem)!) -> NSRect {
        guard let url = (item as? NSURL) as URL?, let index = urls.firstIndex(of: url),
              let view = self.item(at: IndexPath(item: index, section: 0))?.view, let window else { return .zero }
        let square = NSRect(x: 0, y: 0, width: view.bounds.width, height: view.bounds.width)  // flipped: the top part
        let frame = view.convert(square, to: nil)
        return visibleRect.intersects(convert(frame, from: nil)) ? window.convertToScreen(frame) : .zero
    }
}

/// One cell: the picture fitted in a square, the name below (Decision 4).
final class ThumbnailCell: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("thumbnail")
    private(set) var url: URL?
    /// The decode side of the picture shown or asked for; 0 for none.
    private var side = 0
    private var loading: Task<Void, Never>?
    /// The hover's file details read; nil once it has finished, so each URL is read once.
    private var reading: Task<Void, Never>?
    private weak var grid: ThumbnailGrid.Coordinator?
    private var cell: CellView { view as! CellView }

    override func loadView() {
        view = CellView()
        view.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                            owner: self, userInfo: nil))
    }

    override var isSelected: Bool { didSet { cell.selected = isSelected } }

    override func prepareForReuse() {
        super.prepareForReuse()
        loading?.cancel()
        loading = nil
        reading?.cancel()
        reading = nil
        cell.info = nil
        url = nil
        side = 0
        cell.show(nil, failed: false)
    }

    func configure(url: URL, index: Int, count: Int, grid: ThumbnailGrid.Coordinator) {
        self.url = url
        self.grid = grid
        cell.position = (index, count)
        cell.name = url.lastPathComponent
        if grid.isFailed(url) { cell.show(nil, failed: true) }
        load()
    }

    /// The tooltip's details: read off the main thread once the pointer rests on the cell; until then the tooltip is
    /// the name. Cells scrolling under a still pointer enter and exit within the rest, which cancels the read unstarted.
    override func mouseEntered(with event: NSEvent) {
        guard let url, cell.info == nil, reading == nil else { return }
        reading = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Theme.Motion.hoverRest))
            guard !Task.isCancelled else { return }
            let info = await Task.detached { FileInfo.read(url: url, page: 0) }.value
            guard !Task.isCancelled, let self, self.url == url else { return }
            self.reading = nil
            self.cell.info = info
        }
    }

    override func mouseExited(with event: NSEvent) {
        reading?.cancel()
        reading = nil
    }

    /// The drag image: the shown picture and its frame, else the file's icon over the square.
    func dragImage(for url: URL) -> (NSImage, NSRect) { cell.dragImage(for: url) }

    /// Asks for a picture when the cell has none at the grid's decode side, nor a decode on its way.
    func load() {
        guard let url, let grid, !grid.isFailed(url) else { return }
        let want = grid.side
        guard side < want else { return }
        if let shown = grid.model.shownThumbnail(url, side: want) {
            side = want
            cell.show(shown, failed: false)
            grid.resolved(url, failed: false)
            return
        }
        loading?.cancel()
        side = want
        loading = Task { [weak self] in
            do {
                let image = try await grid.picture(for: url, side: want)
                // A reused cell shows another file now.
                guard let self, self.url == url else { return }
                self.cell.show(image, failed: false)
                grid.resolved(url, failed: false)
            } catch is CancellationError {
                // Dropped by a refocus while the cell still shows: asked again on the next visible-range change.
                guard let self, self.url == url, self.side == want else { return }
                self.side = 0
            } catch {
                guard let self, self.url == url else { return }
                self.cell.show(nil, failed: true)
                grid.resolved(url, failed: true)
            }
        }
    }
}

/// The cell's view: a square (loading fill, selection backdrop) with the picture or the can't-open glyph, and the
/// name below (an accent capsule while selected).
private final class CellView: NSView {
    private let square = NSView()
    private let picture = NSView()
    /// Made at the first failure: most cells never need it, and an image view costs layout time as the grid opens.
    private var glyph: NSImageView?
    private let label = NSTextField(labelWithString: "")
    private var image: CGImage?
    private var failed = false
    var selected = false { didSet { applyColours() } }
    /// The cell's index and the grid's count, for the tooltip's position.
    var position = (index: 0, count: 0) { didSet { updateTooltip() } }
    var info: FileInfo? { didSet { updateTooltip() } }
    var name = "" {
        didSet {
            label.stringValue = name
            updateTooltip()
            needsLayout = true
        }
    }

    init() {
        super.init(frame: .zero)
        square.wantsLayer = true
        square.layer?.cornerRadius = Theme.Radius.gridCell
        picture.wantsLayer = true
        picture.layer?.contentsGravity = .resizeAspect
        picture.layer?.borderWidth = 1
        label.font = Theme.gridName
        label.alignment = .center
        label.lineBreakMode = .byTruncatingMiddle
        label.maximumNumberOfLines = 1
        label.wantsLayer = true
        square.addSubview(picture)
        addSubview(square)
        addSubview(label)
        applyColours()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func dragImage(for url: URL) -> (NSImage, NSRect) {
        if let image { return (NSImage(cgImage: image, size: picture.frame.size), convert(picture.frame, from: square)) }
        return (NSWorkspace.shared.icon(forFile: url.path), square.frame)
    }

    func show(_ image: CGImage?, failed: Bool) {
        self.image = image
        self.failed = failed
        picture.layer?.contents = image
        picture.isHidden = image == nil
        if failed, glyph == nil {
            let glyph = NSImageView(image: NSImage(systemSymbolName: "photo.badge.exclamationmark", accessibilityDescription: nil)!)
            glyph.imageScaling = .scaleProportionallyUpOrDown
            square.addSubview(glyph)
            self.glyph = glyph
        }
        glyph?.isHidden = !failed
        updateTooltip()
        applyColours()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let side = bounds.width
        // Not flipped (AppKit asks isFlipped often enough to cost ~8 ms as the grid opens): the square sits at the top.
        square.frame = CGRect(x: 0, y: bounds.height - side, width: side, height: side)
        if let image {
            // Fitted, aspect kept, never above one image pixel per screen pixel.
            let scale = window?.backingScaleFactor ?? 2
            let width = Double(image.width) / scale, height = Double(image.height) / scale
            let fit = min(1, (side - 2 * Theme.gridPictureInset) / max(width, height, 1))
            let size = CGSize(width: (width * fit).rounded(), height: (height * fit).rounded())
            picture.frame = CGRect(x: ((side - size.width) / 2).rounded(), y: ((side - size.height) / 2).rounded(),
                                   width: size.width, height: size.height)
        }
        glyph?.frame = square.bounds.insetBy(dx: side / 3, dy: side / 3)
        // The cell's size, not fittingSize: that sets up an Auto Layout engine per cell (~0.1 ms each as the grid opens).
        let width = min(side, (label.cell?.cellSize.width ?? 0).rounded(.up) + 2 * Theme.gridNamePadding)
        label.frame = CGRect(x: ((side - width) / 2).rounded(), y: bounds.height - side - Theme.gridNameGap - Theme.gridNameHeight,
                             width: width, height: Theme.gridNameHeight)
        label.layer?.cornerRadius = Theme.gridNameHeight / 2
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColours()
    }

    /// The picture's frame depends on the screen's scale.
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsLayout = true
    }

    private func updateTooltip() {
        toolTip = GridText.tooltip(name: name, info: info, index: position.index, count: position.count, failed: failed)
    }

    private func applyColours() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            square.layer?.backgroundColor = selected ? Theme.gridSelected.cgColor
                : image == nil ? Theme.gridLoading.cgColor : nil
            picture.layer?.borderColor = Theme.pictureHairline.cgColor
            label.layer?.backgroundColor = selected ? Theme.gridAccent.cgColor : nil
            label.textColor = selected ? Theme.gridOnAccent : Theme.gridLabel
            glyph?.contentTintColor = Theme.gridFailedGlyph
        }
    }
}
