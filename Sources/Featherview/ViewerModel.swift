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

    /// Fit mode decodes at screen size: enough for any window, far less memory than full size.
    private let screenPixels = Int(NSScreen.screens
        .map { max($0.frame.width, $0.frame.height) * $0.backingScaleFactor }
        .max() ?? 2560)
    private let cache = ImageCache(capacity: 8)
    private var loadTask: Task<Void, Never>?
    /// Read timings with: log stream --level debug --predicate 'subsystem == "net.mynetx.featherview"'
    private static let log = Logger(subsystem: "net.mynetx.featherview", category: "viewer")

    var title: String {
        list.current.map { "\($0.lastPathComponent) — \(list.position)" } ?? "Featherview"
    }

    func open(_ url: URL) {
        do {
            list = ImageList(urls: try FolderScanner.images(around: url), current: url)
            Task { await cache.removeAll() }
            show()
        } catch {
            errorMessage = "Can't open \(url.lastPathComponent)"
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

    func zoomIn() { setZoom(.factor(min(currentFactor * 1.1, 16))) }
    func zoomOut() { setZoom(.factor(max(currentFactor / 1.1, 0.05))) }

    private var currentFactor: Double {
        if case .factor(let f) = zoom { return f }
        return 1
    }

    /// Shows `list.current`, then prefetches its neighbours so arrow keys feel instant.
    func show() {
        loadTask?.cancel()
        guard let url = list.current else {
            image = nil
            return
        }
        let size: Int? = zoom == .fit ? screenPixels : nil
        let neighbors = list.neighbors(radius: 2)
        let started = ContinuousClock.now
        loadTask = Task {
            do {
                let decoded: CGImage
                if let size {
                    decoded = try await cache.image(for: url, maxPixelSize: size)
                } else {
                    // shortcut: full-size zoom bypasses the cache; cache full images too if zooming through a folder feels slow
                    decoded = try await Task.detached(priority: .userInitiated) { try ImageDecoder.decode(url) }.value
                }
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

    func moveCurrentToTrash() {
        guard let url = list.current else { return }
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            Task { await cache.remove(url) }
            list.removeCurrent()
            show()
        } catch {
            errorMessage = "Couldn't move \(url.lastPathComponent) to the Trash"
        }
    }

    func rotate(_ rotation: Rotation) {
        guard let url = list.current else { return }
        do {
            try OrientationRotator.rotate(url, rotation)
            Task {
                await cache.remove(url)
                show()
            }
        } catch RotateError.unsupportedFormat {
            errorMessage = "Lossless rotation works with JPEG, HEIC and TIFF only"
        } catch {
            errorMessage = "Couldn't rotate \(url.lastPathComponent)"
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
