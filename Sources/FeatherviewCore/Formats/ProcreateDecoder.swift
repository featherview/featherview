import Compression
import CoreGraphics
import Foundation
import os

/// Procreate (.procreate), shown at full size from the flattened picture the app keeps in the file.
///
/// The file is a zip (`ZipArchive`) holding:
/// - `Document.archive`: an NSKeyedArchiver binary plist whose root is a `SilicaDocument` with `size`
///   ("{width, height}", the canvas in pixels), `tileSize` (256), `orientation` (1 none, 2 180°,
///   3 270° and 4 90° clockwise: how the canvas was turned, which the stored preview shows too),
///   `flippedHorizontally` / `flippedVertically`, `colorProfile` (a `ValkyrieColorProfile` with the ICC
///   bytes under `SiColorProfileArchiveICCDataKey`), the layers, and `composite`: a `SilicaLayer`
///   whose `UUID` names the folder with the flattened picture, background included.
/// - `<UUID>/<col>~<row>.chunk` (LZO1X) or `.lz4` (LZ4 in Apple's `bv41` block frames, newer
///   Procreate versions; one file can mix both): one tile each, `tileSize` square, clipped at the
///   canvas's right and top edges. Rows count up from the bottom of the canvas, and the lines inside a
///   tile run bottom to top too. Pixels are 8-bit RGBA, premultiplied. A missing tile is transparent.
/// - `QuickLook/Thumbnail.png`: a preview at most 1024 pixels wide, used when the composite can't be read.
// shortcut: the flips are applied to the canvas before it is turned, like the open-source viewers; no sample with a flip set was at hand, check one if a flipped file shows mirrored wrongly.
enum ProcreateDecoder {
    static let format = OwnFormat(
        name: "Procreate", extensions: ["procreate"],
        size: { data, page in (try? Canvas(data))?.displaySize ?? preview.size(data, page) },
        decode: { data, page, maxPixelSize in
            // The tiles are needed at full size whatever the target, so maxPixelSize only reaches the preview.
            do { return try Canvas(data).decode() } catch { return try preview.decode(data, page, maxPixelSize) }
        })

    private static let preview = ZippedImage.format(name: "Procreate", extensions: ["procreate"],
                                                    entry: "QuickLook/Thumbnail.png")

    private struct Canvas {
        let zip: ZipArchive
        let width, height, tileSize, orientation: Int
        let flippedHorizontally, flippedVertically: Bool
        let icc: Data?
        let tiles: [(col: Int, row: Int, name: String)]

        var turned: Bool { orientation == 3 || orientation == 4 }
        var displaySize: CGSize { turned ? CGSize(width: height, height: width) : CGSize(width: width, height: height) }

        init(_ data: Data) throws {
            zip = try ZipArchive(data)
            guard let archive = try zip.read("Document.archive") else { throw OwnDecodeError.unsupported }
            let unarchiver = try NSKeyedUnarchiver(forReadingFrom: archive)
            unarchiver.setClass(SilicaDocument.self, forClassName: "SilicaDocument")
            unarchiver.setClass(SilicaLayer.self, forClassName: "SilicaLayer")
            unarchiver.setClass(ColorProfile.self, forClassName: "ValkyrieColorProfile")
            guard let document = unarchiver.decodeObject(of: SilicaDocument.self, forKey: NSKeyedArchiveRootObjectKey),
                  let uuid = document.composite, !uuid.isEmpty, !uuid.contains("/"),
                  let size = document.size?.trimmingCharacters(in: CharacterSet(charactersIn: "{} ")),
                  case let parts = size.split(separator: ",").compactMap({ Int($0.trimmingCharacters(in: .whitespaces)) }),
                  parts.count == 2, case let tileSize = document.tileSize, (1...4096).contains(tileSize)
            else { throw OwnDecodeError.unsupported }
            (width, height) = try checkedSize(parts[0], parts[1])
            self.tileSize = tileSize
            orientation = document.orientation
            flippedHorizontally = document.flippedHorizontally
            flippedVertically = document.flippedVertically
            icc = document.icc
            let cols = (width + tileSize - 1) / tileSize, rows = (height + tileSize - 1) / tileSize
            tiles = try zip.entries.keys.filter { $0.hasPrefix(uuid + "/") }.map { name in
                let file = name.dropFirst(uuid.count + 1)
                guard file.hasSuffix(".chunk") || file.hasSuffix(".lz4") else { throw OwnDecodeError.unsupported }
                let position = file.prefix { $0 != "." }.split(separator: "~").compactMap { Int($0) }
                guard position.count == 2, (0..<cols).contains(position[0]), (0..<rows).contains(position[1])
                else { throw OwnDecodeError.corrupt }
                return (position[0], position[1], name)
            }
            guard !tiles.isEmpty else { throw OwnDecodeError.unsupported }
            guard Set(tiles.map { $0.col << 32 | $0.row }).count == tiles.count else { throw OwnDecodeError.corrupt }
        }

        func decode() throws -> CGImage {
            let size = displaySize, outWidth = Int(size.width)
            // Where canvas pixel (x, y), counted from the top, lands in the output: flip, then turn.
            func place(_ x: Int, _ y: Int) -> Int {
                let fx = flippedHorizontally ? width - 1 - x : x, fy = flippedVertically ? height - 1 - y : y
                let (ox, oy) = switch orientation {
                case 2: (width - 1 - fx, height - 1 - fy)
                case 3: (fy, width - 1 - fx)
                case 4: (height - 1 - fy, fx)
                default: (fx, fy)
                }
                return oy * outWidth + ox
            }
            let origin = place(0, 0), dx = place(1, 0) - origin, dy = place(0, 1) - origin
            var pixels = Data(count: width * height * 4)
            // Tiles cover separate pixels, so they decode in parallel; a missing tile leaves transparent pixels.
            let result = OSAllocatedUnfairLock<(error: Error?, opaque: Bool)>(
                initialState: (nil, tiles.count == (width + tileSize - 1) / tileSize * ((height + tileSize - 1) / tileSize)))
            pixels.withUnsafeMutableBytes { raw in
                nonisolated(unsafe) let out = raw.bindMemory(to: UInt32.self)  // each tile writes its own pixels
                DispatchQueue.concurrentPerform(iterations: tiles.count) { index in
                    let tile = tiles[index]
                    let tileWidth = min(tileSize, width - tile.col * tileSize)
                    let tileHeight = min(tileSize, height - tile.row * tileSize)
                    let bytes: [UInt8]
                    do { bytes = try tileBytes(tile.name, count: tileWidth * tileHeight * 4) } catch {
                        result.withLock { $0.error = error }
                        return
                    }
                    var alpha: UInt32 = 0xFF00_0000
                    // Tile pixel (i, line) goes to `bottomLeft + i * dx - line * dy`: lines run up the canvas.
                    let bottomLeft = origin + tile.col * tileSize * dx + (height - 1 - tile.row * tileSize) * dy
                    // The inner loop walks whichever tile axis is contiguous in the output, for the cache.
                    let (outerCount, innerCount, outerStep, innerStep, outerSource, innerSource) = abs(dx) == 1
                        ? (tileHeight, tileWidth, -dy, dx, tileWidth, 1)
                        : (tileWidth, tileHeight, dx, -dy, 1, tileWidth)
                    bytes.withUnsafeBytes { src in
                        for o in 0..<outerCount {
                            var at = bottomLeft + o * outerStep, from = o * outerSource
                            for _ in 0..<innerCount {
                                let pixel = src.loadUnaligned(fromByteOffset: from * 4, as: UInt32.self)
                                out[at] = pixel
                                alpha &= pixel
                                at += innerStep
                                from += innerSource
                            }
                        }
                    }
                    if alpha < 0xFF00_0000 { result.withLock { $0.opaque = false } }
                }
            }
            let (error, opaque) = result.withLock { $0 }
            if let error { throw error }
            let info: CGImageAlphaInfo = opaque ? .noneSkipLast : .premultipliedLast
            guard let space = icc.flatMap({ CGColorSpace(iccData: $0 as CFData) }).flatMap({ $0.model == .rgb ? $0 : nil })
                    ?? CGColorSpace(name: CGColorSpace.sRGB),
                  let provider = CGDataProvider(data: pixels as CFData),
                  let image = CGImage(width: outWidth, height: Int(size.height), bitsPerComponent: 8, bitsPerPixel: 32,
                                      bytesPerRow: outWidth * 4, space: space, bitmapInfo: CGBitmapInfo(rawValue: info.rawValue),
                                      provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
            else { throw OwnDecodeError.corrupt }
            return image
        }

        private func tileBytes(_ name: String, count: Int) throws -> [UInt8] {
            guard let data = try zip.read(name) else { throw OwnDecodeError.corrupt }
            let input = [UInt8](data)
            guard name.hasSuffix(".lz4") else { return try LZO1X.decompress(input, size: count) }
            // Apple's LZ4 decoder reads the bv41 frames and never writes past `count`; one byte more shows an overlong tile.
            var output = [UInt8](repeating: 0, count: count + 1)
            guard compression_decode_buffer(&output, output.count, input, input.count, nil, COMPRESSION_LZ4) == count
            else { throw OwnDecodeError.corrupt }
            output.removeLast()
            return output
        }
    }
}

// The few `Document.archive` objects the decoder reads; NSKeyedUnarchiver maps Procreate's class names to them.

@objc(FeatherviewProcreateDocument) private final class SilicaDocument: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool { true }
    let size: String?, tileSize: Int, orientation: Int, composite: String?, icc: Data?
    let flippedHorizontally, flippedVertically: Bool

    required init?(coder: NSCoder) {
        size = coder.decodeObject(of: NSString.self, forKey: "size") as String?
        // Numbers and flags are stored inline, not as objects.
        tileSize = coder.decodeInteger(forKey: "tileSize")
        orientation = coder.decodeInteger(forKey: "orientation")
        flippedHorizontally = coder.decodeBool(forKey: "flippedHorizontally")
        flippedVertically = coder.decodeBool(forKey: "flippedVertically")
        composite = coder.decodeObject(of: SilicaLayer.self, forKey: "composite")?.uuid
        icc = coder.decodeObject(of: ColorProfile.self, forKey: "colorProfile")?.icc
    }

    func encode(with coder: NSCoder) {}  // read only: Featherview never writes Procreate files
}

@objc(FeatherviewProcreateLayer) private final class SilicaLayer: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool { true }
    let uuid: String?
    required init?(coder: NSCoder) { uuid = coder.decodeObject(of: NSString.self, forKey: "UUID") as String? }
    func encode(with coder: NSCoder) {}
}

@objc(FeatherviewProcreateColorProfile) private final class ColorProfile: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool { true }
    let icc: Data?
    required init?(coder: NSCoder) { icc = coder.decodeObject(of: NSData.self, forKey: "SiColorProfileArchiveICCDataKey") as Data? }
    func encode(with coder: NSCoder) {}
}
