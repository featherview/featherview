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

    /// Fit mode decodes at screen size (rounded up to a halving step): enough for any window, less memory than full size.
    private let screenPixels = Int(NSScreen.screens
        .map { max($0.frame.width, $0.frame.height) * $0.backingScaleFactor }
        .max() ?? 2560)
    private let cache = ImageCache(capacity: 8)
    /// Full-size decodes for zoom: one kept, and ones nobody waits for any more are skipped.
    private let fullSizeCache = ImageCache(capacity: 1)
    private var loadTask: Task<Void, Never>?
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

    var title: String {
        guard let url = list.current else { return "Featherview" }
        // While the folder is listed the position isn't known yet; "1 / 1" would be wrong.
        return isOpening ? url.lastPathComponent : "\(url.lastPathComponent) — \(list.position)"
    }

    /// A file shows at once; its folder is scanned off the main thread meanwhile, because a big
    /// folder takes longer to list and sort than the image takes to decode.
    func open(_ url: URL) {
        revealWindow()
        openTask?.cancel()
        isOpening = true
        let isFolder = (try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
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
                    try FolderScanner.images(around: url)
                }.value
                guard !Task.isCancelled else { return }
                list = ImageList(urls: urls, current: url)
                if isFolder {
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

    // Past either end nothing happens yet; Milestone 2 shows the folder chooser here.
    func next() { if list.next() { show() } }
    func previous() { if list.previous() { show() } }
    func first() { list.first(); show() }
    func last() { list.last(); show() }

    func setZoom(_ zoom: Zoom) {
        let needsReload = (zoom == .fit) != (self.zoom == .fit)
        self.zoom = zoom
        if needsReload { show() }
    }

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
            let size = await Task.detached { ImageDecoder.displaySize(of: url) }.value
            guard zoom == .fit, list.current == url else { return }
            let fit = size.map { ZoomSteps.fitFactor(image: $0, view: viewSize, displayScale: displayScale) } ?? 1
            setZoom(.factor(ZoomSteps.step(fit, by: multiplier)))
        }
    }

    /// Shows `list.current`, then prefetches its neighbours so arrow keys feel instant.
    func show() {
        loadTask?.cancel()
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
                let decoded = size == nil
                    ? try await fullSizeCache.image(for: url, maxPixelSize: nil)
                    : try await cache.image(for: url, maxPixelSize: size)
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
            } catch {
                guard !Task.isCancelled else { return }
                image = nil
                errorMessage = "Can't open \(url.lastPathComponent)"
            }
            if let size, prefetchesNeighbors { await cache.prefetch(neighbors, maxPixelSize: size) }
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
        guard let url = list.current else { return }
        let previous = rotateTask
        rotateTask = Task {
            await previous?.value
            guard list.urls.contains(url) else { return }  // ⌘⌫ pressed twice before this ran
            do {
                // Off the main thread: on a network or slow disk, trashing can take seconds.
                try await Task.detached(priority: .userInitiated) {
                    try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                }.value
                await cache.remove(url)
                await fullSizeCache.remove(url)
                let wasCurrent = list.current == url
                list.remove(url)
                if wasCurrent { show() }
            } catch {
                errorMessage = "Couldn't move \(url.lastPathComponent) to the Trash"
            }
        }
    }

    /// Rewrites the file off the main thread. Rotations and trashing run one at a time so none is lost.
    func rotate(_ rotation: Rotation) {
        guard let url = list.current else { return }
        let previous = rotateTask
        rotateTask = Task {
            await previous?.value
            do {
                try await Task.detached(priority: .userInitiated) { try OrientationRotator.rotate(url, rotation) }.value
                await cache.remove(url)
                await fullSizeCache.remove(url)
                fileRevision += 1
                if list.current == url { show() }
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
}
