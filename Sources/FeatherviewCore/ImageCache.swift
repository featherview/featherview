import CoreGraphics
import Foundation
import os

/// Decoded images for display, least recently used evicted first. Decodes use halving steps, so an
/// image can be up to 2× the requested size per side (see `ImageDecoder.decodeSize`). Cached images are keyed by URL only: callers
/// clear it when the decode size they need changes. Running decodes are joined only at the same size.
public actor ImageCache {
    private let capacity: Int
    private let hdr: Bool
    private let colorSpace: CGColorSpace?
    private var images: [URL: CGImage] = [:]
    private var order: [URL] = []  // least recently used first
    private var inFlight: [URL: (size: Int?, task: Task<CGImage, Error>, waiters: Int)] = [:]

    /// `colorSpace`: the screen's, see `ImageDecoder.decode`.
    public init(capacity: Int = 8, hdr: Bool = false, colorSpace: CGColorSpace? = nil) {
        self.capacity = capacity
        self.hdr = hdr
        self.colorSpace = colorSpace
    }

    /// The cached image, or decodes it — once, even when several callers ask at the same time.
    /// A decode that every caller has given up on (task cancelled) is skipped if it hasn't started.
    public func image(for url: URL, maxPixelSize: Int?) async throws -> CGImage {
        try Task.checkCancellation()
        if let hit = images[url] {
            touch(url)
            return hit
        }
        let task: Task<CGImage, Error>
        if let running = inFlight[url], running.size == maxPixelSize, !running.task.isCancelled {
            task = running.task
            inFlight[url]?.waiters += 1
        } else {
            let hdr = hdr, colorSpace = colorSpace
            task = Task.detached(priority: .userInitiated) {
                try Task.checkCancellation()
                return try Signposts.poster.withIntervalSignpost(
                    "Decode", id: Signposts.poster.makeSignpostID(),
                    "\(url.lastPathComponent, privacy: .public) \(maxPixelSize ?? 0)"
                ) {
                    try ImageDecoder.decode(url, maxPixelSize: maxPixelSize, halvingSteps: true, hdr: hdr, colorSpace: colorSpace)
                }
            }
            inFlight[url] = (maxPixelSize, task, 1)
        }
        // Only the current decode may store: a remove or a newer request supersedes this one.
        defer { if inFlight[url]?.task == task { inFlight[url] = nil } }
        // shortcut: a decode already running is not interrupted (ImageIO can't be), only queued ones are skipped; fine while the pool is small.
        let image = try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            Task { await self.leave(url, task) }
        }
        if inFlight[url]?.task == task { store(image, for: url) }
        return image
    }

    private func leave(_ url: URL, _ task: Task<CGImage, Error>) {
        guard inFlight[url]?.task == task else { return }
        inFlight[url]?.waiters -= 1
        if inFlight[url]?.waiters == 0 { task.cancel() }
    }

    /// Warms the cache in the background. Failures are ignored here; they surface when shown.
    public func prefetch(_ urls: [URL], maxPixelSize: Int?) {
        for url in urls where images[url] == nil && inFlight[url] == nil {
            Task { _ = try? await self.image(for: url, maxPixelSize: maxPixelSize) }
        }
    }

    public func remove(_ url: URL) {
        images[url] = nil
        inFlight[url] = nil
        order.removeAll { $0 == url }
    }

    public func removeAll() {
        images = [:]
        inFlight = [:]
        order = []
    }

    public var count: Int { images.count }

    /// True if `url` is decoded and kept, not only being decoded (the bench's `browse` splits by it).
    public func contains(_ url: URL) -> Bool { images[url] != nil }

    private func touch(_ url: URL) {
        order.removeAll { $0 == url }
        order.append(url)
    }

    private func store(_ image: CGImage, for url: URL) {
        images[url] = image
        touch(url)
        while order.count > capacity { images[order.removeFirst()] = nil }
    }
}

extension ImageCache {
    func isDecoding(_ url: URL) -> Bool { inFlight[url] != nil }
}
