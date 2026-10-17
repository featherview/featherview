import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Generated test images for `decode` and `browse`. Never committed: run `corpus <dir>` on each Mac.
enum Corpus {
    private struct File {
        let name: String
        let width: Int, height: Int
        let type: UTType
        var quality: Double = 0.9
        var orientation = 1
        var seed: UInt32 = 0
    }

    static func write(to dir: URL) throws {
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("browse"), withIntermediateDirectories: true)
        var files = [
            File(name: "12mp-landscape.jpg", width: 4032, height: 3024, type: .jpeg),
            File(name: "12mp-portrait.jpg", width: 3024, height: 4032, type: .jpeg),
            // Stored landscape, displayed portrait.
            File(name: "12mp-portrait-exif6.jpg", width: 4032, height: 3024, type: .jpeg, orientation: 6),
            File(name: "50mp-landscape.jpg", width: 8688, height: 5792, type: .jpeg),
            File(name: "50mp-portrait.jpg", width: 5792, height: 8688, type: .jpeg),
            File(name: "12mp-landscape.heic", width: 4032, height: 3024, type: .heic, quality: 0.8),
            File(name: "12mp-portrait.heic", width: 3024, height: 4032, type: .heic, quality: 0.8),
            File(name: "12mp.png", width: 4000, height: 3000, type: .png),
        ]
        for i in 1...40 {
            let landscape = i % 2 == 1
            files.append(File(name: String(format: "browse/%04d.jpg", i), width: landscape ? 4032 : 3024,
                              height: landscape ? 3024 : 4032, type: .jpeg, seed: UInt32(i)))
        }
        for file in files {
            let url = dir.appendingPathComponent(file.name)
            try save(image(width: file.width, height: file.height, seed: file.seed), to: url, file: file)
            let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            print("\(file.name)  \(file.width)×\(file.height)  \(String(format: "%.1f", Double(bytes) / 1_000_000)) MB")
        }
    }

    /// A diagonal gradient plus per-pixel noise: a solid colour would compress to nothing and decode unrealistically fast.
    private static func image(width: Int, height: Int, seed: UInt32) -> CGImage {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        pixels.withUnsafeMutableBufferPointer { buffer in
            for y in 0..<height {
                for x in 0..<width {
                    let noise = hash(UInt32(x), UInt32(y), seed)
                    let i = (y * width + x) * 4
                    buffer[i] = channel((x + y) * 255 / (width + height), noise)
                    buffer[i + 1] = channel(x * 255 / width, noise >> 8)
                    buffer[i + 2] = channel(y * 255 / height, noise >> 16)
                }
            }
        }
        let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        return context.makeImage()!
    }

    private static func channel(_ base: Int, _ noise: UInt32) -> UInt8 {
        UInt8(clamping: base + Int(noise & 0x0F) - 8)
    }

    /// Deterministic, so every Mac gets the same files.
    private static func hash(_ x: UInt32, _ y: UInt32, _ seed: UInt32) -> UInt32 {
        var h = x &* 0x9E37_79B1 ^ y &* 0x85EB_CA77 ^ seed &* 0xC2B2_AE3D
        h ^= h >> 15
        h = h &* 0x2C1B_3C6D
        h ^= h >> 12
        return h
    }

    private static func save(_ image: CGImage, to url: URL, file: File) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, file.type.identifier as CFString, 1, nil)
        else { throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path]) }
        var properties: [CFString: Any] = [kCGImagePropertyOrientation: file.orientation]
        if file.type != .png { properties[kCGImageDestinationLossyCompressionQuality] = file.quality }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination)
        else { throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path]) }
    }
}
