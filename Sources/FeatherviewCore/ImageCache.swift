import CoreGraphics
import Foundation
import os

/// What a display decode is for: full size, to fit these screens (`ImageDecoder.fitDecodeSize`), or a zoom's
/// halving step (`ImageDecoder.zoomStep`; the step, not the factor, so zooming within a step reuses the decode).
public enum DecodeTarget: Hashable, Sendable {
    case full
    case fit([PixelSize])
    case step(Int)
}

/// Decoded images for display, least recently used evicted first. Decodes use halving steps, so an
/// image can be up to 2× the requested size per side (see `ImageDecoder.decodeSize`). One image is kept per URL, and
/// used only for the target it was decoded for. Running decodes are joined only for the same target.
public actor ImageCache {
    private let capacity: Int
    private let hdr: Bool
    private let colorSpace: CGColorSpace?
    private var images: [URL: (target: DecodeTarget, image: CGImage)] = [:]
    private var order: [URL] = []  // least recently used first
    private var inFlight: [URL: (target: DecodeTarget, task: Task<CGImage, Error>, waiters: Int)] = [:]

    /// `colorSpace`: the screen's, see `ImageDecoder.decode`.
    public init(capacity: Int = 8, hdr: Bool = false, colorSpace: CGColorSpace? = nil) {
        self.capacity = capacity
        self.hdr = hdr
        self.colorSpace = colorSpace
    }

    /// The cached image, or decodes it — once, even when several callers ask at the same time.
    /// A decode that every caller has given up on (task cancelled) is skipped if it hasn't started.
    public func image(for url: URL, target: DecodeTarget) async throws -> CGImage {
        try Task.checkCancellation()
        if let hit = images[url], hit.target == target {
            touch(url)
            return hit.image
        }
        let task: Task<CGImage, Error>
        if let running = inFlight[url], running.target == target, !running.task.isCancelled {
            task = running.task
            inFlight[url]?.waiters += 1
        } else {
            let hdr = hdr, colorSpace = colorSpace
            let screens: [PixelSize]? = if case .fit(let screens) = target { screens } else { nil }
            let step: Int? = if case .step(let step) = target { step } else { nil }
            task = Task.detached(priority: .userInitiated) {
                try Task.checkCancellation()
                return try Signposts.poster.withIntervalSignpost(
                    "Decode", id: Signposts.poster.makeSignpostID(),
                    "\(url.lastPathComponent, privacy: .public) \(screens != nil ? "fit" : step.map { "step \($0)" } ?? "full", privacy: .public)"
                ) {
                    try ImageDecoder.decode(url, halvingSteps: true, fitting: screens, step: step, hdr: hdr, colorSpace: colorSpace)
                }
            }
            inFlight[url] = (target, task, 1)
        }
        // Only the current decode may store: a remove or a newer request supersedes this one.
        defer { if inFlight[url]?.task == task { inFlight[url] = nil } }
        // shortcut: a decode already running is not interrupted (ImageIO can't be), only queued ones are skipped; fine while the pool is small.
        let image = try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            Task { await self.leave(url, task) }
        }
        if inFlight[url]?.task == task { store(image, target, for: url) }
        return image
    }

    private func leave(_ url: URL, _ task: Task<CGImage, Error>) {
        guard inFlight[url]?.task == task else { return }
        inFlight[url]?.waiters -= 1
        if inFlight[url]?.waiters == 0 { task.cancel() }
    }

    /// Warms the cache in the background. Failures are ignored here; they surface when shown.
    public func prefetch(_ urls: [URL], target: DecodeTarget) {
        for url in urls where images[url]?.target != target && inFlight[url] == nil {
            Task { _ = try? await self.image(for: url, target: target) }
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

    /// Bytes of the decoded images kept (`bytesPerRow × height`). The process footprint leaves them out:
    /// ImageIO keeps decoded pixels in purgeable volatile memory.
    public var decodedBytes: Int { images.values.reduce(0) { $0 + $1.image.bytesPerRow * $1.image.height } }

    /// True if `url` is decoded and kept, not only being decoded (the bench's `browse` splits by it).
    public func contains(_ url: URL) -> Bool { images[url] != nil }

    private func touch(_ url: URL) {
        order.removeAll { $0 == url }
        order.append(url)
    }

    private func store(_ image: CGImage, _ target: DecodeTarget, for url: URL) {
        images[url] = (target, image)
        touch(url)
        while order.count > capacity { images[order.removeFirst()] = nil }
    }
}

extension ImageCache {
    func isDecoding(_ url: URL) -> Bool { inFlight[url] != nil }
}
