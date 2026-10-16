/// A transparent canvas that layers are drawn onto one at a time with normal (source-over) blending,
/// in straight alpha, so a decoder holds the canvas plus one layer, never every layer at once.
struct LayerCanvas {
    private(set) var image: RGBAImage

    init(width: Int, height: Int) throws {
        let (width, height) = try checkedSize(width, height)
        image = RGBAImage(width: width, height: height, pixels: [UInt8](repeating: 0, count: width * height * 4))
    }

    /// Draws `layer` with its top-left corner at (`x`, `y`), which may be negative or past the edge;
    /// only the overlap with the canvas changes. `opacity` (0…1) multiplies the layer's alpha.
    mutating func draw(_ layer: RGBAImage, x: Int, y: Int, opacity: Double) {
        let opacity = min(max(opacity, 0), 1)
        let x0 = max(x, 0), x1 = min(x + layer.width, image.width)
        let y0 = max(y, 0), y1 = min(y + layer.height, image.height)
        guard opacity > 0, x0 < x1, y0 < y1 else { return }
        let canvasWidth = image.width
        layer.pixels.withUnsafeBufferPointer { src in
            image.pixels.withUnsafeMutableBufferPointer { dst in
                for row in y0..<y1 {
                    var s = ((row - y) * layer.width + (x0 - x)) * 4
                    var d = (row * canvasWidth + x0) * 4
                    for _ in x0..<x1 {
                        let aS = Double(src[s + 3]) / 255 * opacity
                        if aS >= 1 {
                            for c in 0..<4 { dst[d + c] = src[s + c] }
                        } else if aS > 0 {
                            let aD = Double(dst[d + 3]) / 255
                            let keep = aD * (1 - aS)
                            let aO = aS + keep
                            for c in 0..<3 {
                                dst[d + c] = UInt8((Double(src[s + c]) * aS + Double(dst[d + c]) * keep) / aO + 0.5)
                            }
                            dst[d + 3] = UInt8(aO * 255 + 0.5)
                        }
                        s += 4; d += 4
                    }
                }
            }
        }
    }
}
