import CoreGraphics
import Foundation

/// Decoded images, least recently used evicted first. Keyed by URL only: callers clear it when
/// the decode size they need changes.
public actor ImageCache {
    private let capacity: Int
    private var images: [URL: CGImage] = [:]
    private var order: [URL] = []  // least recently used first
    private var inFlight: [URL: Task<CGImage, Error>] = [:]

    public init(capacity: Int = 8) {
        self.capacity = capacity
    }

    /// The cached image, or decodes it — once, even when several callers ask at the same time.
    public func image(for url: URL, maxPixelSize: Int?) async throws -> CGImage {
        if let hit = images[url] {
            touch(url)
            return hit
        }
        if let running = inFlight[url] { return try await running.value }
        let task = Task.detached(priority: .userInitiated) {
            try ImageDecoder.decode(url, maxPixelSize: maxPixelSize)
        }
        inFlight[url] = task
        defer { inFlight[url] = nil }
        let image = try await task.value
        store(image, for: url)
        return image
    }

    /// Warms the cache in the background. Failures are ignored here; they surface when shown.
    public func prefetch(_ urls: [URL], maxPixelSize: Int?) {
        for url in urls where images[url] == nil && inFlight[url] == nil {
            Task { _ = try? await self.image(for: url, maxPixelSize: maxPixelSize) }
        }
    }

    public func remove(_ url: URL) {
        images[url] = nil
        order.removeAll { $0 == url }
    }

    public func removeAll() {
        images = [:]
        order = []
    }

    public var count: Int { images.count }

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
