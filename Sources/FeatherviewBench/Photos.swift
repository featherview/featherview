import CoreGraphics
import FeatherviewCore
import FeatherviewPhotos
import Foundation

/// Lists an album of the Photos library as Open from Photos does, then times the viewer's fit pictures from it.
/// Needs Photos access for the terminal running it.
@MainActor func runPhotos() async {
    let library = PhotosLibrary.shared
    guard [.authorized, .limited].contains(await library.authorize()) else {
        fail("No access to the Photos library. Allow this terminal in System Settings › Privacy & Security › Photos.")
    }
    let album = option("--album") ?? "library"
    // The sheet has listed the albums before one is chosen, so Photos' connection is set up (~140 ms the first time).
    _ = await library.albums()
    let start = ContinuousClock.now
    guard let (urls, kind) = try? await library.list(album) else { fail("No album \(album).") }
    let listMs = start.duration(to: .now).milliseconds
    guard !urls.isEmpty else { fail("No pictures in album \(album).") }
    let target = DecodeTarget.fit([.fallbackScreen])
    // The picture the album opens at, as the viewer shows it first.
    let walk = kind.opensAtEnd ? Array(urls.reversed()) : urls
    func decode(_ url: URL) -> Double? {
        let start = ContinuousClock.now
        guard (try? library.image(url, target: target, colorSpace: displayP3)) != nil else {
            print("Can't decode \(library.name(url) ?? url.absoluteString)")
            return nil
        }
        return start.duration(to: .now).milliseconds
    }
    let first = decode(walk[0])
    let times = walk.dropFirst().prefix(50).compactMap(decode).sorted()
    print("album \(album): \(urls.count) pictures, list \(f(listMs)) ms, first fit \(first.map(f) ?? "failed") ms")
    print("fit (\(PixelSize.fallbackScreen.width)x\(PixelSize.fallbackScreen.height)) over \(times.count) pictures: "
          + "p50 \(f(percentile(times, 0.5))) ms, p95 \(f(percentile(times, 0.95))) ms")
}
