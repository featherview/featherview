import CoreGraphics

/// 8-bit RGBA pixels, straight (not premultiplied) alpha, rows top to bottom: what our own decoders
/// produce and our own encoders consume.
public struct RGBAImage: Equatable, Sendable {
    public let width: Int
    public let height: Int
    /// `width * height * 4` bytes: R, G, B, A per pixel.
    public var pixels: [UInt8]

    public init(width: Int, height: Int, pixels: [UInt8]) {
        precondition(pixels.count == width * height * 4, "pixel buffer size")
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// Opaque black.
    public init(width: Int, height: Int) {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for i in stride(from: 3, to: pixels.count, by: 4) { pixels[i] = 255 }
        self.init(width: width, height: height, pixels: pixels)
    }

    /// Reads any CGImage as sRGB RGBA; the alpha is un-premultiplied again.
    public init?(_ image: CGImage) {
        let width = image.width, height = image.height
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var pixels = Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: width * height * 4))
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Int(pixels[i + 3])
            guard alpha > 0, alpha < 255 else { continue }
            for c in 0..<3 { pixels[i + c] = UInt8(min(255, (Int(pixels[i + c]) * 255 + alpha / 2) / alpha)) }
        }
        self.init(width: width, height: height, pixels: pixels)
    }

    public subscript(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        get {
            let i = (y * width + x) * 4
            return (pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3])
        }
        set {
            let i = (y * width + x) * 4
            pixels[i] = newValue.r; pixels[i + 1] = newValue.g; pixels[i + 2] = newValue.b; pixels[i + 3] = newValue.a
        }
    }

    public var isOpaque: Bool { stride(from: 3, to: pixels.count, by: 4).allSatisfy { pixels[$0] == 255 } }

    /// A CGImage in sRGB. Opaque images get no alpha channel, so the viewer shows no checkerboard.
    public func makeCGImage() -> CGImage? {
        let opaque = isOpaque
        let info: CGImageAlphaInfo = opaque ? .noneSkipLast : .last
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: info.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

import Foundation

/// Why one of our own decoders gave up. The viewer shows "Can't open <name>" either way.
public enum OwnDecodeError: Error, Equatable {
    case notThisFormat, truncated, corrupt, unsupported
}

/// Reads a file's bytes front to back; every read past the end throws `.truncated` instead of trapping.
/// Reads straight from the `Data` without copying it, so a header read of a mapped file touches only
/// the pages it reads.
struct ByteReader {
    let data: Data
    var offset = 0

    init(_ bytes: [UInt8]) { self.data = Data(bytes) }
    init(_ data: Data) { self.data = data }

    var remaining: Int { data.count - offset }
    var isAtEnd: Bool { offset >= data.count }

    mutating func u8() throws -> UInt8 {
        guard offset < data.count else { throw OwnDecodeError.truncated }
        defer { offset += 1 }
        return data[data.startIndex + offset]
    }

    mutating func u16le() throws -> Int { Int(try u8()) | Int(try u8()) << 8 }
    mutating func u16be() throws -> Int { Int(try u8()) << 8 | Int(try u8()) }
    mutating func u32be() throws -> Int { try u16be() << 16 | u16be() }
    mutating func u32le() throws -> Int { try u16le() | u16le() << 16 }

    mutating func take(_ count: Int) throws -> ArraySlice<UInt8> {
        guard count >= 0, count <= remaining else { throw OwnDecodeError.truncated }
        defer { offset += count }
        let start = data.startIndex + offset
        return ArraySlice(data[start..<start + count])
    }

    mutating func skip(_ count: Int) throws { _ = try take(count) }
}

/// Pixel counts our decoders accept: a corrupt header can't make them allocate gigabytes.
// shortcut: 256 megapixels, the largest of our formats' real files are far below; raise it if one isn't.
let maxOwnPixels = 1 << 28

func checkedSize(_ width: Int, _ height: Int) throws -> (Int, Int) {
    guard width > 0, height > 0, width <= 1 << 16, height <= 1 << 16, width * height <= maxOwnPixels
    else { throw OwnDecodeError.corrupt }
    return (width, height)
}
