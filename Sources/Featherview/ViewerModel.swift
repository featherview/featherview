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

    private(set) var list = ImageList(urls: [])
    private(set) var image: CGImage?
    var errorMessage: String?
    /// True while a folder is being scanned, so the view shows nothing instead of the open hint.
    private(set) var isOpening = false
    var showInfo = false
    private(set) var zoom = Zoom.fit
    /// Bumped when the current file changes on disk (rotation), so views reading it refresh.
    private(set) var fileRevision = 0
    /// The overlay's `{size}` and `{date}` for the file shown, read off the main thread when it's shown.
    private(set) var fileValues: (url: URL, values: [String: String])?
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
    private(set) var emptyFolder: URL?
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
    private(set) var pageCount = 1
    /// F7 / F8: which panel is open, if any.
    var destinationPanel: FileOperation?
    var slots = DestinationSlots(defaults: .standard)

    /// Fit mode decodes at screen size (rounded up to a halving step): enough for any window, less memory than full size.
    private let screenPixels = Int(NSScreen.screens
        .map { max($0.frame.width, $0.frame.height) * $0.backingScaleFactor }
        .max() ?? 2560)
    private let cache = ImageCache(capacity: 8)
    /// Full-size decodes for zoom: one kept, and ones nobody waits for any more are skipped.
    private let fullSizeCache = ImageCache(capacity: 1)
    private var loadTask: Task<Void, Never>?
    /// The page decode running, if any: ImageIO can't stop one, so the next waits for it (see show).
    private var pageDecode: Task<CGImage, Error>?
    private var openTask: Task<Void, Never>?
    private var rotateTask: Task<Void, Never>?
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
    private var openedFolder: URL?

    private func isFolderPath(_ url: URL) -> Bool {
        (try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    /// A file shows at once; its folder is scanned off the main thread meanwhile, because a big
    /// folder takes longer to list and sort than the image takes to decode.
    func open(_ url: URL) {
        revealWindow()
        openTask?.cancel()
        isOpening = true
        closeChooser()
        emptyFolder = nil
        let includeHidden = AppSettings.showHiddenFiles.value()
        let isFolder = isFolderPath(url)
        openedFolder = isFolder ? url : url.deletingLastPathComponent()
        // Off the main actor: at launch the main thread is busy building the window, the decode needn't wait.
        let prefetch = isFolder || zoom != .fit ? nil : screenPixels
        let prepare = Task.detached(priority: .userInitiated) { [cache, fullSizeCache] in
            await cache.removeAll()
            await fullSizeCache.removeAll()
            if let prefetch { await cache.prefetch([url], maxPixelSize: prefetch) }
        }
        openTask = Task {
            defer { if !Task.isCancelled { isOpening = false } }
            await prepare.value
            guard !Task.isCancelled else { return }
            if !isFolder {
                list = ImageList(urls: [url], current: url)
                show()
            }
            do {
                let urls = try await Task.detached(priority: .userInitiated) {
                    try FolderScanner.images(around: url, includeHidden: includeHidden)
                }.value
                guard !Task.isCancelled else { return }
                list = ImageList(urls: urls, current: url)
                if isFolder {
                    emptyFolder = urls.isEmpty ? url : nil
                    show()
                } else if zoom == .fit, prefetchesNeighbors {
                    // show() ran before the neighbours were known; calling it again could restart the decode.
                    await cache.prefetch(list.neighbors(radius: 2), maxPixelSize: screenPixels)
                }
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = "Can't open \(url.lastPathComponent)"
            }
        }
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
        let needsReload = (zoom == .fit) != (self.zoom == .fit)
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
        list.release()
        // The old file's count would let ⌥→ ask a single-page file for page 2; it's read again below.
        if page == 0 { self.page = 0; pageCount = 1 }
        guard let url = list.current else {
            image = nil
            errorMessage = nil  // an old file's error would hide the "Open an image" hint
            return
        }
        let size: Int? = zoom == .fit ? screenPixels : nil
        let neighbors = list.neighbors(radius: 2)
        let started = ContinuousClock.now
        loadTask = Task {
            do {
                let decoded: CGImage
                if page > 0 {
                    // shortcut: pages after the first aren't cached or prefetched; cache them if people browse long TIFFs.
                    // One at a time, and one superseded while it waits is skipped: holding ⌥→ on a big TIFF
                    // would otherwise run a full-size decode per key press at once.
                    _ = await pageDecode?.result
                    guard !Task.isCancelled else { return }
                    let decode = Task.detached(priority: .userInitiated) {
                        try ImageDecoder.decode(url, maxPixelSize: size, halvingSteps: true, page: page)
                    }
                    pageDecode = decode
                    // A finished decode would otherwise keep its page in memory, outside both caches.
                    defer { if pageDecode == decode { pageDecode = nil } }
                    decoded = try await decode.value
                } else {
                    decoded = size == nil
                        ? try await fullSizeCache.image(for: url, maxPixelSize: nil)
                        : try await cache.image(for: url, maxPixelSize: size)
                }
                guard !Task.isCancelled else { return }
                image = decoded
                errorMessage = nil
                let elapsed = started.duration(to: .now).components
                let ms = elapsed.seconds * 1000 + elapsed.attoseconds / 1_000_000_000_000_000
                Self.log.debug("show \(url.lastPathComponent, privacy: .public): \(ms) ms")
                if !loggedLaunch, let start = Self.processStart {
                    loggedLaunch = true
                    // shortcut: measured when the image is set, the frame that draws it follows (~1 frame), fine for budgets.
                    let launchMs = Int(Date().timeIntervalSince(start) * 1000)
                    Self.log.debug("first image \(launchMs) ms after launch")
                }
                // Read again on every show: a rotation changes both size and date. Not awaited, so the
                // prefetch below doesn't wait for another file read (slow on network or USB disks).
                Task {
                    let values = await Task.detached { OverlayTemplate.fileValues(of: url) }.value
                    if list.current == url { fileValues = (url, values) }
                }
                // Not awaited either, and only for TIFFs: a cached image swaps in without another file read.
                if page == 0, ImageFormats.mayHavePages(url) {
                    Task {
                        let count = await Task.detached { ImageDecoder.pageCount(of: url) }.value
                        if list.current == url { pageCount = count }
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                image = nil  // pageCount stays: one bad page mustn't hide the file's other pages
                errorMessage = "Can't open \(url.lastPathComponent)"
            }
            if let size, page == 0, prefetchesNeighbors { await cache.prefetch(neighbors, maxPixelSize: size) }
        }
    }

    /// Only the viewer in use prefetches neighbours: windows in the background keep just what they
    /// show, so many windows (30 files opened from Finder) don't each hold eight decoded images.
    private var prefetchesNeighbors: Bool { ViewerModel.lastActive.current === self }

    /// Called when this viewer's window becomes key: now its neighbours are worth decoding.
    func becameActive() {
        guard zoom == .fit, !list.isEmpty else { return }
        let neighbors = list.neighbors(radius: 2)
        Task { await cache.prefetch(neighbors, maxPixelSize: screenPixels) }
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

    func toggleFullScreen() {
        window?.toggleFullScreen(nil)
    }

    /// ⌘C: the current image at full resolution, upright, decoded off the main thread.
    func copyImage() {
        guard let url = list.current else { return }
        let page = page
        Task {
            do {
                let image = try await Task.detached(priority: .userInitiated) {
                    try ImageDecoder.decode(url, page: page)
                }.value
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.writeObjects([NSImage(cgImage: image, size: .zero)])
            } catch {
                errorMessage = "Couldn't copy \(url.lastPathComponent)"
            }
        }
    }

    /// ⌥1–⌥3: opens the current file in the app set in Settings › Open With.
    func openWith(_ index: Int) {
        let path = AppSettings.openWith[index].value()
        guard let url = list.current, !path.isEmpty else { return }
        NSWorkspace.shared.open([url], withApplicationAt: URL(fileURLWithPath: path),
                                configuration: NSWorkspace.OpenConfiguration())
    }

    func showInFinder() {
        if let url = list.current { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }
}
