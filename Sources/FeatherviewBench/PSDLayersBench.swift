import FeatherviewCore
import Foundation

/// Tagged blocks the compositor draws without (the milestone's known limits); `knko` counts only when set.
let knownLimitKeys: Set<String> = ["lfx2", "lrFX", "lmfx", "clrL", "knko"]

/// The corpus oracle: every layered 8-bit RGB PSD/PSB under `dir` with a real stored composite, its layers drawn at
/// full size and compared with that composite, both over white. Totals count the files without known limits.
func runPSDLayers(_ dir: URL, time: Bool) {
    let files = (FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? [])
        .filter { ["psd", "psb"].contains($0.pathExtension.lowercased()) }
        .sorted { $0.path < $1.path }
    print("file\tsize\tlayers\tmean diff\t% off > 8\tknown limits" + (time ? "\tms" : ""))
    var clean = 0, within = 0
    for url in files {
        guard let layers = try? PSDLayers(url: url), layers.hasRealComposite, !layers.nodes.isEmpty,
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
