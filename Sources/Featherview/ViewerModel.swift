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
    private(set) var image: CGImage?
    var errorMessage: String?
    /// True while a folder is being scanned, so the view shows nothing instead of the open hint.
    private(set) var isOpening = false
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
        /// ← / → work with no images too, as long as a folder is known (the chooser leaves it).
        var canBrowse = false
        var hasCurrent = false
        /// Rotate, Trash, F7 / F8: not on a held (already removed) image.
        var canChangeFile = false
        var hasPages = false
    }
    /// Stored, and set only when a value flips: buttons reading `list` would all re-evaluate on every image.
    private(set) var availability = Availability()
    private func updateAvailability() {
        let new = Availability(canBrowse: folder != nil, hasCurrent: list.current != nil,
                               canChangeFile: list.current != nil && !list.isHolding,
                               hasPages: pageCount > 1 && !list.isHolding)
        if new != availability { availability = new }
    }
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
    private let cache = ImageCache(capacity: 8, hdr: ImageDecoder.supportsHDR, colorSpace: screenSpace)
    /// Zoom decodes larger than the fit decode: one kept, and ones nobody waits for any more are skipped.
    /// Zoom steps at or below fit size go in `cache`, as large as fit decodes.
    private let fullSizeCache = ImageCache(capacity: 1, hdr: ImageDecoder.supportsHDR, colorSpace: screenSpace)
    /// The halving step the image on screen was decoded at while zoomed (page 0); zooming within it decodes nothing.
    @ObservationIgnored private var shownStep: Int?
    private var loadTask: Task<Void, Never>?
    /// The page decode running, if any: ImageIO can't stop one, so the next waits for it (see show).
    private var pageDecode: Task<CGImage, Error>?
    private var openTask: Task<Void, Never>?
    private var rotateTask: Task<Void, Never>?
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
        chooserSession.onListed = { [weak self] in self?.countImages() }
    }

    var title: String {
        guard let url = list.current else { return emptyFolder?.lastPathComponent ?? "Featherview" }
        // While the folder is listed the position isn't known yet; "1 / 1" would be wrong.
        if isOpening { return url.lastPathComponent }
        if pageCount > 1 {
            return String(localized: "\(url.lastPathComponent) — page \(page + 1) / \(pageCount) — \(list.position)")
        }
        return "\(url.lastPathComponent) — \(list.position)"
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
    func open(_ url: URL) {
        openTask?.cancel()
        isOpening = true
        closeChooser()
        emptyFolder = nil
        let includeHidden = AppSettings.showHiddenFiles.value()
        let isFolder = isFolderPath(url)
        openedFolder = isFolder ? url : url.deletingLastPathComponent()
        // Off the main actor: at launch the main thread is busy building the window, the decode needn't wait.
        let prefetch: DecodeTarget? = zoom != .fit ? nil : .fit(screens)
        ready = [:]
        knownInfo = [:]
        // A folder's first image is known only after its scan, so the scan runs here too, alongside the
        // window build, and its first image starts decoding at once (it used to wait for both).
        let prepare = Task.detached(priority: .userInitiated) { [cache, fullSizeCache] () -> Result<[URL], Error>? in
            await cache.removeAll()
            await fullSizeCache.removeAll()
            guard isFolder else {
                if let prefetch { await cache.prefetch([url], target: prefetch) }
                return nil
            }
            let scan = Result {
                try Signposts.poster.withIntervalSignpost("Scan") {
                    try FolderScanner.images(around: url, includeHidden: includeHidden, sorted: false)
                }
            }
            if let prefetch, let first = FolderScanner.firstInFinderOrder((try? scan.get()) ?? []) {
                await cache.prefetch([first], target: prefetch)
            }
            return scan.map(FolderScanner.inFinderOrder)
        }
        openTask = Task {
            defer { if !Task.isCancelled { isOpening = false } }
            let folderScan = await prepare.value
            guard !Task.isCancelled else { return }
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
                    show()
                } else if zoom == .fit, prefetchesNeighbors {
                    // show() ran before the neighbours were known; calling it again could restart the decode.
                    let neighbors = list.neighbors(radius: 2)
                    await cache.prefetch(neighbors, target: .fit(screens))
                    guard !Task.isCancelled else { return }
                    await fillReady(neighbors, screens: screens)
                }
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = "Can't open \(url.lastPathComponent)"
            }
        }
        // Only now: shown earlier, the view sees no image and !isOpening and builds the toolbar (~150 ms) first.
        revealWindow()
    }

    func next() {
        if list.next() { show() } else { pastEnd(forward: true) }
    }

    func previous() {
        if list.previous() { show() } else { pastEnd(forward: false) }
    }
    func first() { list.first(); show() }
    func last() { list.last(); show() }

    func setZoom(_ zoom: Zoom) {
        var needsReload = (zoom == .fit) != (self.zoom == .fit)
        // Past the decoded step the image shows enlarged (drawn at its full size) until the next step lands.
        if case .factor(let factor) = zoom, !needsReload, page == 0, let shownStep,
           fileInfo?.isFor(list.current, page: 0) == true, let size = fileInfo?.pixelSize {
            needsReload = ImageDecoder.zoomStep(full: Int(max(size.width, size.height)), factor: factor) != shownStep
        }
        self.zoom = zoom
        // A held image is gone from disk: show() would release it and decode the next file at the held page.
        if needsReload, !list.isHolding { show(page: page) }
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
    func chooserOpen() { chooserSession.open { [weak self] in self?.open($0) } }
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

    /// ⌥→ / ⌥←: pages of a multi-page TIFF; nothing past either end, nor on a held (removed) image.
    func nextPage() { if !list.isHolding, page + 1 < pageCount { page += 1; show(page: page) } }
    func previousPage() { if !list.isHolding, page > 0 { page -= 1; show(page: page) } }

    /// Settings › Viewer › zoom step, 10 % by default (×1.1).
    private var zoomMultiplier: Double { 1 + Double(max(AppSettings.zoomStepPercent.value(), 1)) / 100 }
    func zoomIn() { stepZoom(by: zoomMultiplier) }
    func zoomOut() { stepZoom(by: 1 / zoomMultiplier) }

    /// From fit, steps from the scale the image is shown at, which needs its full pixel size.
    private func stepZoom(by multiplier: Double) {
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
    /// arrow keys feel instant.
    func show(page: Int = 0) {
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
        let neighbors = list.neighbors(radius: 2)
        let started = ContinuousClock.now
        let prefetched = page == 0 && size != nil ? ready[url] : nil
        navigation = (Signposts.poster.beginInterval("Navigate", id: Signposts.poster.makeSignpostID(),
                                                     "\(url.lastPathComponent, privacy: .public)"),
                      url, prefetched != nil, nil)
        if let prefetched { shown(prefetched, url: url, page: page, started: started) }
        shownStep = nil
        loadTask = Task {
            // Set while zoomed when the step goes in `cache`: its neighbours are prefetched at it.
            var zoomPrefetch: DecodeTarget?
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
                    let space = Self.screenSpace
                    let decode = Task.detached(priority: .userInitiated) {
                        try ImageDecoder.decode(url, halvingSteps: true, fitting: size, page: page,
                                                hdr: ImageDecoder.supportsHDR, colorSpace: space)
                    }
                    pageDecode = decode
                    // A finished decode would otherwise keep its page in memory, outside both caches.
                    defer { if pageDecode == decode { pageDecode = nil } }
                    decoded = try await decode.value
                } else if let size {
                    decoded = try await cache.image(for: url, target: .fit(size))
                } else {
                    let (target, zoomCache) = await zoomDecode(url)
                    guard !Task.isCancelled else { return }
                    if case .step(let step) = target { shownStep = step }
                    if zoomCache === cache { zoomPrefetch = target }
                    decoded = try await zoomCache.image(for: url, target: target)
                }
                guard !Task.isCancelled else { return }
                if prefetched == nil { shown(decoded, url: url, page: page, started: started) }
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
            } catch {
                guard !Task.isCancelled else { return }
                endNavigation("failed")
                fileInfo = nil
                image = nil  // pageCount stays: one bad page mustn't hide the file's other pages
                errorMessage = "Can't open \(url.lastPathComponent)"
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
            } else if let zoomPrefetch, prefetchesNeighbors {
                // ±1, not ±2 as at fit: zoomed images are large.
                // shortcut: steps above fit size (fullSizeCache, one image) prefetch nothing, give it room if browsing at 100 % is common.
                await cache.prefetch(list.neighbors(radius: 1), target: zoomPrefetch)
            }
        }
    }

    /// The halving step to decode zoomed `url` at, for the current factor, and the cache it goes in: `cache`
    /// when that step is no larger than the fit decode, else the one-image `fullSizeCache`. Full size in
    /// `fullSizeCache` when the size can't be read (the decode then reports the file).
    private func zoomDecode(_ url: URL) async -> (DecodeTarget, ImageCache) {
        var size = fileInfo?.isFor(url, page: 0) == true ? fileInfo?.pixelSize : knownInfo[url]?.pixelSize
        if size == nil { size = await Task.detached { ImageDecoder.displaySize(of: url) }.value }
        // Read after the wait: setZoom can't re-decode before `shownStep` is set, so it must see the latest factor.
        guard case .factor(let factor) = zoom, let size else { return (.full, fullSizeCache) }
        let full = Int(max(size.width, size.height))
        let step = ImageDecoder.zoomStep(full: full, factor: factor)
        let fit = ImageDecoder.fitDecodeSize(image: PixelSize(width: Int(size.width), height: Int(size.height)), screens: screens)
        return (.step(step), ImageDecoder.stepSize(full: full, step: step) <= fit ? cache : fullSizeCache)
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
        guard zoom == .fit, !list.isEmpty else { return }
        let neighbors = list.neighbors(radius: 2)
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
                errorMessage = "Couldn't move \(url.lastPathComponent) to the Trash"
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
        guard wasCurrent, !hold else { return }
        // Keeps the folder known, so the view says it's empty and ← / → still reach the chooser.
        if list.isEmpty { emptyFolder = openedFolder ?? url.deletingLastPathComponent() }
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

    /// Rewrites the file off the main thread. Rotations and trashing run one at a time so none is lost.
    func rotate(_ rotation: Rotation) {
        guard let url = list.current, !list.isHolding else { return }  // a held image is already gone
        let page = page
        let previous = rotateTask
        rotateTask = Task {
            await previous?.value
            do {
                try await Task.detached(priority: .userInitiated) { try OrientationRotator.rotate(url, rotation, page: page) }.value
                await cache.remove(url)
                await fullSizeCache.remove(url)
                knownInfo[url] = nil
                ready[url] = nil
                fileRevision += 1
                if list.current == url { show(page: self.page) }
            } catch RotateError.notFirstPage {
                errorMessage = String(localized: "Only page 1 of \(url.lastPathComponent) can be rotated losslessly")
            } catch RotateError.unsupportedFormat {
                errorMessage = "Lossless rotation works with JPEG, HEIC and TIFF only"
            } catch {
                errorMessage = "Couldn't rotate \(url.lastPathComponent)"
            }
        }
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
        guard let url = list.current else { return }
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

    /// ⌥1–⌥3: opens the current file in the app set in Settings › Open With.
    func openWith(_ index: Int) {
        let path = AppSettings.openWith[index].value()
        guard let url = list.current, !path.isEmpty else { return }
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
        if let url = list.current { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }
}
