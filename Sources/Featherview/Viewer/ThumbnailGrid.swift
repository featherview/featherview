import AppKit
import FeatherviewCore
import os
import SwiftUI

/// The thumbnail grid (T): the viewer's list as cells, in its order, in place of the canvas. Visible cells ask the
/// model for their pictures; every change of the visible range refocuses the grid's decode queue, so a fling leaves
/// no decodes behind it.
struct ThumbnailGrid: NSViewRepresentable {
    let model: ViewerModel
    let urls: [URL]
    /// The slider's size in points.
    let cellSize: Double
    /// The toolbar's and strip's room, as the canvas has; the grid scrolls under both.
    let insets: CanvasInsets
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
        grid.onLayout = { [weak coordinator] in coordinator?.laidOut() }
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
        private var cellSize = 0.0
        private var insets: CanvasInsets?
        /// The cell to scroll to the middle once the grid has its width (entering).
        private var pendingScroll: Int?
        /// ⇧-click extends from here.
        private var anchor: Int?
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
            if cellSize != view.cellSize {
                let oldSide = side
                cellSize = view.cellSize
                layout.itemSize = NSSize(width: cellSize, height: cellSize + Theme.gridNameGap + Theme.gridNameHeight)
                if side != oldSide { refocus(force: true) }
            }
            if urls != view.urls { reload(view.urls) }
        }

        /// The list changed (or the grid opened): every cell again, the selection kept by URL.
        private func reload(_ new: [URL]) {
            guard let grid else { return }
            let entering = urls.isEmpty
            let selected = entering ? Set(model.gridSelection) : Set(grid.selectionIndexPaths.map { urls[$0.item] })
            urls = new
            grid.urls = new
            grid.reloadData()
            grid.selectionIndexPaths = Self.paths(GridSelection.indices(of: selected, in: new))
            if entering, let focus = model.gridFocus { pendingScroll = new.firstIndex(of: focus) }
            syncSelection(focus: nil)
            fillKey = nil
            refocus(force: true)
        }

        private static func paths<S: Sequence<Int>>(_ items: S) -> Set<IndexPath> {
            Set(items.map { IndexPath(item: $0, section: 0) })
        }

        func laidOut() {
            if let index = pendingScroll, let grid, grid.bounds.width > 0, index < urls.count {
                pendingScroll = nil
                grid.scrollToItems(at: [IndexPath(item: index, section: 0)], scrollPosition: .centeredVertically)
            }
            refocus(force: false)
        }

        // MARK: Decode order

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
        /// before the bounds notification came), so its decode isn't dropped at once.
        func picture(for url: URL, side: Int) async throws -> CGImage {
            if !wanted.contains(url) { refocus(force: true) }
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
            let elapsed = fill.started.duration(to: .now).components
            let ms = elapsed.seconds * 1000 + elapsed.attoseconds / 1_000_000_000_000_000
            Self.log.debug("grid fill \(fill.cells) cells: \(ms) ms")
        }

        func isFailed(_ url: URL) -> Bool { failed.contains(url) }

        // MARK: Selection and keys

        /// Click, ⇧-click range, ⌘-click toggle (Decision 10); the clicked cell takes the focus.
        func clicked(_ index: Int, _ flags: NSEvent.ModifierFlags) {
            guard let grid else { return }
            var selection = Set(grid.selectionIndexPaths.map(\.item))
            if flags.contains(.shift), let anchor {
                selection.formUnion(min(anchor, index)...max(anchor, index))
            } else if flags.contains(.command) {
                if selection.remove(index) == nil { selection.insert(index) }
                anchor = index
            } else {
                selection = [index]
                anchor = index
            }
            grid.selectionIndexPaths = Self.paths(selection)
            syncSelection(focus: index)
        }

        func key(_ key: GridKey) -> Bool {
            switch key {
            case .first: select(0)
            case .last: select(urls.count - 1)
            default: return onKey(key)
            }
            return true
        }

        private func select(_ index: Int) {
            guard let grid, urls.indices.contains(index) else { return }
            anchor = index
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
        }

        // MARK: Data source and delegate

        func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { urls.count }

        func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
            let item = collectionView.makeItem(withIdentifier: ThumbnailCell.identifier, for: indexPath)
            (item as? ThumbnailCell)?.configure(url: urls[indexPath.item], grid: self)
            return item
        }

        /// The keyboard's selection (arrows, ⇧-arrows, ⌘A): a single cell added takes the focus.
        func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
            let single = indexPaths.count == 1 ? indexPaths.first?.item : nil
            if let single { anchor = single }
            syncSelection(focus: single)
        }

        func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
            syncSelection(focus: nil)
        }
    }
}

/// The grid's collection view: its own clicks (no rubber band), double-click and keys.
final class GridCollectionView: NSCollectionView {
    var urls: [URL] = []
    /// Keys `GridKey` maps; false sends the key on up the responder chain.
    var onKey: (GridKey) -> Bool = { _ in false }
    /// Return is a key; this is the double-click.
    var onOpen: (URL) -> Void = { _ in }
    var onClick: (Int, NSEvent.ModifierFlags) -> Void = { _, _ in }
    var onLayout: () -> Void = {}

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func layout() {
        super.layout()
        onLayout()
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags
        var modifiers: MenuKey.Modifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if let key = GridKey.action(characters: event.charactersIgnoringModifiers ?? "", modifiers: modifiers), onKey(key) { return }
        super.keyDown(with: event)
    }

    /// No rubber band (spec "Mouse": no selection rectangle): a click between cells does nothing, a drag selects nothing.
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let index = indexPathForItem(at: convert(event.locationInWindow, from: nil))?.item, index < urls.count else { return }
        if event.clickCount == 2 { onOpen(urls[index]) } else { onClick(index, event.modifierFlags) }
    }
}

/// One cell: the picture fitted in a square, the name below (Decision 4).
final class ThumbnailCell: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("thumbnail")
    private(set) var url: URL?
    /// The decode side of the picture shown or asked for; 0 for none.
    private var side = 0
    private var loading: Task<Void, Never>?
    private weak var grid: ThumbnailGrid.Coordinator?
    private var cell: CellView { view as! CellView }

    override func loadView() { view = CellView() }

    override var isSelected: Bool { didSet { cell.selected = isSelected } }

    override func prepareForReuse() {
        super.prepareForReuse()
        loading?.cancel()
        loading = nil
        url = nil
        side = 0
        cell.show(nil, failed: false)
    }

    func configure(url: URL, grid: ThumbnailGrid.Coordinator) {
        self.url = url
        self.grid = grid
        cell.name = url.lastPathComponent
        if grid.isFailed(url) { cell.show(nil, failed: true) }
        load()
    }

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
    private let glyph = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var image: CGImage?
    private var failed = false
    var selected = false { didSet { applyColours() } }
    var name = "" {
        didSet {
            label.stringValue = name
            updateTooltip()
            needsLayout = true
        }
    }

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        square.wantsLayer = true
        square.layer?.cornerRadius = Theme.Radius.gridCell
        picture.wantsLayer = true
        picture.layer?.contentsGravity = .resizeAspect
        picture.layer?.borderWidth = 1
        glyph.image = NSImage(systemSymbolName: "photo.badge.exclamationmark", accessibilityDescription: nil)
        glyph.imageScaling = .scaleProportionallyUpOrDown
        glyph.isHidden = true
        label.font = Theme.gridName
        label.alignment = .center
        label.lineBreakMode = .byTruncatingMiddle
        label.maximumNumberOfLines = 1
        label.wantsLayer = true
        square.addSubview(picture)
        square.addSubview(glyph)
        addSubview(square)
        addSubview(label)
        applyColours()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func show(_ image: CGImage?, failed: Bool) {
        self.image = image
        self.failed = failed
        picture.layer?.contents = image
        picture.isHidden = image == nil
        glyph.isHidden = !failed
        updateTooltip()
        applyColours()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let side = bounds.width
        square.frame = CGRect(x: 0, y: 0, width: side, height: side)
        if let image {
            // Fitted, aspect kept, never above one image pixel per screen pixel.
            let scale = window?.backingScaleFactor ?? 2
            let width = Double(image.width) / scale, height = Double(image.height) / scale
            let fit = min(1, (side - 2 * Theme.gridPictureInset) / max(width, height, 1))
            let size = CGSize(width: (width * fit).rounded(), height: (height * fit).rounded())
            picture.frame = CGRect(x: ((side - size.width) / 2).rounded(), y: ((side - size.height) / 2).rounded(),
                                   width: size.width, height: size.height)
        }
        glyph.frame = square.bounds.insetBy(dx: side / 3, dy: side / 3)
        let width = min(side, label.fittingSize.width + 2 * Theme.gridNamePadding)
        label.frame = CGRect(x: ((side - width) / 2).rounded(), y: side + Theme.gridNameGap, width: width, height: Theme.gridNameHeight)
        label.layer?.cornerRadius = Theme.gridNameHeight / 2
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColours()
    }

    private func updateTooltip() {
        toolTip = failed ? String(localized: "Can't open \(name)") : name
    }

    private func applyColours() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            square.layer?.backgroundColor = selected ? Theme.gridSelected.cgColor
                : image == nil ? Theme.gridLoading.cgColor : nil
            picture.layer?.borderColor = Theme.pictureHairline.cgColor
            label.layer?.backgroundColor = selected ? Theme.gridAccent.cgColor : nil
            label.textColor = selected ? Theme.gridOnAccent : Theme.gridLabel
            glyph.contentTintColor = Theme.gridFailedGlyph
        }
    }
}
