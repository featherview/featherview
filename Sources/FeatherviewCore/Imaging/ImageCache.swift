import CoreGraphics
import Foundation
import os

/// What a display decode is for: full size, to fit these screens (`ImageDecoder.fitDecodeSize`), or a zoom's
/// halving step (`ImageDecoder.zoomStep`; the step, not the factor, so zooming within a step reuses the decode).
public enum DecodeTarget: Hashable, Sendable {
    case full
    case fit([PixelSize])
    case step(Int)
    /// A grid cell's picture, longest side at most this (`ImageDecoder.thumbnail`).
    case thumbnail(Int)

    /// Whether an image decoded for `self` may be shown for `wanted`: the same target, or a larger thumbnail.
    func serves(_ wanted: DecodeTarget) -> Bool {
        if case .thumbnail(let have) = self, case .thumbnail(let want) = wanted { return have >= want }
        return self == wanted
    }
}

/// Decoded images for display, least recently used evicted first. Decodes use halving steps, so an
/// image can be up to 2× the requested size per side (see `ImageDecoder.decodeSize`). One image is kept per URL, and
/// used only for the targets it serves (`DecodeTarget.serves`). Running decodes are joined by the same rule.
public actor ImageCache {
    private let capacity: Int
    private let byteBudget: Int?
    private let hdr: Bool
    private let colorSpace: CGColorSpace?
    private var images: [URL: (target: DecodeTarget, image: CGImage)] = [:]
    private var order: [URL] = []  // least recently used first
    private var inFlight: [URL: (target: DecodeTarget, task: Task<CGImage, Error>, waiters: Int)] = [:]
    private let queue: DecodeQueue

    /// `colorSpace`: the screen's, see `ImageDecoder.decode`. `queue` runs the decodes; caches that share one
    /// share its threads and its window. `byteBudget`: at most this many `decodedBytes` are kept as well.
    public init(capacity: Int = 8, hdr: Bool = false, colorSpace: CGColorSpace? = nil, queue: DecodeQueue = DecodeQueue(),
                byteBudget: Int? = nil) {
        self.capacity = capacity
        self.byteBudget = byteBudget
        self.hdr = hdr
        self.colorSpace = colorSpace
        self.queue = queue
    }

    /// The cached image, or decodes it — once, even when several callers ask at the same time.
    /// A decode that every caller has given up on (task cancelled) is skipped if it hasn't started.
    public func image(for url: URL, target: DecodeTarget) async throws -> CGImage {
        try Task.checkCancellation()
        if let hit = images[url], hit.target.serves(target) {
            touch(url)
            return hit.image
        }
        let task: Task<CGImage, Error>
        if let running = inFlight[url], running.target.serves(target), !running.task.isCancelled {
            task = running.task
            inFlight[url]?.waiters += 1
        } else {
            let hdr = hdr, colorSpace = colorSpace, queue = queue
            let screens: [PixelSize]? = if case .fit(let screens) = target { screens } else { nil }
            let step: Int? = if case .step(let step) = target { step } else { nil }
            let side: Int? = if case .thumbnail(let side) = target { side } else { nil }
            let label = side.map { "thumb \($0)" } ?? (screens != nil ? "fit" : step.map { "step \($0)" } ?? "full")
            task = Task.detached(priority: .userInitiated) {
                try await queue.run(url) {
                    try Signposts.poster.withIntervalSignpost(
                    "Decode", id: Signposts.poster.makeSignpostID(),
                    "\(url.lastPathComponent, privacy: .public) \(label, privacy: .public)"
                    ) {
                        if let side { try ImageDecoder.thumbnail(url, side: side, colorSpace: colorSpace) }
                        else { try ImageDecoder.decode(url, halvingSteps: true, fitting: screens, step: step, hdr: hdr, colorSpace: colorSpace) }
                    }
                }
            }
            inFlight[url] = (target, task, 1)
        }
        // Only the current decode may store: a remove or a newer request supersedes this one.
        defer { if inFlight[url]?.task == task { inFlight[url] = nil } }
        // A decode already running is not interrupted (ImageIO can't be), only waiting ones are skipped.
        let image = try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            Task { await self.leave(url, task) }
        }
        // Outside the queue's window (the user moved on while it ran) it would push out an image still wanted.
        // Stored for the decode's own target: a joined smaller thumbnail must not hide that it is larger.
        if let running = inFlight[url], running.task == task, queue.wants(url) { store(image, running.target, for: url) }
        return image
    }

    private func leave(_ url: URL, _ task: Task<CGImage, Error>) {
        guard inFlight[url]?.task == task else { return }
        inFlight[url]?.waiters -= 1
        if inFlight[url]?.waiters == 0 { task.cancel() }
    }

    /// Warms the cache in the background. Failures are ignored here; they surface when shown.
    public func prefetch(_ urls: [URL], target: DecodeTarget) {
        for url in urls where images[url]?.target.serves(target) != true && inFlight[url] == nil {
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
        // The image just stored stays, even alone over the budget: its caller is about to show it.
        if let byteBudget {
            var bytes = decodedBytes
            while bytes > byteBudget, order.count > 1, let oldest = images.removeValue(forKey: order.removeFirst()) {
                bytes -= oldest.image.bytesPerRow * oldest.image.height
            }
        }
    }
}

extension ImageCache {
    func isDecoding(_ url: URL) -> Bool { inFlight[url] != nil }
}
