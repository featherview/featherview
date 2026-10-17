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
                guard image.pixels[i + 3] != 0 else { continue }  // invisible: no error to pass on
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
        for i in stride(from: 0, to: p.count, by: 4) where p[i + 3] > 0 {
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
        // Open addressing at most half full (a Dictionary costs a second per 24 MP): slot → entry + 1, 0 = empty.
        let limit = 1 << 16, mask = limit * 2 - 1
        var slots = [Int32](repeating: 0, count: limit * 2)
        var count = [Int](), keys = [UInt32]()
        count.reserveCapacity(limit); keys.reserveCapacity(limit)
        let full = image.pixels.withUnsafeBufferPointer { p in
            slots.withUnsafeMutableBufferPointer { slots in
                for i in stride(from: 0, to: p.count, by: 4) where p[i + 3] > 0 {
                    let key = UInt32(p[i]) << 16 | UInt32(p[i + 1]) << 8 | UInt32(p[i + 2])
                    var s = Int((key &* 0x9E37_79B1) >> 15) & mask
                    while true {
                        let n = Int(slots[s]) - 1
                        if n < 0 {
                            if keys.count == limit { return true }
                            slots[s] = Int32(keys.count + 1); keys.append(key); count.append(1)
                            break
                        }
                        if keys[n] == key { count[n] += 1; break }
                        s = (s + 1) & mask
                    }
                }
                return false
            }
        }
        if full { return buckets(image) }
        var sums = [Int](repeating: 0, count: keys.count * 3)
        for (n, key) in keys.enumerated() {
            for c in 0..<3 { sums[n * 3 + c] = count[n] * Int(key >> (16 - 8 * UInt32(c)) & 255) }
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
        var nearest = Nearest(palette: palette)
        var out = image.pixels
        let w = image.width, h = image.height
        guard dither else {
            var last: UInt32 = .max, lastIndex = 0 // runs of one colour skip the search
            for i in stride(from: 0, to: out.count, by: 4) {
                let key = UInt32(out[i]) << 16 | UInt32(out[i + 1]) << 8 | UInt32(out[i + 2])
                if key != last { last = key; lastIndex = nearest(Int(out[i]), Int(out[i + 1]), Int(out[i + 2])) }
                let q = palette[lastIndex]
                out[i] = UInt8(q.r); out[i + 1] = UInt8(q.g); out[i + 2] = UInt8(q.b)
            }
            return RGBAImage(width: w, height: h, pixels: out)
        }
        // Floyd–Steinberg is one long chain of dependent steps per row (latency-bound); two rows at once, the lower
        // one two pixels behind (all it needs from the upper row is done by then), give the CPU two chains to overlap.
        // 16 × the error, in integers (the weights are sixteenths): three rows, one pad each side.
        let stride = (w + 2) * 3
        var error = [Int32](repeating: 0, count: stride * 3)
        out.withUnsafeMutableBufferPointer { p in
            error.withUnsafeMutableBufferPointer { error in
                for y in Swift.stride(from: 0, to: h, by: 2) {
                    for r in 1...2 { let base = (y + r) % 3 * stride; for x in 0..<stride { error[base + x] = 0 } }
                    for x in 0..<w + 2 {
                        if x < w { step(p, error, x, y, w, stride, palette, &nearest) }
                        if x >= 2, y + 1 < h { step(p, error, x - 2, y + 1, w, stride, palette, &nearest) }
                    }
                }
            }
        }
        return RGBAImage(width: w, height: h, pixels: out)
    }

    /// One dithered pixel: wanted colour (pixel + incoming error), nearest entry, error passed on.
    /// Wrapping arithmetic: no overflow checks on the hot path (all values are small).
    @inline(__always) private static func step(_ out: UnsafeMutableBufferPointer<UInt8>, _ error: UnsafeMutableBufferPointer<Int32>,
                                               _ x: Int, _ y: Int, _ w: Int, _ stride: Int,
                                               _ palette: [(r: Int, g: Int, b: Int)], _ nearest: inout Nearest) {
        let i = (y &* w &+ x) &* 4, row = y % 3 &* stride, next = (y &+ 1) % 3 &* stride
        guard out[i + 3] != 0 else { return }  // invisible: not in the palette, so no error to pass on
        let e = row &+ (x &+ 1) &* 3
        let wr = Int32(out[i]) &+ (error[e] &+ 8) >> 4, wg = Int32(out[i + 1]) &+ (error[e + 1] &+ 8) >> 4
        let wb = Int32(out[i + 2]) &+ (error[e + 2] &+ 8) >> 4
        let q = palette[nearest(Int(min(255, max(0, wr))), Int(min(255, max(0, wg))), Int(min(255, max(0, wb))))]
        out[i] = UInt8(truncatingIfNeeded: q.r); out[i + 1] = UInt8(truncatingIfNeeded: q.g); out[i + 2] = UInt8(truncatingIfNeeded: q.b)
        let d = (wr &- Int32(truncatingIfNeeded: q.r), wg &- Int32(truncatingIfNeeded: q.g), wb &- Int32(truncatingIfNeeded: q.b))
        let ahead = row &+ (x &+ 2) &* 3, below = next &+ x &* 3
        error[ahead] &+= d.0 &* 7; error[ahead + 1] &+= d.1 &* 7; error[ahead + 2] &+= d.2 &* 7
        error[below] &+= d.0 &* 3; error[below + 1] &+= d.1 &* 3; error[below + 2] &+= d.2 &* 3
        error[below + 3] &+= d.0 &* 5; error[below + 4] &+= d.1 &* 5; error[below + 5] &+= d.2 &* 5
        error[below + 6] &+= d.0; error[below + 7] &+= d.1; error[below + 8] &+= d.2
    }

    /// The nearest palette entry. Per cell, filled on first use: the palette entries that can be nearest to some
    /// colour in it (nearest possible distance no more than the smallest farthest distance), then an exact search
    /// among those. 4-wide cells keep the lists short; each takes its list from its 8-wide parent, not the whole palette.
    private struct Nearest {
        let palette: [(r: Int, g: Int, b: Int)]
        var coarse = Cells(bits: 5), fine = Cells(bits: 6)
        lazy var all = palette.indices.map { Int16($0) }

        @inline(__always) mutating func callAsFunction(_ r: Int, _ g: Int, _ b: Int) -> Int {
            let k = (r >> 2) << 12 | (g >> 2) << 6 | (b >> 2)
            var v = Int(fine.cell[k])
            if v == -1 { v = fill(k, r, g, b) }
            if v <= -2 { return -2 - v }
            var best = 0, bestDistance = Int.max
            for j in v + 1...v + Int(fine.lists[v]) {
                let n = Int(fine.lists[j]), c = palette[n]
                let dr = c.r &- r, dg = c.g &- g, db = c.b &- b, d = dr &* dr &+ dg &* dg &+ db &* db // wrapping: no overflow checks in the hot loop
                if d < bestDistance { best = n; bestDistance = d }
            }
            return best
        }

        @inline(never) mutating func fill(_ k: Int, _ r: Int, _ g: Int, _ b: Int) -> Int {
            let c = bucket(r, g, b)
            if coarse.cell[c] == -1 { coarse.fill(c, r, g, b, palette, from: all[...]) }
            fine.fill(k, r, g, b, palette, from: coarse.list(c))
            return Int(fine.cell[k])
        }
    }

    /// Candidate lists of palette entries per cube of side 2^(8 - bits), for `map`.
    private struct Cells {
        let bits: Int
        /// -1 not filled yet; -2 - n when entry n is the only candidate; else the offset of [count, entries…] in `lists`.
        var cell: [Int32], lists = [Int16]()
        init(bits: Int) {
            self.bits = bits
            cell = [Int32](repeating: -1, count: 1 << (3 * bits))
        }

        func list(_ k: Int) -> ArraySlice<Int16> {
            let v = Int(cell[k])
            return v <= -2 ? [Int16(-2 - v)][...] : lists[v + 1...v + Int(lists[v])]
        }

        mutating func fill(_ k: Int, _ r: Int, _ g: Int, _ b: Int, _ palette: [(r: Int, g: Int, b: Int)],
                           from: ArraySlice<Int16>) {
            let side = (1 << (8 - bits)) - 1, mask = ~side
            func axis(_ v: Int, _ lo: Int) -> (near: Int, far: Int) {
                let d = v < lo ? lo - v : v > lo + side ? v - lo - side : 0, f = max(abs(v - lo), abs(v - lo - side))
                return (d * d, f * f)
            }
            var bound = Int.max
            let start = lists.count
            lists.append(0)
            withUnsafeTemporaryAllocation(of: Int.self, capacity: from.count) { near in
                for (j, n) in from.enumerated() {
                    let c = palette[Int(n)], x = axis(c.r, r & mask), y = axis(c.g, g & mask), z = axis(c.b, b & mask)
                    near[j] = x.near + y.near + z.near
                    bound = min(bound, x.far + y.far + z.far)
                }
                for (j, n) in from.enumerated() where near[j] <= bound { lists.append(n) }
            }
            let count = lists.count - start - 1
            if count == 1 { cell[k] = Int32(-2 - Int(lists[start + 1])); lists.removeLast(2) } else {
                lists[start] = Int16(count); cell[k] = Int32(start)
            }
        }
    }
}
