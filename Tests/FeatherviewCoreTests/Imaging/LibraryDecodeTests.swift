import CoreGraphics
import Foundation
import Testing
import os
@testable import FeatherviewCore

/// Records what the decoder asks of the library; pictures are 4×3.
private final class FakeLibrary: LibraryImages {
    let fetched: URL
    let created = Date(timeIntervalSince1970: 1_700_000_000)
    let targets = OSAllocatedUnfairLock<[DecodeTarget]>(initialState: [])

    init(fetched: URL) { self.fetched = fetched }

    func image(_ url: URL, target: DecodeTarget, colorSpace: CGColorSpace?) throws -> CGImage {
        targets.withLock { $0.append(target) }
        let context = CGContext(data: nil, width: 4, height: 3, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return context.makeImage()!
    }

    func info(_ url: URL) -> FileInfo {
        FileInfo(url: url, page: 0, pixelSize: CGSize(width: 4, height: 3), bytes: nil, modified: created, values: [:])
    }

    func file(_ url: URL) throws -> URL { fetched }
}

// Sets and clears the process-wide hook, so its tests never overlap.
@Suite(.serialized) struct LibraryDecodeTests {
    let url = URL(string: "featherview-photos://library/library/A%2FL0%2F001")!

    private func withLibrary<T>(_ library: (any LibraryImages)?, _ body: () async throws -> T) async rethrows -> T {
        ImageDecoder.library = library
        defer { ImageDecoder.library = nil }
        return try await body()
    }

    @Test func fitAndThumbnailAskTheLibrary() async throws {
        let fake = FakeLibrary(fetched: URL(fileURLWithPath: "/nonexistent.jpg"))
        let fit = DecodeTarget.fit([PixelSize(width: 100, height: 100)])
        try await withLibrary(fake) {
            let image = try await ImageCache().image(for: url, target: fit)
            #expect(image.width == 4 && image.height == 3)
            _ = try await ImageCache().image(for: url, target: .thumbnail(128))
        }
        #expect(fake.targets.withLock { $0 } == [fit, .thumbnail(128)])
    }

    @Test func zoomDecodesTheFetchedFile() async throws {
        let file = try Fixtures.writeImage(to: Fixtures.makeTempDir().appendingPathComponent("IMG_0001.jpg"),
                                           width: 40, height: 30)
        let fake = FakeLibrary(fetched: file)
        try await withLibrary(fake) {
            let image = try await ImageCache().image(for: url, target: .full)
            #expect(image.width == 40 && image.height == 30)
        }
        #expect(fake.targets.withLock { $0 }.isEmpty)
    }

    @Test func noHookIsOneBadFile() async {
        await withLibrary(nil) {
            for target in [DecodeTarget.fit([PixelSize(width: 100, height: 100)]), .thumbnail(128), .full, .step(2)] {
                await #expect(throws: DecodeError.unreadable(url)) { try await ImageCache().image(for: url, target: target) }
            }
            #expect(ImageDecoder.displaySize(of: url) == nil)
            #expect(FileInfo.read(url: url, page: 0).pixelSize == nil)
        }
    }

    @Test func infoComesFromTheLibrary() async {
        let fake = FakeLibrary(fetched: URL(fileURLWithPath: "/nonexistent.jpg"))
        await withLibrary(fake) {
            let info = FileInfo.read(url: url, page: 0)
            #expect(info.pixelSize == CGSize(width: 4, height: 3))
            #expect(info.modified == fake.created)
            #expect(info.bytes == nil)
            #expect(info.values == OverlayTemplate.fileValues(size: CGSize(width: 4, height: 3), modified: fake.created))
            #expect(info.values["size"]?.isEmpty == false)
            #expect(info.isCurrent)
            #expect(ImageDecoder.pageCount(of: url) == 1)
            #expect(ImageDecoder.displaySize(of: url) == CGSize(width: 4, height: 3))
        }
    }
}
