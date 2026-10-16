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
    var showInfo = false
    private(set) var zoom = Zoom.fit
    /// Bumped when the current file changes on disk (rotation), so views reading it refresh.
    private(set) var fileRevision = 0
    /// The viewer area, kept up to date by the view; fit-mode zoom steps start from it.
    var viewSize = CGSize.zero
    var displayScale = 2.0
    /// Brings the viewer window back if it was closed; set by the view.
    var revealWindow: () -> Void = {}

    /// Fit mode decodes at screen size: enough for any window, far less memory than full size.
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

    var title: String {
        list.current.map { "\($0.lastPathComponent) — \(list.position)" } ?? "Featherview"
    }

    /// Scans the folder off the main thread: a big folder takes a while to list and sort.
    func open(_ url: URL) {
        revealWindow()
        openTask?.cancel()
        openTask = Task {
            do {
                let urls = try await Task.detached(priority: .userInitiated) {
                    try FolderScanner.images(around: url)
                }.value
                guard !Task.isCancelled else { return }
                list = ImageList(urls: urls, current: url)
                await cache.removeAll()
                await fullSizeCache.removeAll()
                show()
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

    func zoomIn() { stepZoom(by: 1.1) }
    func zoomOut() { stepZoom(by: 1 / 1.1) }

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
            } catch {
                guard !Task.isCancelled else { return }
                image = nil
                errorMessage = "Can't open \(url.lastPathComponent)"
            }
            if let size { await cache.prefetch(neighbors, maxPixelSize: size) }
        }
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

    func toggleFullScreen() {
        NSApp.keyWindow?.toggleFullScreen(nil)
    }

    var isFullScreen: Bool {
        NSApp.keyWindow?.styleMask.contains(.fullScreen) == true
    }
}
