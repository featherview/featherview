import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import FeatherviewCore
@Test func debugDump() throws {
    let S = "/private/tmp/claude-501/-Users-jm-Web-mx-featherview/c42a591a-7c34-43a1-a3b1-c19f8c97ace0/scratchpad"
    guard let list = try? String(contentsOfFile: S + "/dump.txt", encoding: .utf8) else { return }
    for (i, path) in list.split(separator: "\n").enumerated() {
        let url = URL(fileURLWithPath: S + "/realpsd/" + path)
        guard let layers = try PSDLayers(url: url) else { continue }
        let ours = try PSDCompositor.photoshop(layers).render(scale: 1)
        let stored = PSDComposite(url: url)!
        let theirs = try stored.decode(size: PixelSize(width: stored.width, height: stored.height))
        for (name, image) in [("ours", ours.makeCGImage()!), ("stored", theirs)] {
            let out = URL(fileURLWithPath: S + "/dump/\(i)-\(name).png")
            let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
            CGImageDestinationAddImage(dest, image, nil)
            CGImageDestinationFinalize(dest)
        }
        print("DUMP", i, path, ours.width, ours.height, Array(ours.pixels.prefix(8)))
    }
}
