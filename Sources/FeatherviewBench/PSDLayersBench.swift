import FeatherviewCore
import Foundation

/// Tagged blocks the compositor draws without (the milestone's known limits); `knko` counts only when set.
let knownLimitKeys: Set<String> = ["lfx2", "lrFX", "lmfx", "clrL", "knko"]

/// Whether the file has version info (image resource 1057), which Photoshop always writes: a composite from a
/// tool that leaves it out isn't Photoshop's to compare with.
func hasVersionInfo(_ url: URL) -> Bool {
    guard let data = try? Data(contentsOf: url, options: .mappedIfSafe), data.count >= 34 else { return false }
    let b = [UInt8](data.prefix(1 << 20))
    func be(_ at: Int, _ n: Int) -> Int { at + n <= b.count ? b[at ..< at + n].reduce(0) { $0 << 8 | Int($1) } : 0 }
    var at = 30 + be(26, 4)
    let end = at + 4 + be(at, 4)
    at += 4
    while at + 12 <= min(end, b.count) {
        if be(at + 4, 2) == 1057 { return true }
        let sizeAt = at + 6 + ((1 + Int(b[at + 6]) + 1) & ~1)
        at = sizeAt + 4 + ((be(sizeAt, 4) + 1) & ~1)
    }
    return false
}

/// The corpus oracle: every layered 8-bit RGB PSD/PSB under `dir` with a real stored composite and version info, its layers drawn at
/// full size and compared with that composite, both over white. Totals count the files without known limits.
func runPSDLayers(_ dir: URL, time: Bool) {
    let files = (FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? [])
        .filter { ["psd", "psb"].contains($0.pathExtension.lowercased()) }
        .sorted { $0.path < $1.path }
    print("file\tsize\tlayers\tmean diff\t% off > 8\tknown limits" + (time ? "\tms" : ""))
    var clean = 0, within = 0
    for url in files {
        guard let layers = try? PSDLayers(url: url), layers.hasRealComposite, !layers.nodes.isEmpty, hasVersionInfo(url),
              let stored = PSDComposite(url: url),
              let composite = try? stored.decode(size: PixelSize(width: stored.width, height: stored.height)),
              let storedPixels = composite.dataProvider?.data as Data?, composite.bytesPerRow == stored.width * 4
        else { continue }
        let name = url.path.dropFirst(dir.path.count + 1)
        let start = ContinuousClock.now
        let drawn: RGBAImage
        do { drawn = try PSDCompositor.photoshop(layers).render(scale: 1) } catch {
            print("\(name)\tcan't draw its layers")
            continue
        }
        let ms = start.duration(to: .now).milliseconds
        var limits = Set<String>(), count = 0
        func limited(_ blocks: [String: Data]) {
            limits.formUnion(blocks.filter { knownLimitKeys.contains($0.key) && ($0.key != "knko" || $0.value.first != 0) }.keys)
        }
        func walk(_ nodes: [PSDNode]) {
            for node in nodes {
                switch node {
                case .layer(let layer):
                    count += 1
                    limited(layer.blocks)
                case .group(let group):
                    limited(group.blocks)
                    walk(group.children)
                }
            }
        }
        walk(layers.nodes)

        var total = 0, off = 0
        let pixels = layers.width * layers.height
        storedPixels.withUnsafeBytes { (stored: UnsafeRawBufferPointer) in
            for p in 0..<pixels {
                let a = Int(drawn.pixels[p * 4 + 3])
                var worst = 0
                for c in 0..<3 {
                    let ours = (Int(drawn.pixels[p * 4 + c]) * a + 255 * (255 - a) + 127) / 255
                    let difference = abs(ours - Int(stored[p * 4 + c]))
                    total += difference
                    worst = max(worst, difference)
                }
                if worst > 8 { off += 1 }
            }
        }
        let mean = Double(total) / Double(pixels * 3), share = 100 * Double(off) / Double(pixels)
        if limits.isEmpty {
            clean += 1
            if mean <= 1, share <= 1 { within += 1 }
        }
        print(["\(name)", "\(layers.width)×\(layers.height)", "\(count)", String(format: "%.2f", mean), String(format: "%.2f", share),
               limits.sorted().joined(separator: " ")].joined(separator: "\t") + (time ? "\t\(f(ms))" : ""))
    }
    let percent = clean == 0 ? 0 : 100 * Double(within) / Double(clean)
    print("\(within) of \(clean) files without known limits within mean ≤ 1 and ≤ 1 % off by > 8 (\(f(percent)) %)")
}
