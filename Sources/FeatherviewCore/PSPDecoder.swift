import CoreGraphics
import Foundation
import ImageIO

/// PaintShop Pro images (file format 4 and up, PaintShop Pro 6 and later), shown flattened: the stored
/// full-size composite when there is one, otherwise the raster layers composited bottom to top.
/// Little-endian blocks (`~BK\0`, id, length) holding chunks that start with their own length.
// shortcut: vector, adjustment, mask and art-media layers are skipped (the composite, when stored, includes them), render them if files without a composite need them.
// shortcut: user masks are ignored and every blend mode is drawn as normal, apply them if a real file looks wrong without.
// shortcut: group layers aren't honoured (the spec gives a group's layer count, not which layers it holds), so a hidden or faded group's layers draw as if it were visible and opaque; files with groups store a composite, which is used first.
enum PSPDecoder {
    static let format = OwnFormat.raster(name: "PaintShop Pro", extensions: ["psp", "pspimage"],
                                         size: { data, _ in try size(data) },
                                         decode: { data, _ in try decode(data) })

    private static let signature = Array("Paint Shop Pro Image File\n\u{1A}".utf8) + [0, 0, 0, 0, 0]
    private static let blockMagic: [UInt8] = [0x7E, 0x42, 0x4B, 0x00]

    private enum Block {
        static let image = 0, palette = 2, layerBank = 3, layer = 4, channel = 5
        static let composite = 9, compositeBank = 16, compositeAttributes = 17, jpeg = 18
    }

    private enum Compression { static let none = 0, rle = 1, lz77 = 2, jpeg = 3 }

    private struct Attributes {
        let width, height, compression, bitDepth: Int
        let greyscale: Bool
    }

    private typealias Palette = [(r: UInt8, g: UInt8, b: UInt8)]

    static func size(_ data: Data) throws -> (width: Int, height: Int) {
        var reader = ByteReader(data)
        let attributes = try header(&reader)
        return (attributes.width, attributes.height)
    }

    static func decode(_ data: Data) throws -> RGBAImage {
        var reader = ByteReader(data)
        let attributes = try header(&reader)
        // Note where the main blocks are first: their order is free, except that the composite bank comes
        // before the layer bank, and the palette can be anywhere.
        var palette: Palette = []
        var compositeBank: (start: Int, end: Int)?, layerBank: (start: Int, end: Int)?
        while !reader.isAtEnd {
            let (id, end) = try blockHeader(&reader, end: data.count)
            switch id {
            case Block.palette: palette = try readPalette(&reader, end: end)
            case Block.compositeBank: compositeBank = (reader.offset, end)
            case Block.layerBank: layerBank = (reader.offset, end)
            default: break
            }
            reader.offset = end
        }
        if let compositeBank {
            reader.offset = compositeBank.start
            if let image = try composite(&reader, end: compositeBank.end, attributes: attributes) { return image }
        }
        guard let layerBank else { throw OwnDecodeError.corrupt }
        reader.offset = layerBank.start
        return try layers(&reader, end: layerBank.end, attributes: attributes, palette: palette)
    }

    // MARK: - Structure

    /// File header and General Image Attributes block; leaves the reader after that block.
    private static func header(_ reader: inout ByteReader) throws -> Attributes {
        guard reader.remaining >= 36, Array(try reader.take(32)) == signature else { throw OwnDecodeError.notThisFormat }
        let major = try reader.u16le()
        try reader.skip(2)
        // shortcut: format 3 (PaintShop Pro 5) has another block header and isn't read, add it if such a file turns up.
        guard major >= 4 else { throw OwnDecodeError.unsupported }
        let (id, end) = try blockHeader(&reader, end: reader.data.count)
        guard id == Block.image else { throw OwnDecodeError.corrupt }
        _ = try chunkStart(&reader, end: end, minimum: 46)
        let width = try long(&reader), height = try long(&reader)
        try reader.skip(9)  // resolution, metric
        let compression = try reader.u16le(), bitDepth = try reader.u16le()
        try reader.skip(6)  // planes, colour count
        let greyscale = try reader.u8() != 0
        guard compression <= Compression.lz77 else { throw OwnDecodeError.corrupt }
        // shortcut: 48-bit (16 bits per channel) images aren't read, convert them to 8 bits if one turns up.
        guard bitDepth != 48 else { throw OwnDecodeError.unsupported }
        guard [1, 4, 8, 24].contains(bitDepth) else { throw OwnDecodeError.corrupt }
        _ = try checkedSize(width, height)
        reader.offset = end
        return Attributes(width: width, height: height, compression: compression, bitDepth: bitDepth, greyscale: greyscale)
    }

    /// Reads `~BK\0`, the id and the length; returns the id and where the block ends (checked against `end`).
    private static func blockHeader(_ reader: inout ByteReader, end: Int) throws -> (id: Int, end: Int) {
        guard Array(try reader.take(4)) == blockMagic else { throw OwnDecodeError.corrupt }
        let id = try reader.u16le(), length = try reader.u32le()
        guard length <= end - reader.offset else { throw OwnDecodeError.truncated }
        return (id, reader.offset + length)
    }

    /// Reads a chunk's own length (which counts itself) and checks it; returns where the chunk ends.
    private static func chunkStart(_ reader: inout ByteReader, end: Int, minimum: Int) throws -> Int {
        let start = reader.offset
        let size = try reader.u32le()
        guard size >= minimum, size <= end - start else { throw OwnDecodeError.corrupt }
        return start + size
    }

    private static func long(_ reader: inout ByteReader) throws -> Int { Int(Int32(truncatingIfNeeded: try reader.u32le())) }

    private static func isBlockNext(_ reader: ByteReader) -> Bool {
        var peek = reader
        return (try? Array(peek.take(4))) == blockMagic
    }

    /// A Color Palette block's body: RGBQUAD entries, red first.
    private static func readPalette(_ reader: inout ByteReader, end: Int) throws -> Palette {
        let chunkEnd = try chunkStart(&reader, end: end, minimum: 8)
        let count = try reader.u32le()
        reader.offset = chunkEnd
        guard count <= 256, count * 4 <= end - reader.offset else { throw OwnDecodeError.corrupt }
        let bytes = try reader.take(count * 4)
        return stride(from: bytes.startIndex, to: bytes.endIndex, by: 4).map { (bytes[$0], bytes[$0 + 1], bytes[$0 + 2]) }
    }

    // MARK: - Composite image bank

    /// The full-size composite, if the bank holds one (most files with several layers do); nil otherwise.
    private static func composite(_ reader: inout ByteReader, end: Int, attributes: Attributes) throws -> RGBAImage? {
        let infoEnd = try chunkStart(&reader, end: end, minimum: 8)
        let count = try reader.u32le()
        reader.offset = infoEnd
        var chosen: (index: Int, bitDepth: Int, compression: Int)?
        var index = 0
        // Every entry has a 10-byte header, so `count` can't run past the block.
        while index < count {
            let (id, entryEnd) = try blockHeader(&reader, end: end)
            guard id == Block.compositeAttributes else { throw OwnDecodeError.corrupt }
            _ = try chunkStart(&reader, end: entryEnd, minimum: 24)
            let width = try long(&reader), height = try long(&reader)
            let bitDepth = try reader.u16le(), compression = try reader.u16le()
            try reader.skip(6)  // planes, colour count
            let type = try reader.u16le()
            if chosen == nil, type == 0, width == attributes.width, height == attributes.height {
                chosen = (index, bitDepth, compression)
            }
            reader.offset = entryEnd
            index += 1
        }
        guard let chosen else { return nil }
        for _ in 0..<chosen.index { reader.offset = try blockHeader(&reader, end: end).end }
        let (id, imageEnd) = try blockHeader(&reader, end: end)
        if chosen.compression == Compression.jpeg {
            guard id == Block.jpeg else { throw OwnDecodeError.corrupt }
            let chunkEnd = try chunkStart(&reader, end: imageEnd, minimum: 14)
            let length = try reader.u32le()
            reader.offset = chunkEnd
            guard length <= imageEnd - reader.offset else { throw OwnDecodeError.corrupt }
            let jpeg = Data(try reader.take(length))
            guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil),
                  cgImage.width == attributes.width, cgImage.height == attributes.height,
                  let image = RGBAImage(cgImage) else { throw OwnDecodeError.corrupt }
            return image
        }
        guard id == Block.composite, chosen.compression <= Compression.lz77 else { throw OwnDecodeError.corrupt }
        let chunkEnd = try chunkStart(&reader, end: imageEnd, minimum: 8)
        reader.offset = chunkEnd
        var palette: Palette = []
        if isBlockNext(reader) {
            var peek = reader
            let (subID, subEnd) = try blockHeader(&peek, end: imageEnd)
            if subID == Block.palette { palette = try readPalette(&peek, end: subEnd); reader.offset = subEnd }
        }
        let channels = try readChannels(&reader, end: imageEnd, width: attributes.width, height: attributes.height,
                                        bitDepth: chosen.bitDepth, compression: chosen.compression)
        return try assemble(channels, width: attributes.width, height: attributes.height, bitDepth: chosen.bitDepth,
                            greyscale: attributes.greyscale, palette: palette, colour: 8, alpha: 9)
    }

    // MARK: - Layer bank

    private static func layers(_ reader: inout ByteReader, end: Int, attributes: Attributes, palette: Palette) throws -> RGBAImage {
        var canvas = try LayerCanvas(width: attributes.width, height: attributes.height)
        while reader.offset < end {
            let (id, layerEnd) = try blockHeader(&reader, end: end)
            defer { reader.offset = layerEnd }
            guard id == Block.layer else { continue }
            let infoEnd = try chunkStart(&reader, end: layerEnd, minimum: 4 + 2 + 36)
            try reader.skip(try reader.u16le())  // name
            let type = try reader.u8()
            let imageX = try long(&reader), imageY = try long(&reader)
            try reader.skip(8)
            let savedX0 = try long(&reader), savedY0 = try long(&reader)
            let savedX1 = try long(&reader), savedY1 = try long(&reader)
            let opacity = try reader.u8()
            try reader.skip(1)  // blend mode
            let flags = try reader.u8()
            guard reader.offset <= infoEnd else { throw OwnDecodeError.corrupt }
            reader.offset = infoEnd
            while isBlockNext(reader) { reader.offset = try blockHeader(&reader, end: layerEnd).end }  // layer extensions
            reader.offset = try chunkStart(&reader, end: layerEnd, minimum: 8)  // bitmap and channel counts
            // 1 raster, 2 floating raster selection; the saved rectangle is relative to the image rectangle.
            let width = savedX1 - savedX0, height = savedY1 - savedY0
            guard type == 1 || type == 2, flags & 1 != 0, opacity > 0, width > 0, height > 0 else { continue }
            _ = try checkedSize(width, height)
            let channels = try readChannels(&reader, end: layerEnd, width: width, height: height,
                                            bitDepth: attributes.bitDepth, compression: attributes.compression)
            let layer = try assemble(channels, width: width, height: height, bitDepth: attributes.bitDepth,
                                     greyscale: attributes.greyscale, palette: palette, colour: 0, alpha: 1)
            canvas.draw(layer, x: imageX + savedX0, y: imageY + savedY0, opacity: Double(opacity) / 255)
        }
        return canvas.image
    }

    // MARK: - Channels

    private struct Channel {
        let bitmapType, channelType: Int
        let bytes: [UInt8]
    }

    /// Every Channel sub-block from the reader to `end`. Each holds one plane of `width` × `height`
    /// samples, rows not padded (the "uncompressed length" field gives a padded bitmap size, so it isn't used).
    private static func readChannels(_ reader: inout ByteReader, end: Int, width: Int, height: Int,
                                     bitDepth: Int, compression: Int) throws -> [Channel] {
        var channels: [Channel] = []
        while reader.offset < end {
            let (id, channelEnd) = try blockHeader(&reader, end: end)
            defer { reader.offset = channelEnd }
            guard id == Block.channel else { continue }
            let chunkEnd = try chunkStart(&reader, end: channelEnd, minimum: 16)
            let length = try reader.u32le()
            try reader.skip(4)
            let bitmapType = try reader.u16le(), channelType = try reader.u16le()
            reader.offset = chunkEnd
            guard length <= channelEnd - reader.offset else { throw OwnDecodeError.corrupt }
            let content = try reader.take(length)
            // Colour channels of paletted images pack 1 or 4 bits per sample; every other channel is 8-bit.
            // shortcut: packed rows are assumed to be byte-aligned (no 1- or 4-bit sample file exists), check it when one does.
            let bits = channelType == 0 && (bitmapType == 0 || bitmapType == 8) && bitDepth < 8 ? bitDepth : 8
            let size = (width * bits + 7) / 8 * height
            channels.append(Channel(bitmapType: bitmapType, channelType: channelType,
                                    bytes: try unpack(content, size: size, compression: compression)))
        }
        return channels
    }

    private static func unpack(_ content: ArraySlice<UInt8>, size: Int, compression: Int) throws -> [UInt8] {
        switch compression {
        case Compression.none:
            guard content.count >= size else { throw OwnDecodeError.truncated }
            return Array(content.prefix(size))
        case Compression.rle:
            // A 2-byte packet makes at most 127 bytes: don't allocate for more than the stream can hold.
            guard size <= content.count * 64 else { throw OwnDecodeError.corrupt }
            var out = [UInt8]()
            out.reserveCapacity(size)
            var i = content.startIndex
            while i < content.endIndex {
                let count = Int(content[i])
                i += 1
                if count > 128 {
                    guard i < content.endIndex, out.count + count - 128 <= size else { throw OwnDecodeError.corrupt }
                    out.append(contentsOf: repeatElement(content[i], count: count - 128))
                    i += 1
                } else {
                    guard count <= content.endIndex - i, out.count + count <= size else { throw OwnDecodeError.corrupt }
                    out.append(contentsOf: content[i..<i + count])
                    i += count
                }
            }
            guard out.count == size else { throw OwnDecodeError.corrupt }
            return out
        case Compression.lz77:
            // Deflate expands at most about 1032 to 1.
            guard size <= content.count * 1032 + 1024 else { throw OwnDecodeError.corrupt }
            return try Inflate.zlib(content, size: size)
        default:
            throw OwnDecodeError.corrupt
        }
    }

    /// RGBA from the colour channels of bitmap type `colour` (red, green, blue, or one paletted/grey channel)
    /// and the transparency channel of bitmap type `alpha`, if present.
    private static func assemble(_ channels: [Channel], width: Int, height: Int, bitDepth: Int, greyscale: Bool,
                                 palette: Palette, colour: Int, alpha: Int) throws -> RGBAImage {
        func plane(_ bitmap: Int, _ channel: Int) -> [UInt8]? {
            channels.first { $0.bitmapType == bitmap && $0.channelType == channel }?.bytes
        }
        let count = width * height
        var pixels = [UInt8](repeating: 255, count: count * 4)
        if bitDepth == 24 {
            guard let red = plane(colour, 1), let green = plane(colour, 2), let blue = plane(colour, 3)
            else { throw OwnDecodeError.corrupt }
            for i in 0..<count { pixels[i * 4] = red[i]; pixels[i * 4 + 1] = green[i]; pixels[i * 4 + 2] = blue[i] }
        } else {
            guard let samples = plane(colour, 0) else { throw OwnDecodeError.corrupt }
            let rowBytes = (width * bitDepth + 7) / 8, mask = (1 << bitDepth) - 1
            for y in 0..<height {
                for x in 0..<width {
                    let bit = x * bitDepth
                    let index = Int(samples[y * rowBytes + bit / 8]) >> (8 - bitDepth - bit % 8) & mask
                    let i = (y * width + x) * 4
                    if greyscale, bitDepth == 8 {
                        pixels[i] = UInt8(index); pixels[i + 1] = UInt8(index); pixels[i + 2] = UInt8(index)
                    } else if index < palette.count {
                        pixels[i] = palette[index].r; pixels[i + 1] = palette[index].g; pixels[i + 2] = palette[index].b
                    } else {
                        pixels[i] = 0; pixels[i + 1] = 0; pixels[i + 2] = 0
                    }
                }
            }
        }
        if let transparency = plane(alpha, 0) {
            for i in 0..<count { pixels[i * 4 + 3] = transparency[i] }
        }
        return RGBAImage(width: width, height: height, pixels: pixels)
    }
}
