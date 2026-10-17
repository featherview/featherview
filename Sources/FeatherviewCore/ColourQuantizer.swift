import Foundation

/// Batch "Reduce colours": the one step on raw pixels, after the render.
public enum ColourQuantizer {
    /// At most `colours` distinct colours (2…256, clamped). 2 = black and white by luminance.
    /// Alpha is kept as it is. Floyd–Steinberg error diffusion when `dither`.
    public static func reduce(_ image: RGBAImage, colours: Int, dither: Bool) -> RGBAImage {
        let colours = min(256, max(2, colours))
        if colours == 2 { return blackAndWhite(image, dither: dither) }
        if hasAtMost(colours, image) { return image }
        let palette = medianCut(image, colours: colours)
        return map(image, palette: palette, dither: dither)
    }

    private static func luminance(_ r: Float, _ g: Float, _ b: Float) -> Float { 0.2126 * r + 0.7152 * g + 0.0722 * b }

    private static func blackAndWhite(_ image: RGBAImage, dither: Bool) -> RGBAImage {
        var out = image
        let w = image.width
        var error = [Float](repeating: 0, count: (w + 2) * 2) // this row and the next, one pad each side
        for y in 0..<image.height {
            let row = (y & 1) * (w + 2), next = (1 - (y & 1)) * (w + 2)
            for x in 0..<w {
                let i = (y * w + x) * 4
                let v = luminance(Float(image.pixels[i]), Float(image.pixels[i + 1]), Float(image.pixels[i + 2]))
                    + error[row + x + 1]
                let on = v >= 128
                let q: UInt8 = on ? 255 : 0
                out.pixels[i] = q; out.pixels[i + 1] = q; out.pixels[i + 2] = q
                if dither {
                    let e = v - (on ? 255 : 0)
                    error[row + x + 2] += e * 7 / 16
                    error[next + x] += e * 3 / 16
                    error[next + x + 1] += e * 5 / 16
                    error[next + x + 2] += e / 16
                }
            }
            for x in 0..<w + 2 { error[row + x] = 0 }
        }
        return out
    }

    private static func hasAtMost(_ n: Int, _ image: RGBAImage) -> Bool {
        var seen = Set<UInt32>(minimumCapacity: n + 1)
        let p = image.pixels
        for i in stride(from: 0, to: p.count, by: 4) {
            seen.insert(UInt32(p[i]) << 16 | UInt32(p[i + 1]) << 8 | UInt32(p[i + 2]))
            if seen.count > n { return false }
        }
        return true
    }

    private static func bucket(_ r: Int, _ g: Int, _ b: Int) -> Int { (r >> 3) << 10 | (g >> 3) << 5 | (b >> 3) }

    /// The image's colours as entries for the median cut: every exact colour when there are at most 65,536
    /// (fine gradients and near-greys keep apart), else 5-bit-per-channel buckets (not a sort of every pixel).
    /// `channel(n, c)` is entry n's channel c at that precision; `sums` are full 8-bit sums.
    private static func histogram(_ image: RGBAImage)
        -> (count: [Int], sums: [Int], channel: (Int, Int) -> Int) {
        let p = image.pixels
        var exact = [UInt32: Int]()
        var count = [Int](), sums = [Int](), keys = [UInt32]()
        for i in stride(from: 0, to: p.count, by: 4) where p[i + 3] > 0 {
            let key = UInt32(p[i]) << 16 | UInt32(p[i + 1]) << 8 | UInt32(p[i + 2])
            let n: Int
            if let found = exact[key] { n = found } else {
                if keys.count == 1 << 16 { return buckets(image) }
                n = keys.count; exact[key] = n; keys.append(key)
                count.append(0); sums += [0, 0, 0]
            }
            count[n] += 1
            sums[n * 3] += Int(p[i]); sums[n * 3 + 1] += Int(p[i + 1]); sums[n * 3 + 2] += Int(p[i + 2])
        }
        return (count, sums, { n, c in Int(keys[n] >> (16 - 8 * UInt32(c)) & 255) })
    }

    private static func buckets(_ image: RGBAImage) -> (count: [Int], sums: [Int], channel: (Int, Int) -> Int) {
        var count = [Int](repeating: 0, count: 1 << 15)
        var sums = [Int](repeating: 0, count: 3 << 15)
        let p = image.pixels
        for i in stride(from: 0, to: p.count, by: 4) where p[i + 3] > 0 {
            let k = bucket(Int(p[i]), Int(p[i + 1]), Int(p[i + 2]))
            count[k] += 1
            sums[k * 3] += Int(p[i]); sums[k * 3 + 1] += Int(p[i + 1]); sums[k * 3 + 2] += Int(p[i + 2])
        }
        return (count, sums, { k, c in k >> (10 - 5 * c) & 31 })
    }

    /// Median cut over the histogram's entries; each box's mean is its colour.
    private static func medianCut(_ image: RGBAImage, colours: Int) -> [(r: Int, g: Int, b: Int)] {
        let (count, sums, channel) = histogram(image)
        var boxes = [count.indices.filter { count[$0] > 0 }]
        if boxes[0].isEmpty { return [(0, 0, 0)] }
        while boxes.count < colours {
            // Split the box with the most pixels that still holds more than one entry.
            var best = -1, bestPixels = 0
            for (n, box) in boxes.enumerated() where box.count > 1 {
                let pixels = box.reduce(0) { $0 + count[$1] }
                if pixels > bestPixels { best = n; bestPixels = pixels }
            }
            guard best >= 0 else { break }
            let box = boxes[best]
            let axis = (0..<3).max { a, b in
                let ra = box.map { channel($0, a) }, rb = box.map { channel($0, b) }
                return ra.max()! - ra.min()! < rb.max()! - rb.min()!
            }!
            let sorted = box.sorted { channel($0, axis) < channel($1, axis) }
            var running = 0, cut = 1
            for (n, k) in sorted.enumerated() {
                running += count[k]
                if running * 2 >= bestPixels { cut = max(1, min(sorted.count - 1, n + 1)); break }
            }
            boxes[best] = Array(sorted[..<cut])
            boxes.append(Array(sorted[cut...]))
        }
        return boxes.map { box in
            var n = 0, r = 0, g = 0, b = 0
            for k in box { n += count[k]; r += sums[k * 3]; g += sums[k * 3 + 1]; b += sums[k * 3 + 2] }
            return ((r + n / 2) / n, (g + n / 2) / n, (b + n / 2) / n)
        }
    }

    private static func map(_ image: RGBAImage, palette: [(r: Int, g: Int, b: Int)], dither: Bool) -> RGBAImage {
        // Per 5-bit bucket, filled on first use: the palette entries that can be nearest to some colour in it
        // (nearest possible distance no more than the smallest farthest distance), then an exact search among those.
        var start = [Int32](repeating: -1, count: 1 << 15), length = [Int16](repeating: 0, count: 1 << 15)
        var candidates = [Int16]()
        var near = [Int](repeating: 0, count: palette.count)
        func axis(_ v: Int, _ lo: Int) -> (near: Int, far: Int) {
            let d = v < lo ? lo - v : v > lo + 7 ? v - lo - 7 : 0, f = max(abs(v - lo), abs(v - lo - 7))
            return (d * d, f * f)
        }
        func nearest(_ r: Int, _ g: Int, _ b: Int) -> Int {
            let k = bucket(r, g, b)
            if start[k] < 0 {
                var bound = Int.max
                for (n, c) in palette.enumerated() {
                    let x = axis(c.r, r & ~7), y = axis(c.g, g & ~7), z = axis(c.b, b & ~7)
                    near[n] = x.near + y.near + z.near
                    bound = min(bound, x.far + y.far + z.far)
                }
                start[k] = Int32(candidates.count)
                for n in palette.indices where near[n] <= bound { candidates.append(Int16(n)) }
                length[k] = Int16(candidates.count - Int(start[k]))
            }
            var best = 0, bestDistance = Int.max
            for j in Int(start[k])..<Int(start[k]) + Int(length[k]) {
                let n = Int(candidates[j]), c = palette[n]
                let d = (c.r - r) * (c.r - r) + (c.g - g) * (c.g - g) + (c.b - b) * (c.b - b)
                if d < bestDistance { best = n; bestDistance = d }
            }
            return best
        }
        var out = image
        let w = image.width
        var error = [Float](repeating: 0, count: (w + 2) * 2 * 3)
        for y in 0..<image.height {
            let row = (y & 1) * (w + 2) * 3, next = (1 - (y & 1)) * (w + 2) * 3
            for x in 0..<w {
                let i = (y * w + x) * 4
                func wanted(_ c: Int) -> Float { Float(image.pixels[i + c]) + (dither ? error[row + (x + 1) * 3 + c] : 0) }
                func level(_ c: Int) -> Int { min(255, max(0, Int(wanted(c).rounded()))) }
                let q = palette[nearest(level(0), level(1), level(2))]
                out.pixels[i] = UInt8(q.r); out.pixels[i + 1] = UInt8(q.g); out.pixels[i + 2] = UInt8(q.b)
                guard dither else { continue }
                for c in 0..<3 {
                    let e = wanted(c) - Float(c == 0 ? q.r : c == 1 ? q.g : q.b)
                    error[row + (x + 2) * 3 + c] += e * 7 / 16
                    error[next + x * 3 + c] += e * 3 / 16
                    error[next + (x + 1) * 3 + c] += e * 5 / 16
                    error[next + (x + 2) * 3 + c] += e / 16
                }
            }
            for x in 0..<(w + 2) * 3 { error[row + x] = 0 }
        }
        return out
    }
}
