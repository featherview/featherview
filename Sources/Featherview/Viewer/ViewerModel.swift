import Accessibility
import AppKit
import FeatherviewCore
import Observation
import os

@MainActor @Observable
final class ViewerModel {
    enum Zoom: Equatable {
        case fit
        /// 1 = one image pixel per screen pixel.
        case factor(Double)
    }

    private(set) var list = ImageList(urls: []) { didSet { updateAvailability() } }
    private(set) var image: CGImage? { didSet { isLeaving = false } }
    /// Rotations and flips asked for (R, L, H, V) that the picture on screen doesn't show yet: the canvas shows
    /// them while the file is rewritten and decoded again.
    private(set) var pendingChanges: [OrientationChange] = []
    var pendingTransform: PictureTransform { PictureTransform(pendingChanges) }
    /// The file being rewritten and how many of `pendingChanges` are written to it, which the next decode of it shows.
    @ObservationIgnored private var writtenChanges: (url: URL, count: Int)?
    /// True while a trashed or moved picture fades out before the next one shows.
    private(set) var isLeaving = false
    var errorMessage: String?
    /// True while a folder is being scanned, so the view shows nothing instead of the open hint.
    private(set) var isOpening = false { didSet { updateAvailability() } }
    var showInfo = false
    private(set) var zoom = Zoom.fit
    /// Bumped when the current file changes on disk (rotation), so views reading it refresh.
    private(set) var fileRevision = 0
    /// For the image on screen, read off the main thread: the previous image's until the next one is shown,
    /// then the new one's if it was read ahead, else none until its read lands (never another file's).
    private(set) var fileInfo: FileInfo?
    /// Page-0 reads for the image shown and its prefetched neighbours, so a swap sets the info with the image.
    @ObservationIgnored private var knownInfo: [URL: FileInfo] = [:]
    /// Fit-size decodes of the image shown and its neighbours, also in `cache`: one swaps in with the
    /// position, in one update. Awaiting the cache actor would draw a frame in between (≈15 ms).
    @ObservationIgnored private var ready: [URL: CGImage] = [:]
    var fileValues: (url: URL, values: [String: String])? { fileInfo.map { ($0.url, $0.values) } }

    /// The scale the image is shown at, from its full pixel size (not the screen-size decode).
    var zoomPercent: Int? {
        switch zoom {
        case .factor(let factor): return Int((factor * 100).rounded())
        case .fit:
            guard let size = fileInfo?.pixelSize else { return nil }
            return Int((ZoomSteps.fitFactor(image: size, view: viewSize, displayScale: displayScale) * 100).rounded())
        }
    }

    /// When toolbar buttons and menu items can act; the methods they call guard on the same.
    struct Availability: Equatable {
        /// ← / → work with no images too, as long as a folder is known (the chooser leaves it);
        /// with "Past the end: Stop" not past the folder's ends.
        var canGoBack = false
        var canGoForward = false
        var hasCurrent = false
        /// Rotate, Trash, F7 / F8: not on a held (already removed) image.
        var canChangeFile = false
        var hasPages = false
        /// T: the window has a list to show as thumbnails (also while the grid shows, to leave it).
        var canShowGrid = false
        /// File › Compare With…: an image shows (not the grid).
        var canCompare = false
        /// X: comparing, and pane 2's file opened.
        var canSwap = false
    }
    /// Stored, and set only when a value flips: buttons reading `list` would all re-evaluate on every image.
    private(set) var availability = Availability()
    private func updateAvailability() {
        // While the folder is listed its ends aren't known yet.
        let pastEnd = isOpening ? .loop : AppSettings.pastEndBehavior
        // In the grid → moves between cells, not images (Decision 8).
        let canBrowse = folder != nil && !isGrid
        let new = Availability(canGoBack: canBrowse && pastEnd.canStep(forward: false, index: list.index, count: list.urls.count),
                               canGoForward: canBrowse && pastEnd.canStep(forward: true, index: list.index, count: list.urls.count),
                               hasCurrent: list.current != nil,
                               // In the grid these act on one viewed image (Decision 13).
                               canChangeFile: list.current != nil && !list.isHolding && !isGrid,
                               hasPages: (pageCount > 1 || player.frameCount > 1) && !list.isHolding && !isGrid,
                               canShowGrid: isGrid || (!list.isEmpty && !isOpening),
                               canCompare: list.current != nil && !list.isHolding && !isGrid,
                               canSwap: compareSession != nil && compareSession?.errorMessage == nil
                                   && list.current != nil && !list.isHolding)
        if new != availability { availability = new }
        if isAnimation != (player.frameCount > 1) { isAnimation.toggle() }
    }
    /// An animation shows: ⌥→ / ⌥← step its frames, the page items and buttons say "frame". Set only when it flips.
    private(set) var isAnimation = false
    /// Plays the animation on screen; the canvas shows its frames after the model's image (frame 0).
    let player = AnimationPlayer(colorSpace: ViewerModel.screenSpace)
    /// The viewer area, kept up to date by the view; fit-mode zoom steps start from it.
    var viewSize = CGSize.zero
    var displayScale = 2.0
    /// Brings this model's window back if it was closed. Only the main viewer sets it (AppDelegate):
    /// an extra window opening a file must not raise or reopen the main one.
    var revealWindow: () -> Void = {}

    /// Opens viewer windows for files from Finder; every window's view installs the openers.
    static let windows = ViewerWindows()
    /// The main viewer, owned here, not by a view, so a file from Finder starts decoding before any window exists.
    static let main: ViewerModel = {
        let viewer = ViewerModel()
        viewer.revealWindow = { ViewerModel.windows.revealMain() }
        return viewer
    }()
    /// The viewer the user last worked in, for ⌘O and "Use Viewer's Folder" from the batch window;
    /// the main one until another is used, and again once that one's window closes.
    static let lastActive = LastUsed(fallback: main)

    /// A folder opened directly that has no images: the view says so, ← / → still leave it.
    private(set) var emptyFolder: URL? { didSet { updateAvailability() } }
    /// Shown past either end of the folder (spec "Moving past the end of a folder").
    private let chooserSession = ChooserSession()
    var chooser: FolderChooser? { chooserSession.chooser }
    /// Also true while the chooser's first listing runs, so keys go to it and Esc cancels it.
    var isChooserOpen: Bool { chooserSession.isOpen }
    /// Image counts of the chooser's folders, filled in off the main thread as they are counted.
    private(set) var chooserCounts: [URL: Int] = [:]
    private var countTask: Task<Void, Never>?
    /// Page of a multi-page TIFF, 0-based; `pageCount` is 1 for every other file.
    private(set) var page = 0
    private(set) var pageCount = 1 { didSet { updateAvailability() } }
    /// F7 / F8: which panel is open, if any.
    var destinationPanel: FileOperation?
    var slots = DestinationSlots(defaults: .standard)

    /// Fit mode decodes to fit every screen, per axis (rounded up to a halving step): enough for any window,
    /// less memory than full size.
    /// shortcut: screens are read at launch; a display plugged in later decodes for the old set, re-read on
    /// `NSApplication.didChangeScreenParametersNotification` if that comes up.
    private let screens: [PixelSize] = {
        let screens = NSScreen.screens.map {
            PixelSize(width: Int($0.frame.width * $0.backingScaleFactor), height: Int($0.frame.height * $0.backingScaleFactor))
        }
        return screens.isEmpty ? [PixelSize(width: 2560, height: 1600)] : screens
    }()
    /// Display decodes come in it, so Core Animation doesn't colour-convert each image on the main thread.
    /// shortcut: the main screen's at launch; on another display CA converts again (slower, and clipped to the first
    /// display's gamut), follow the window's screen if people browse on two displays.
    private static let screenSpace = NSScreen.main?.colorSpace?.cgColorSpace
    /// Every display decode of this viewer runs here: nearest the image shown first, stale ones dropped (`focusDecodes`).
    private let decodes = DecodeQueue()
    /// Counts opens, so a superseded open's scan can't refocus the newer one's decodes (checked under the lock).
    private let openCount = OSAllocatedUnfairLock(initialState: 0)
    private let cache: ImageCache
    /// Zoom decodes larger than the fit decode: one kept, and ones nobody waits for any more are skipped.
    /// Zoom steps at or below fit size go in `cache`, as large as fit decodes.
    private let fullSizeCache: ImageCache
    /// The way the user last browsed: the neighbours ahead of it are decoded first.
    @ObservationIgnored private var forward = true
    /// The halving step the image on screen was decoded at while zoomed (page 0), with the longest side it was
    /// worked out from (`fileInfo` is still the previous file's until the decode lands); zooming within it decodes nothing.
    @ObservationIgnored private var shownStep: (step: Int, full: Int)?
    private var loadTask: Task<Void, Never>?
    /// The page decode running, if any: ImageIO can't stop one, so the next waits for it (see show).
    private var pageDecode: Task<CGImage, Error>?
    private var openTask: Task<Void, Never>?
    private var rotateTask: Task<Void, Never>?
    /// Rotations not yet done: the grid waits for them, a file being rewritten would give its old picture.
    @ObservationIgnored private var rotations = 0
    /// ⌘C's full-size decodes: ImageIO can't stop one, so they run one at a time and held ⌘C skips the ones in between.
    private let copies = LatestWins()
    /// Read timings with: log stream --level debug --predicate 'subsystem == "net.mynetx.featherview"'
    private static let log = Logger(subsystem: "net.mynetx.featherview", category: "viewer")
    /// When the process started, so the first image's log line covers launch and folder scan too.
    private static let processStart: Date? = {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var mib = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return nil }
        let start = info.kp_proc.p_starttime
        return Date(timeIntervalSince1970: Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000)
    }()
    private var loggedLaunch = false
    /// The running `Navigate` signpost: from show() until the canvas commits `image`, the image shown for `url`.
    @ObservationIgnored private var navigation: (state: OSSignpostIntervalState, url: URL, prefetched: Bool, image: CGImage?)?

    init() {
        cache = ImageCache(capacity: 8, hdr: ImageDecoder.supportsHDR, colorSpace: Self.screenSpace, queue: decodes)
        fullSizeCache = ImageCache(capacity: 1, hdr: ImageDecoder.supportsHDR, colorSpace: Self.screenSpace, queue: decodes)
        chooserSession.onListed = { [weak self] in self?.countImages() }
    }

    /// The window's title: the file name, then the counter.
    var title: String { titleCounter.map { "\(titleName) \($0)" } ?? titleName }

    /// The file (or empty folder) name, the folder's in the grid, both names in compare; the toolbar title shows it
    /// in the title font.
    var titleName: String {
        if isGrid, let folder { return folder.lastPathComponent }
        if let compareSession, let current = list.current {
            return CompareText.title(first: current.lastPathComponent, second: compareSession.url.lastPathComponent)
        }
        return list.current?.lastPathComponent ?? emptyFolder?.lastPathComponent
            ?? (isOpening ? openingFile?.lastPathComponent ?? "" : "Featherview")
    }

    /// The file being opened, named in the title before its image shows; nil for a folder, whose first image
    /// is known only after its scan (the title stays empty meanwhile, rather than reading "Featherview").
    private(set) var openingFile: URL?

    /// "— 1 / 4" (with the page for multi-page files), shown quieter after the name; nil without a position.
    var titleCounter: String? {
        if isGrid { return "— \(GridText.counter(list.urls.count))" }
        // While the folder is listed the position isn't known yet; "1 / 1" would be wrong.
        guard list.current != nil, !isOpening else { return nil }
        if pageCount > 1 { return String(localized: "— page \(page + 1) / \(pageCount) — \(list.position)") }
        return "— \(list.position)"
    }

    /// The folder being browsed, also when it has no images. It's the path the folder was opened by:
    /// the scanner lists a symlinked folder under its target, and the chooser must go back the way the user came.
    var folder: URL? { openedFolder ?? list.current?.deletingLastPathComponent() ?? emptyFolder }
    private var openedFolder: URL? { didSet { updateAvailability() } }

    private func isFolderPath(_ url: URL) -> Bool {
        (try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    /// A file shows at once; its folder is scanned off the main thread meanwhile, because a big
    /// folder takes longer to list and sort than the image takes to decode.
    /// `keepingCompare`: pane 1 changes folder (a swap or a compare start), pane 2 stays.
    func open(_ url: URL, keepingCompare: Bool = false) {
        openTask?.cancel()
        closeGrid()
        if !keepingCompare { leaveCompare() }
        // Its decode may be dropped by the refocus below; cancelled, it ends quietly instead of showing an error.
        loadTask?.cancel()
        isOpening = true
        closeChooser()
        emptyFolder = nil
        let includeHidden = AppSettings.showHiddenFiles.value()
        let isFolder = isFolderPath(url)
        openingFile = isFolder ? nil : url
        openedFolder = isFolder ? url : url.deletingLastPathComponent()
        // Off the main actor: at launch the main thread is busy building the window, the decode needn't wait.
        let prefetch: DecodeTarget? = zoom != .fit ? nil : .fit(screens)
        ready = [:]
        knownInfo = [:]
        // The old folder's waiting decodes go; a folder's first image is known only after its scan, which refocuses.
        // Pane 2's file stays in the window: dropped, its decode (a swap asks for it next) would never be asked again.
        let kept = keepingCompare ? compareSession.map { [$0.url] } ?? [] : []
        let opening = openCount.withLock { count in
            count += 1
            decodes.focus((isFolder ? [] : [url]) + kept)
            return count
        }
        // A folder's first image is known only after its scan, so the scan runs here too, alongside the
        // window build, and its first image starts decoding at once (it used to wait for both).
        // Also reads the first image's file details while it decodes, so the status bar is complete in the
        // frame that shows the image (read after it, they waited for the toolbar build at launch).
        let prepare = Task.detached(priority: .userInitiated) { [cache, fullSizeCache, decodes, openCount] () -> (scan: Result<[URL], Error>?, info: FileInfo?) in
            await cache.removeAll()
            await fullSizeCache.removeAll()
            guard isFolder else {
                if let prefetch { await cache.prefetch([url], target: prefetch) }
                return (nil, FileInfo.read(url: url, page: 0))
            }
            let scan = Result {
                try Signposts.poster.withIntervalSignpost("Scan") {
                    try FolderScanner.images(around: url, includeHidden: includeHidden, sorted: false)
                }
            }
            let first = FolderScanner.firstInFinderOrder((try? scan.get()) ?? [])
            if let prefetch, let first,
               // Not on the main actor: at launch it is busy building the window, and the decode would wait for it.
               openCount.withLock({ count in
                   guard count == opening else { return false }
                   decodes.focus([first] + kept)
                   return true
               }) {
                await cache.prefetch([first], target: prefetch)
            }
            return (scan.map(FolderScanner.inFinderOrder), first.map { FileInfo.read(url: $0, page: 0) })
        }
        openTask = Task {
            defer { if !Task.isCancelled { isOpening = false } }
            // prepare is detached: cancelling this task must reach it.
            let (folderScan, firstInfo) = await withTaskCancellationHandler { await prepare.value } onCancel: { prepare.cancel() }
            guard !Task.isCancelled else { return }
            if let firstInfo { knownInfo[firstInfo.url] = firstInfo }
            if !isFolder {
                list = ImageList(urls: [url], current: url)
                show()
            }
            do {
                let urls: [URL]
                if let folderScan {
                    urls = try folderScan.get()
                } else {
                    urls = try await Task.detached(priority: .userInitiated) {
                        try Signposts.poster.withIntervalSignpost("Scan") {
                            try FolderScanner.images(around: url, includeHidden: includeHidden)
                        }
                    }.value
                }
                guard !Task.isCancelled else { return }
                list = ImageList(urls: urls, current: url)
                if isFolder {
                    emptyFolder = urls.isEmpty ? url : nil
                    if urls.isEmpty { leaveCompare() }  // the chooser keeps comparing; an empty list ends it
                    show()
                } else if zoom == .fit, prefetchesNeighbors {
                    // The folder is listed: the title's position and the status bar needn't wait for the neighbours.
                    isOpening = false
                    // show() ran before the neighbours were known; calling it again could restart the decode.
                    let neighbors = focusDecodes()
                    await cache.prefetch(neighbors, target: .fit(screens))
                    guard !Task.isCancelled else { return }
                    await fillReady(neighbors, screens: screens)
                }
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = String(localized: "Can't open \(url.lastPathComponent)")
            }
        }
        // Only now: shown earlier, the view sees no image and !isOpening and builds the toolbar (~150 ms) first.
        revealWindow()
    }

    func next() {
        guard !isGrid else { return }
        forward = true
        if list.next() { show() } else { pastEnd(forward: true) }
    }

    func previous() {
        guard !isGrid else { return }
        forward = false
        if list.previous() { show() } else { pastEnd(forward: false) }
    }
    func first() { list.first(); show() }
    func last() { list.last(); show() }

    func setZoom(_ zoom: Zoom) {
        var needsReload = (zoom == .fit) != (self.zoom == .fit)
        // Past the decoded step the image shows enlarged (drawn at its full size) until the next step lands.
        if case .factor(let factor) = zoom, !needsReload, page == 0, let shownStep {
            needsReload = ImageDecoder.zoomStep(full: shownStep.full, factor: factor) != shownStep.step
        }
        self.zoom = zoom
        // A held image is gone from disk: show() would release it and decode the next file at the held page.
        if needsReload, !list.isHolding { show(page: page, keepsPlayer: true) }
    }

    private func pastEnd(forward: Bool) {
        // While the folder is scanned the list isn't complete yet: its end isn't the folder's end.
        guard !isOpening else { return }
        switch AppSettings.pastEndBehavior {
        case .stop: break
        case .loop:
            guard !list.isEmpty else { break }
            if forward { list.first() } else { list.last() }
            show()
        case .folderChooser:
            guard let folder else { break }
            let includeHidden = AppSettings.showHiddenFiles.value()
            chooserCounts = [:]  // folders may have changed since the last chooser
            chooserSession.start(folder: folder, includeHidden: includeHidden)
        }
    }

    /// Chooser keys: ↑ ↓ select, → / Space enter, ← up, Return opens, Esc cancels.
    func chooserMove(_ delta: Int) { chooserSession.move(delta) }
    func chooserEnter() { chooserSession.enter() }
    func chooserUp() { chooserSession.up() }
    func chooserOpen() { chooserSession.open { [weak self] in self?.open($0, keepingCompare: true) } }
    func closeChooser() {
        countTask?.cancel()
        chooserSession.close()
    }

    /// Counts the listed folders' images one by one, off the main thread; a big folder takes a while.
    private func countImages() {
        countTask?.cancel()
        guard let chooser else { return }
        let folders = chooser.entries.map(\.url).filter { chooserCounts[$0] == nil }
        let includeHidden = AppSettings.showHiddenFiles.value()
        countTask = Task {
            for folder in folders {
                let count = await Task.detached(priority: .utility) {
                    FolderTree.imageCount(in: folder, includeHidden: includeHidden)
                }.value
                guard !Task.isCancelled else { return }
                chooserCounts[folder] = count
            }
        }
    }

    /// ⌥→ / ⌥←: pages of a multi-page TIFF, frames of an animation; nothing past either end, nor on a held (removed) image.
    func nextPage() {
        guard !list.isHolding else { return }
        if player.frameCount > 1 { player.step(forward: true) } else if page + 1 < pageCount { page += 1; show(page: page) }
    }
    func previousPage() {
        guard !list.isHolding else { return }
        if player.frameCount > 1 { player.step(forward: false) } else if page > 0 { page -= 1; show(page: page) }
    }

    /// G: pauses or plays the animation shown.
    func toggleAnimation() { player.togglePlaying() }

    /// The system's "Play animated images" changed: the animation shown follows it.
    func animatedImagesSettingChanged() {
        if player.frameCount > 1, player.isPlaying != AXAnimatedImagesEnabled() { player.togglePlaying() }
    }

    /// Settings › Viewer › zoom step, 10 % by default (×1.1).
    private var zoomMultiplier: Double { 1 + Double(max(AppSettings.zoomStepPercent.value(), 1)) / 100 }
    func zoomIn() { zoom(by: zoomMultiplier) }
    func zoomOut() { zoom(by: 1 / zoomMultiplier) }

    /// A zoom step, or a pinch step. From fit, steps from the scale the image is shown at, which needs its full pixel size.
    func zoom(by multiplier: Double) {
        if case .factor(let factor) = zoom {
            setZoom(.factor(ZoomSteps.step(factor, by: multiplier)))
            return
        }
        guard let url = list.current else { return }
        Task {
            let page = page
            let size = await Task.detached { ImageDecoder.displaySize(of: url, page: page) }.value
            guard zoom == .fit, list.current == url else { return }
            let fit = size.map { ZoomSteps.fitFactor(image: $0, view: viewSize, displayScale: displayScale) } ?? 1
            setZoom(.factor(ZoomSteps.step(fit, by: multiplier)))
        }
    }

    /// Shows `list.current` (page 0 unless `page` is given), then prefetches its neighbours so
    /// arrow keys feel instant. `keepsPlayer`: a zoom change, whose animation goes on at the new decode target.
    func show(page: Int = 0, keepsPlayer: Bool = false) {
        // Work queued before T (a Trash, a move, a rotation) lands behind the grid; leaving it shows the image.
        guard !isGrid else { return }
        // First: no frame of the file shown so far may land on the next one's canvas.
        if !keepsPlayer || player.url != list.current {
            player.stop(showing: player.url == list.current ? image : nil)
            updateAvailability()
        }
        loadTask?.cancel()
        endNavigation("superseded")
        list.release()
        // The old file's count would let ⌥→ ask a single-page file for page 2; it's read again below.
        // Assigned only when they change: the toolbar reads pageCount and would rebuild its items on every image.
        if page == 0 {
            if self.page != 0 { self.page = 0 }
            if pageCount != 1 { pageCount = 1 }
        }
        guard let url = list.current else {
            image = nil
            errorMessage = nil  // an old file's error would hide the "Open an image" hint
            return
        }
        let size: [PixelSize]? = zoom == .fit ? screens : nil
        let neighbors = focusDecodes()
        let started = ContinuousClock.now
        let prefetched = page == 0 && size != nil ? ready[url] : nil
        navigation = (Signposts.poster.beginInterval("Navigate", id: Signposts.poster.makeSignpostID(),
                                                     "\(url.lastPathComponent, privacy: .public)"),
                      url, prefetched != nil, nil)
        if let prefetched { shown(prefetched, url: url, page: page, started: started) }
        shownStep = nil
        loadTask = Task {
            // Set while zoomed (page 0): its neighbours are prefetched.
            var zoomed = false
            var target = DecodeTarget.fit(screens)
            do {
                let decoded: CGImage
                if let prefetched {
                    decoded = prefetched
                } else if page > 0 {
                    // shortcut: pages after the first aren't cached or prefetched; cache them if people browse long TIFFs.
                    // One at a time, and one superseded while it waits is skipped: holding ⌥→ on a big TIFF
                    // would otherwise run a full-size decode per key press at once.
                    _ = await pageDecode?.result
                    guard !Task.isCancelled else { return }
                    let space = Self.screenSpace, decodes = decodes
                    let decode = Task.detached(priority: .userInitiated) {
                        try await decodes.run(url) {
                            try ImageDecoder.decode(url, halvingSteps: true, fitting: size, page: page,
                                                    hdr: ImageDecoder.supportsHDR, colorSpace: space)
                        }
                    }
                    pageDecode = decode
                    // A finished decode would otherwise keep its page in memory, outside both caches.
                    defer { if pageDecode == decode { pageDecode = nil } }
                    decoded = try await decode.value
                } else if let size {
                    decoded = try await cache.image(for: url, target: .fit(size))
                } else {
                    let decode = await zoomDecode(url)
                    guard !Task.isCancelled else { return }
                    if case .step(let step) = decode.target, let full = decode.full { shownStep = (step, full) }
                    zoomed = true
                    target = decode.target
                    decoded = try await decode.cache.image(for: url, target: decode.target)
                }
                guard !Task.isCancelled else { return }
                if prefetched == nil { shown(decoded, url: url, page: page, started: started) }
                if page == 0 { play(url, target: target, first: decoded) }
                // Read again on every show: a rotation changes both size and date. Not awaited, so the
                // prefetch below doesn't wait for another file read (slow on network or USB disks).
                Task {
                    let info = await Task.detached { FileInfo.read(url: url, page: page) }.value
                    if page == 0 { knownInfo[url] = info }
                    // A slower read for another page of this file may finish last. Unchanged: no second redraw.
                    if info.isFor(list.current, page: self.page), info != fileInfo { fileInfo = info }
                }
                // Not awaited either, and only for TIFFs: a cached image swaps in without another file read.
                if page == 0, ImageFormats.mayHavePages(url) {
                    Task {
                        let count = await Task.detached { ImageDecoder.pageCount(of: url) }.value
                        if list.current == url, pageCount != count { pageCount = count }
                    }
                }
            } catch is CancellationError {
                return  // the queue dropped the decode: another image or folder took its place, not a bad file
            } catch {
                guard !Task.isCancelled else { return }
                endNavigation("failed")
                fileInfo = nil
                image = nil  // pageCount stays: one bad page mustn't hide the file's other pages
                errorMessage = String(localized: "Can't open \(url.lastPathComponent)")
            }
            if let size, page == 0, prefetchesNeighbors {
                await cache.prefetch(neighbors, target: .fit(size))
                // A rotation may have dropped ready[url] meanwhile: this task's image is the unrotated one.
                guard !Task.isCancelled else { return }
                let wanted = Set(neighbors + [url])
                knownInfo = knownInfo.filter { wanted.contains($0.key) }
                ready = ready.filter { wanted.contains($0.key) }
                if let image, list.current == url { ready[url] = image }
                await fillReady(neighbors, screens: size)
            } else if zoomed, prefetchesNeighbors {
                // ±1 (focusDecodes), not ±2 as at fit: zoomed images are large. Each at its own step, and only into `cache` when
                // that step is within its own fit size: a larger neighbour would break the cache's memory budget.
                // shortcut: steps above fit size (fullSizeCache, one image) prefetch nothing, give it room if browsing at 100 % is common.
                let wanted = Set(neighbors + [url])
                knownInfo = knownInfo.filter { wanted.contains($0.key) }
                // Fit decodes, read only at fit: step decodes replace them in `cache`, so kept here they'd sit outside its budget.
                ready = [:]
                for neighbor in neighbors {
                    let decode = await zoomDecode(neighbor)
                    guard !Task.isCancelled else { return }
                    if decode.cache === cache { await cache.prefetch([neighbor], target: decode.target) }
                }
            }
        }
    }

    /// Tells `decodes` what is wanted now and returns the neighbours to prefetch: the image shown, then ±2 at fit,
    /// ±1 zoomed, none in a background window, those ahead of the browsing direction first. Waiting decodes of
    /// other files are dropped, so a held key doesn't leave stale prefetches in front of the image the user stops at.
    @discardableResult
    private func focusDecodes() -> [URL] {
        guard let url = list.current else {
            decodes.focus([])
            return []
        }
        let neighbors = list.neighbors(radius: !prefetchesNeighbors ? 0 : zoom == .fit ? 2 : 1, forward: forward)
        // Pane 2's file right after the image shown: a held arrow key never drops its decode.
        decodes.focus([url] + (compareSession.map { [$0.url] } ?? []) + neighbors)
        return neighbors
    }

    /// The halving step to decode zoomed `url` at, for the current factor, and the cache it goes in: `cache`
    /// when that step is no larger than the fit decode, else the one-image `fullSizeCache`. Full size in
    /// `fullSizeCache` when the size can't be read (the decode then reports the file). `full` is the longest side.
    private func zoomDecode(_ url: URL) async -> (target: DecodeTarget, cache: ImageCache, full: Int?) {
        let size = await pageZeroInfo(url).pixelSize
        // Read after the wait: setZoom can't re-decode before `shownStep` is set, so it must see the latest factor.
        guard case .factor(let factor) = zoom, let size else { return (.full, fullSizeCache, nil) }
        let pixels = PixelSize(width: Int(size.width), height: Int(size.height))
        let decision = ImageDecoder.zoomDecode(size: pixels, factor: factor, screens: screens,
                                                  exactFit: ImageDecoder.decodesAtExactFit(url))
        return (.step(decision.step), decision.withinFit ? cache : fullSizeCache, max(pixels.width, pixels.height))
    }

    /// `url`'s page-0 info, read and kept in `knownInfo` when missing: a zoomed decode is smaller than the file,
    /// so `shown` needs the file's size with it, or the canvas draws the decode's pixels at the zoom factor.
    /// Never `fileInfo`: `shown` reads only `knownInfo`, and after a rotation `fileInfo` has the old orientation.
    private func pageZeroInfo(_ url: URL) async -> FileInfo {
        if let known = knownInfo[url] { return known }
        let revision = fileRevision
        let info = await Task.detached { FileInfo.read(url: url, page: 0) }.value
        // A rotation while we read makes it stale; it doesn't cancel the caller.
        if fileRevision == revision { knownInfo[url] = info }
        return info
    }

    /// Starts the animation in `url` once its frame 0 (`first`) shows, or moves the running one to `target`.
    private func play(_ url: URL, target: DecodeTarget, first: CGImage) {
        guard ImageFormats.mayAnimate(url) else { return }
        if player.url == url {
            player.retarget(target)
            // The canvas goes on showing the player's frame, so it never commits `first`.
            if player.current != nil { endCommittedNavigation() }
            return
        }
        Task {
            let animation = await Task.detached(priority: .userInitiated) { Animation.read(url) }.value
            // Another file, page or zoom took its place meanwhile.
            guard let animation, list.current == url, page == 0, image === first, player.url == nil, !isGrid else { return }
            player.start(url: url, animation: animation, target: target, first: first, playing: AXAnimatedImagesEnabled())
            updateAvailability()
        }
    }

    /// Decodes and reads `neighbors` ahead, so a swap to one is synchronous and its status bar complete.
    private func fillReady(_ neighbors: [URL], screens: [PixelSize]) async {
        for neighbor in neighbors {
            // A rotation while we wait would make what we read stale; it doesn't cancel this task.
            let revision = fileRevision
            var decoded = ready[neighbor]
            if decoded == nil { decoded = try? await cache.image(for: neighbor, target: .fit(screens)) }
            guard !Task.isCancelled else { return }
            var info = knownInfo[neighbor]
            if info == nil { info = await Task.detached { FileInfo.read(url: neighbor, page: 0) }.value }
            guard !Task.isCancelled else { return }
            guard fileRevision == revision else { continue }
            // Stored together: a swap to an image without its info would keep the previous file's in the bar.
            knownInfo[neighbor] = info
            ready[neighbor] = decoded
        }
    }

    /// Puts a decoded image on screen with its file info, in the same update: the status bar would
    /// otherwise draw without size and date first.
    private func shown(_ decoded: CGImage, url: URL, page: Int, started: ContinuousClock.Instant) {
        let info = FileInfo.shown(url: url, page: page, known: knownInfo[url], current: fileInfo)
        if info != fileInfo { fileInfo = info }
        if let navigation, navigation.url == url {
            // Already on screen: the canvas commits nothing new, so the wait ends here.
            if image === decoded { endCommittedNavigation() } else { self.navigation?.image = decoded }
        }
        if image !== decoded {
            // The rewritten file shows the changes written to it; the rest stay pending. Another file shows none.
            if let written = writtenChanges, written.url == url {
                pendingChanges.removeFirst(min(written.count, pendingChanges.count))
            } else {
                pendingChanges = []
            }
            writtenChanges = nil
        }
        image = decoded
        errorMessage = nil
        // Measures until the model has the image, not until it is on screen: the `Navigate` signpost covers that.
        let elapsed = started.duration(to: .now).components
        let ms = elapsed.seconds * 1000 + elapsed.attoseconds / 1_000_000_000_000_000
        Self.log.debug("show \(url.lastPathComponent, privacy: .public): \(ms) ms")
    }

    /// Called by the canvas once its first image is committed to the screen: launch is measured to here.
    func firstImageDrawn() {
        guard !loggedLaunch, let start = Self.processStart else { return }
        loggedLaunch = true
        let launchMs = Int(Date().timeIntervalSince(start) * 1000)
        Self.log.debug("first image \(launchMs) ms after launch")
        Signposts.poster.emitEvent("FirstImage")
    }

    /// The canvas committed `committed` to the screen.
    func imageCommitted(_ committed: CGImage) {
        if let navigation, navigation.image === committed { endCommittedNavigation() }
    }

    private func endCommittedNavigation() {
        endNavigation(navigation?.prefetched == true ? "prefetched: yes" : "prefetched: no")
    }

    private func endNavigation(_ outcome: String) {
        guard let navigation else { return }
        Signposts.poster.endInterval("Navigate", navigation.state, "\(outcome, privacy: .public)")
        self.navigation = nil
    }

    /// Runs `body` after the frame being built now is committed (Core Animation commits it before the run
    /// loop sleeps), so slow work in `body` doesn't hold that frame back.
    static func afterFrame(_ body: @escaping @MainActor () -> Void) {
        let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, false, Int.max) { _, _ in
            DispatchQueue.main.async { body() }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }

    /// Only the viewer in use prefetches neighbours: windows in the background keep just what they
    /// show, so many windows (30 files opened from Finder) don't each hold eight decoded images.
    private var prefetchesNeighbors: Bool { ViewerModel.lastActive.current === self }

    /// Called when this viewer's window becomes key: now its neighbours are worth decoding.
    func becameActive() {
        updateAvailability()  // "Past the end of a folder" may have changed in Preferences
        guard zoom == .fit, !list.isEmpty else { return }
        let neighbors = focusDecodes()
        Task { await cache.prefetch(neighbors, target: .fit(screens)) }
    }

    /// Queued behind rotations: one still running would write the file back after it was trashed.
    func moveCurrentToTrash() {
        guard let url = list.current, !list.isHolding else { return }
        let previous = rotateTask
        let scan = openTask
        rotateTask = Task {
            await previous?.value
            await scan?.value  // the scan's list would bring the file back
            guard list.urls.contains(url) else { return }  // ⌘⌫ pressed twice before this ran
            let withSidecars = AppSettings.moveSidecars.value()
            do {
                // Off the main thread: on a network or slow disk, trashing can take seconds.
                try await Task.detached(priority: .userInitiated) {
                    let sidecars = withSidecars ? Sidecars.files(for: url) : []
                    try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                    // shortcut: a sidecar that can't be trashed stays behind silently; report it if users ask.
                    for sidecar in sidecars { try? FileManager.default.trashItem(at: sidecar, resultingItemURL: nil) }
                }.value
                await removeFromList(url)
            } catch {
                errorMessage = String(localized: "Couldn't move \(url.lastPathComponent) to the Trash")
            }
        }
    }

    /// After Trash or a move: the image leaves the list. With "show the next image" on (default) the
    /// next one shows; off, the removed image stays until the next key, which then shows the one after it.
    private func removeFromList(_ url: URL) async {
        ready[url] = nil
        await cache.remove(url)
        await fullSizeCache.remove(url)
        let wasCurrent = list.current == url
        let wasLast = list.index == list.urls.count - 1
        let hold = wasCurrent && !wasLast && !AppSettings.showNextAfterRemoval.value()
        // Held, the removed file stays current, so ⌘⌫, F7 / F8, R / L and Info can't reach the unseen next one.
        list.remove(url, hold: hold)
        if let compareSession, compareSession.url == url { secondFailed(compareSession, url: url) }
        guard wasCurrent, !hold else { return }
        // Keeps the folder known, so the view says it's empty and ← / → still reach the chooser.
        if list.isEmpty {
            emptyFolder = openedFolder ?? url.deletingLastPathComponent()
            leaveCompare()
        }
        // The leaving picture fades out ("gone", not "replaced"); the next one appears hard.
        if image != nil, !isGrid {
            isLeaving = true
            try? await Task.sleep(for: .seconds(Theme.Motion.leave))
        }
        show()
    }

    func showDestinations(_ operation: FileOperation) {
        guard list.current != nil, !list.isHolding else { return }
        slots = DestinationSlots(defaults: .standard)  // Settings or another window may have changed them
        destinationPanel = operation
    }

    /// F7 / F8 with a slot picked: moves or copies the current file (and sidecars) there.
    /// A copy leaves the viewer as it is; a move removes the file from the list.
    func transfer(to slot: Int) {
        guard let operation = destinationPanel, let url = list.current, !list.isHolding else { return }
        slots = DestinationSlots.update(in: .standard) { $0.lastUsed = slot }
        guard let folder = slots[slot] else { return }
        destinationPanel = nil
        if AppSettings.askBeforeMoveCopy.value(), !confirm(operation, url, folder) { return }
        let withSidecars = AppSettings.moveSidecars.value()
        let previous = rotateTask
        let scan = openTask
        rotateTask = Task {
            await previous?.value
            await scan?.value  // the scan's list would bring the file back
            guard list.urls.contains(url) else { return }
            do {
                let target = try await Task.detached(priority: .userInitiated) {
                    try FileMover.transfer(url, to: folder, operation: operation,
                                           sidecars: withSidecars ? Sidecars.files(for: url) : [])
                }.value
                // A move into the file's own folder leaves it where it is, so it stays in the list.
                if operation == .move, target != url { await removeFromList(url) }
            } catch {
                errorMessage = operation == .move
                    ? String(localized: "Couldn't move \(url.lastPathComponent) to \(folder.lastPathComponent)")
                    : String(localized: "Couldn't copy \(url.lastPathComponent) to \(folder.lastPathComponent)")
            }
        }
    }

    /// S / ⇧⌘S: writes the shown image (its page, upright) in any writable format, then shows the
    /// saved file in its folder if Featherview can read it; otherwise the original stays.
    func saveAs() {
        guard let url = list.current, !list.isHolding else { return }
        let page = page
        Task {
            guard let choice = await SavePanel.run(for: url, window: window) else { return }
            let target = choice.url
            let previous = rotateTask
            // Queued behind rotations, like Trash and moves: one still running would give the old image.
            rotateTask = Task {
                await previous?.value
                do {
                    try await Task.detached(priority: .userInitiated) {
                        try ImageSaver.save(url, page: page, to: target, as: choice.format, options: choice.options)
                    }.value
                    guard ImageFormats.isDecodable(target) else { return }
                    await cache.remove(target)  // it may have replaced a listed file
                    await fullSizeCache.remove(target)
                    fileRevision += 1  // the Info panel reloads even when the path stays the same
                    open(target)
                } catch {
                    errorMessage = String(localized: "Couldn't save \(target.lastPathComponent)")
                }
            }
        }
    }

    /// Lets the user pick a slot's folder; returns false if they cancelled.
    @discardableResult
    func chooseFolder(for slot: Int) -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = slots[slot]
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        slots = DestinationSlots.update(in: .standard) { $0[slot] = url }
        return true
    }

    private func confirm(_ operation: FileOperation, _ url: URL, _ folder: URL) -> Bool {
        let alert = NSAlert()
        alert.messageText = operation == .move
            ? String(localized: "Move \(url.lastPathComponent) to \(folder.lastPathComponent)?")
            : String(localized: "Copy \(url.lastPathComponent) to \(folder.lastPathComponent)?")
        alert.addButton(withTitle: operation == .move ? String(localized: "Move") : String(localized: "Copy"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    func rotate(_ rotation: Rotation) { change(.rotate(rotation)) }

    func flip(_ flip: Flip) { change(.flip(flip)) }

    /// Rewrites the file off the main thread. Rotations, flips and trashing run one at a time so none is lost.
    func change(_ change: OrientationChange) {
        guard let url = list.current, !list.isHolding else { return }  // a held image is already gone
        let page = page
        let isRotation = if case .rotate = change { true } else { false }
        pendingChanges.append(change)
        rotations += 1
        // A rotated file shows once the canvas has finished turning the picture, not part-way; a flip shows at once.
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let turned = ContinuousClock.now + .seconds(isRotation && !reduceMotion ? Theme.Motion.rotation : 0)
        let previous = rotateTask
        rotateTask = Task {
            defer { rotations -= 1 }
            await previous?.value
            do {
                try await Task.detached(priority: .userInitiated) { try OrientationRotator.apply(url, change, page: page) }.value
                // Only for the file on screen: another one shown meanwhile cleared the changes.
                if list.current == url {
                    writtenChanges = (url, (writtenChanges?.url == url ? writtenChanges?.count ?? 0 : 0) + 1)
                }
                await cache.remove(url)
                await fullSizeCache.remove(url)
                await thumbnails?.cache.remove(url)
                try? await Task.sleep(until: turned)
                knownInfo[url] = nil
                ready[url] = nil
                fileRevision += 1
                if list.current == url { show(page: self.page) }
                if let compareSession, compareSession.url == url {
                    // Pane 2 shows the same file: its picture and size turned too.
                    await compareSession.zoomCache.remove(url)
                    compareSession.change(to: url)
                    compareSession.info = nil
                    showSecond()
                }
            } catch RotateError.notFirstPage {
                dropFailed(url)
                errorMessage = isRotation
                    ? String(localized: "Only page 1 of \(url.lastPathComponent) can be rotated losslessly")
                    : String(localized: "Only page 1 of \(url.lastPathComponent) can be flipped losslessly")
            } catch RotateError.unsupportedFormat {
                dropFailed(url)
                errorMessage = isRotation
                    ? String(localized: "Lossless rotation works with JPEG, HEIC and TIFF only")
                    : String(localized: "Lossless flipping works with JPEG, HEIC and TIFF only")
            } catch {
                dropFailed(url)
                errorMessage = isRotation
                    ? String(localized: "Couldn't rotate \(url.lastPathComponent)")
                    : String(localized: "Couldn't flip \(url.lastPathComponent)")
            }
        }
    }

    /// Takes back the change that failed: the first not yet written (the ones before it in the chain were).
    private func dropFailed(_ url: URL) {
        guard list.current == url else { return }
        let written = writtenChanges?.url == url ? writtenChanges?.count ?? 0 : 0
        if pendingChanges.indices.contains(written) { pendingChanges.remove(at: written) }
    }

    // MARK: Thumbnail grid

    /// T: the grid of the list's thumbnails in place of the image (on), or the focused cell's image (off).
    private(set) var isGrid = false { didSet { updateAvailability() } }
    /// The last cell clicked or moved to: T, Return and double-click view it; the strip shows its details.
    var gridFocus: URL? { didSet { if gridFocus != oldValue { readGridInfo() } } }
    /// The selected cells' files, in list order; set by the grid.
    var gridSelection: [URL] = []
    /// The focused cell's details for the strip, read off the main thread.
    private(set) var gridInfo: FileInfo?
    @ObservationIgnored private var gridInfoTask: Task<Void, Never>?
    /// Esc's target: the image shown before T.
    @ObservationIgnored private var gridReturn: URL?
    /// Created at the first T, never at launch; dropped when another folder opens or the window closes.
    @ObservationIgnored private var thumbnails: Thumbnails?
    /// The running `GridShow` signpost: from T until the grid's first frame is committed.
    @ObservationIgnored private var gridShow: OSSignpostIntervalState?

    /// The grid's own decodes: a queue wider than the viewer's and a cache of 3 screens of pixels (Decisions 8, 9).
    private struct Thumbnails {
        let queue: DecodeQueue
        let cache: ImageCache
    }

    func toggleGrid() {
        if isGrid { return viewFromGrid(gridFocus) }
        guard availability.canShowGrid else { return }
        leaveCompare()
        gridShow = Signposts.poster.beginInterval("GridShow", id: Signposts.poster.makeSignpostID())
        if thumbnails == nil {
            let queue = DecodeQueue(width: max(2, min(6, ProcessInfo.processInfo.activeProcessorCount - 2)))
            let budget = ThumbnailSize.cacheBudget(screens: screens)
            thumbnails = Thumbnails(queue: queue, cache: ImageCache(capacity: .max, colorSpace: Self.screenSpace,
                                                                    queue: queue, byteBudget: budget))
        }
        loadTask?.cancel()
        endNavigation("superseded")
        player.stop()
        gridReturn = list.current
        errorMessage = nil  // the viewed image's error would sit over the cells
        gridFocus = list.current
        gridSelection = list.current.map { [$0] } ?? []
        showInfo = false
        isGrid = true
    }

    /// Return, double-click, T: leaves the grid and shows `url` (the focused cell).
    func viewFromGrid(_ url: URL?) {
        guard isGrid else { return }
        if let url, url != list.current, list.select(url), ready[url] == nil {
            // The image viewed before T would show until this one decodes: another file's picture.
            image = nil
        }
        isGrid = false
        thumbnails?.queue.focus([])  // waiting cell decodes would compete with this image's
        show()
    }

    /// Esc: back to the image shown before T.
    func leaveGridCancelling() { viewFromGrid(gridReturn) }

    /// The window closes: the grid goes, and the image viewed restarts (its decode, its animation) for a reopened window.
    func closeWindow() {
        viewFromGrid(list.current)
        closeGrid()
    }

    /// Another file or folder opens: the grid goes, with its thumbnails.
    func closeGrid() {
        isGrid = false
        thumbnails?.queue.focus([])
        thumbnails = nil
        gridFocus = nil
        gridSelection = []
    }

    /// The grid's first frame is on screen.
    func gridDrawn() {
        guard let gridShow else { return }
        Signposts.poster.endInterval("GridShow", gridShow)
        self.gridShow = nil
    }

    /// A kept picture for `url` at `side` or larger, at once (no actor hop), so a cell scrolled back to shows it
    /// in the same frame.
    func shownThumbnail(_ url: URL, side: Int) -> CGImage? {
        guard rotations == 0 else { return nil }
        return thumbnails?.cache.cached(url, target: .thumbnail(side))
    }

    /// A cell's picture, decoded on the grid's queue, longest side at most `side`.
    func thumbnail(_ url: URL, side: Int) async throws -> CGImage {
        if rotations > 0 { await rotateTask?.value }
        guard isGrid, let thumbnails else { throw CancellationError() }
        return try await thumbnails.cache.image(for: url, target: .thumbnail(side))
    }

    /// The cells wanted now, visible first, then ahead (`GridWindow.wanted`): waiting decodes of others are dropped.
    func focusThumbnails(_ urls: [URL]) {
        guard isGrid else { return }  // a cell's late load after leaving would bring its decodes back
        thumbnails?.queue.focus(urls)
    }

    /// Decodes cells ahead of the scroll before they show.
    func prefetchThumbnails(_ urls: [URL], side: Int) {
        guard let cache = thumbnails?.cache, !urls.isEmpty else { return }
        Task { await cache.prefetch(urls, target: .thumbnail(side)) }
    }

    /// + / −, and the View menu's retitled zoom items, in the grid.
    func stepThumbnails(larger: Bool) {
        let size = ThumbnailSize.stepped(AppSettings.thumbnailSize.value(), larger: larger)
        UserDefaults.standard.set(size, forKey: AppSettings.thumbnailSize.key)
    }

    private func readGridInfo() {
        gridInfoTask?.cancel()
        // The previous cell's details stay until these are read, as the viewer's do: the strip doesn't blink.
        guard let url = gridFocus else { gridInfo = nil; return }
        gridInfoTask = Task {
            let info = await Task.detached { FileInfo.read(url: url, page: 0) }.value
            if !Task.isCancelled, gridFocus == url { gridInfo = info }
        }
    }

    // MARK: Compare

    /// The second pane while comparing; none exists until compare starts.
    private(set) var compareSession: CompareSession? { didSet { updateAvailability() } }
    /// The running `CompareShow` signpost: from showSecond() until pane 2's canvas commits `image`.
    @ObservationIgnored private var compareShow: (state: OSSignpostIntervalState, image: CGImage?)?

    /// Shows `first` in pane 1 (selected in the list, or its folder opened) and `second` in pane 2. Leaves the grid.
    func compare(_ first: URL, with second: URL) {
        if isGrid {
            viewFromGrid(first)
        } else if list.current != first {
            if list.select(first) { show() } else { open(first, keepingCompare: true) }
        }
        showInfo = false
        if let compareSession {
            compareSession.change(to: second)
            updateAvailability()
        } else {
            compareSession = CompareSession(url: second, zoomCache: ImageCache(
                capacity: 1, hdr: ImageDecoder.supportsHDR, colorSpace: Self.screenSpace, queue: decodes))
        }
        focusDecodes()
        showSecond()
    }

    /// File › Compare With…: the second image, chosen beside the current one.
    func showCompareOpenPanel() {
        guard availability.canCompare, let current = list.current else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.directoryURL = current.deletingLastPathComponent()
        panel.message = CompareText.choose(current.lastPathComponent)
        guard panel.runModal() == .OK, let url = panel.url, list.current == current else { return }
        compare(current, with: url)
    }

    /// Esc, Stop Comparing, opening a file, T, an empty list: pane 1 stays at its zoom, pane 2's decodes go.
    func leaveCompare() {
        guard let compareSession else { return }
        compareSession.task?.cancel()
        endCompareShow("superseded")
        self.compareSession = nil
        focusDecodes()
    }

    /// X: the two files change panes; pane 1's opens its folder when it isn't in the list. Zoom stays.
    func swapCompared() {
        guard availability.canSwap, let compareSession, let first = list.current else { return }
        let second = compareSession.url
        compareSession.change(to: first)
        if list.select(second) { show() } else { open(second, keepingCompare: true) }
        showSecond()
    }

    /// Pane 2's zoom: in step, pane 1's factor matched to the second picture's size (`CompareSync`); else its own.
    /// Fit until both pictures' sizes are known.
    var secondZoom: Zoom {
        guard let compareSession else { return .fit }
        guard AppSettings.compareInStep.value() else { return compareSession.ownZoom }
        guard let info = compareSession.info, info.url == compareSession.url, let second = info.pixelSize,
              let fileInfo, fileInfo.isFor(list.current, page: page), let first = fileInfo.pixelSize else {
            // Pane 1's details are the previous file's until its decode lands: pane 2 keeps its zoom meanwhile.
            return compareSession.info?.url == compareSession.url ? compareSession.lastMatched.map { .factor($0) } ?? .fit : .fit
        }
        let factor = switch zoom {
        case .factor(let factor): factor
        case .fit: ZoomSteps.fitFactor(image: first, view: viewSize, displayScale: displayScale)
        }
        let matched = CompareSync.matchedFactor(factor, first: first, second: second)
        compareSession.lastMatched = matched
        return .factor(matched)
    }

    /// The scale pane 2's picture is shown at, from its full pixel size.
    var secondZoomPercent: Int? {
        switch secondZoom {
        case .factor(let factor): return Int((factor * 100).rounded())
        case .fit:
            guard let size = compareSession?.info?.pixelSize else { return nil }
            return Int((ZoomSteps.fitFactor(image: size, view: viewSize, displayScale: displayScale) * 100).rounded())
        }
    }

    /// Decodes pane 2's file for `secondZoom`, off the main thread: at fit size into the viewer's cache (a swap or a
    /// step onto it reuses it), beyond fit into the session's own. Asking again for the decode on its way does nothing.
    func showSecond() {
        guard let compareSession else { return }
        let url = compareSession.url
        var target = DecodeTarget.fit(screens)
        var decodeCache = cache
        if case .factor(let factor) = secondZoom, let info = compareSession.info, info.url == url, let size = info.pixelSize {
            let decision = ImageDecoder.zoomDecode(size: PixelSize(width: Int(size.width), height: Int(size.height)),
                                                   factor: factor, screens: screens,
                                                   exactFit: ImageDecoder.decodesAtExactFit(url))
            if !decision.withinFit {
                target = .step(decision.step)
                decodeCache = compareSession.zoomCache
            }
        }
        if let wanted = compareSession.wanted, wanted.url == url, wanted.target == target { return }
        compareSession.wanted = (url, target)
        compareSession.task?.cancel()
        endCompareShow("superseded")
        compareShow = (Signposts.poster.beginInterval("CompareShow", id: Signposts.poster.makeSignpostID(),
                                                      "\(url.lastPathComponent, privacy: .public)"), nil)
        let started = ContinuousClock.now
        let known = knownInfo[url]
        compareSession.task = Task {
            do {
                let decoded = try await decodeCache.image(for: url, target: target)
                guard !Task.isCancelled else { return }
                var info = compareSession.info?.url == url ? compareSession.info : known
                if info == nil { info = await Task.detached { FileInfo.read(url: url, page: 0) }.value }
                guard !Task.isCancelled else { return }
                // Already on screen: the canvas commits nothing new.
                if compareSession.image === decoded { endCompareShow("shown") } else { compareShow?.image = decoded }
                compareSession.image = decoded
                compareSession.info = info
                compareSession.errorMessage = nil
                updateAvailability()
                let elapsed = started.duration(to: .now).components
                let ms = elapsed.seconds * 1000 + elapsed.attoseconds / 1_000_000_000_000_000
                Self.log.debug("compare \(url.lastPathComponent, privacy: .public): \(ms) ms")
            } catch is CancellationError {
                // The queue dropped it, not a newer ask: the next one decodes again.
                if !Task.isCancelled {
                    compareSession.wanted = nil
                    endCompareShow("dropped")
                }
            } catch {
                guard !Task.isCancelled else { return }
                endCompareShow("failed")
                secondFailed(compareSession, url: url)
            }
        }
    }

    /// Pane 2's file can't be read (or is gone): it says so, compare stays.
    private func secondFailed(_ session: CompareSession, url: URL) {
        session.image = nil
        session.info = nil
        session.difference = nil
        session.errorMessage = String(localized: "Can't open \(url.lastPathComponent)")
        updateAvailability()
    }

    /// Pane 2's canvas committed `committed` to the screen.
    func secondCommitted(_ committed: CGImage) {
        if let compareShow, compareShow.image === committed { endCompareShow("shown") }
    }

    private func endCompareShow(_ outcome: String) {
        guard let compareShow else { return }
        Signposts.poster.endInterval("CompareShow", compareShow.state, "\(outcome, privacy: .public)")
        self.compareShow = nil
    }

    func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .folder]
        panel.canChooseDirectories = true
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }

    /// The window showing this model; set by the view.
    weak var window: NSWindow?
    /// Kept up to date by the view from the window's full-screen notifications.
    var isFullScreen = false
    /// True while the viewer itself has the keyboard, not a text field or selected text beside it;
    /// ⌘C copies the image only then. Kept up to date by the view.
    var hasKeyboardFocus = false

    func toggleFullScreen() {
        window?.toggleFullScreen(nil)
    }

    /// ⌘C: the current image at full resolution, upright, decoded off the main thread.
    func copyImage() {
        guard let url = list.current, !isGrid else { return }
        let page = page
        let pending = rotateTask  // a rotation still rewriting the file would give the old image
        copies.submit {
            await pending?.value
            do {
                let image = try await Task.detached(priority: .userInitiated) { try ImageDecoder.decode(url, page: page, hdr: false) }.value
                guard !Task.isCancelled else { return }  // a newer ⌘C came in: skip the encode
                guard let data = await Task.detached(priority: .userInitiated, operation: { ClipboardImage.pngData(image) }).value
                else { throw DecodeError.unreadable(url) }
                guard !Task.isCancelled else { return }
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                // the pasteboard can still refuse very large data; say so rather than leave it silently empty
                if !pasteboard.setData(data, forType: .png) {
                    self.errorMessage = String(localized: "Couldn't copy \(url.lastPathComponent)")
                }
            } catch {
                if !Task.isCancelled { self.errorMessage = String(localized: "Couldn't copy \(url.lastPathComponent)") }
            }
        }
    }

    /// ⌥1–⌥3: opens the current file in the app set in Settings › Open With. Not in the grid (Decision 13).
    func openWith(_ index: Int) {
        let path = AppSettings.openWith[index].value()
        guard let url = list.current, !path.isEmpty, !isGrid else { return }
        Task {
            do {
                _ = try await NSWorkspace.shared.open([url], withApplicationAt: URL(fileURLWithPath: path),
                                                      configuration: NSWorkspace.OpenConfiguration())
            } catch {
                let app = FileManager.default.displayName(atPath: path)
                errorMessage = String(localized: "Can't open \(url.lastPathComponent) with \(app)")
            }
        }
    }

    func showInFinder() {
        if let url = list.current, !isGrid { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }
}
