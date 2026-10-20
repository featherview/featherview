import CoreGraphics
import Foundation
import ImageIO

/// BPG (bellard.org/bpg): a small header in front of an HEVC stream whose VPS and SPS were left out.
/// We rebuild those from the header, wrap the stream as a HEIF file and let ImageIO decode it with the
/// system's HEVC decoder, so no third-party HEVC code ships (every free one is LGPL).
// shortcut: first frame only, no ICC profile, no CMYK, and only what macOS's HEVC decoder handles
// (not 12/14 bits, nor RGB/YCgCo with subsampled chroma); revisit if people bring such files.
enum BPGDecoder {
    static let format = OwnFormat.raster(name: "BPG", extensions: ["bpg"],
                                         size: { data, _ in try size(data) }, decode: { data, _ in try decode(data) })

    struct Header {
        var pixelFormat = 0, bitDepth = 8, colorSpace = 0, width = 0, height = 0
        var alpha = false, premultiplied = false, limitedRange = false
        /// Alpha first when there is one, as in the file.
        var hevcHeaders: [ArraySlice<UInt8>] = []
        var data: ArraySlice<UInt8> = []
    }

    static func size(_ data: Data) throws -> (width: Int, height: Int) {
        let header = try header(data, readStream: false)
        return (header.width, header.height)
    }

    static func decode(_ data: Data) throws -> RGBAImage {
        let header = try header(data, readStream: true)
        // HEVC codes a flat 16 MP picture in about 1 KB; a file far shorter than that can't be real.
        guard header.data.count >= header.width * header.height / 65536 else { throw OwnDecodeError.truncated }
        let (color, alpha) = try split(header.data)
        guard !color.isEmpty else { throw OwnDecodeError.corrupt }
        let file = try heif(header, color: color, alpha: header.alpha ? alpha : nil)
        guard let source = CGImageSourceCreateWithData(Data(file) as CFData, nil),
              let full = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
              full.width >= header.width, full.height >= header.height
        else { throw OwnDecodeError.unsupported }
        // ImageIO reports no HEVC errors: a stream it can't decode comes back as all-zero pixels, alpha
        // or padding byte included, which no real picture has (only a fully transparent black one).
        guard let raw = full.dataProvider?.data, let bytes = CFDataGetBytePtr(raw),
              UnsafeBufferPointer(start: bytes, count: CFDataGetLength(raw)).contains(where: { $0 != 0 })
        else { throw OwnDecodeError.corrupt }
        guard var image = straightRGBA(full, width: header.width, height: header.height)
                ?? full.cropping(to: CGRect(x: 0, y: 0, width: header.width, height: header.height)).flatMap(RGBAImage.init)
        else { throw OwnDecodeError.unsupported }
        if header.premultiplied { unpremultiply(&image) }
        if header.colorSpace == 2 { fromYCgCo(&image, limitedRange: header.limitedRange) }
        return image
    }

    /// ImageIO gives images with alpha as straight 8-bit sRGB RGBA: copied as is, since drawing them
    /// would premultiply and lose the colour of nearly transparent pixels.
    private static func straightRGBA(_ image: CGImage, width: Int, height: Int) -> RGBAImage? {
        guard image.alphaInfo == .last, image.bitsPerComponent == 8, image.bitsPerPixel == 32,
              image.bitmapInfo.intersection(.byteOrderMask).isEmpty,
              image.colorSpace?.name == CGColorSpace.sRGB,
              let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data),
              CFDataGetLength(data) >= image.bytesPerRow * image.height
        else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            pixels.withUnsafeMutableBytes { out in
                out.baseAddress!.advanced(by: y * width * 4).copyMemory(from: bytes + y * image.bytesPerRow, byteCount: width * 4)
            }
        }
        return RGBAImage(width: width, height: height, pixels: pixels)
    }

    // MARK: - File header

    static func header(_ data: Data, readStream: Bool) throws -> Header {
        var reader = ByteReader(data)
        guard reader.remaining >= 6, try reader.u32be() == 0x4250_47FB else { throw OwnDecodeError.notThisFormat }
        var h = Header()
        let a = try reader.u8(), b = try reader.u8()
        h.pixelFormat = Int(a >> 5)
        let alpha1 = a & 0x10 != 0
        h.bitDepth = Int(a & 0x0F) + 8
        h.colorSpace = Int(b >> 4)
        let hasExtension = b & 0x08 != 0, alpha2 = b & 0x04 != 0
        h.limitedRange = b & 0x02 != 0
        guard h.pixelFormat <= 5, h.bitDepth <= 14, h.colorSpace <= 4 else { throw OwnDecodeError.unsupported }
        guard alpha1 || !alpha2 else { throw OwnDecodeError.unsupported }  // CMYK
        h.alpha = alpha1
        h.premultiplied = alpha1 && alpha2
        (h.width, h.height) = try checkedSize(ue7(&reader), ue7(&reader))
        guard readStream else { return h }
        let length = try ue7(&reader)
        if hasExtension { try reader.skip(ue7(&reader)) }  // EXIF, ICC, XMP, thumbnail, animation timing
        for _ in 0..<(h.alpha ? 2 : 1) { h.hevcHeaders.append(try reader.take(ue7(&reader))) }
        h.data = try reader.take(length == 0 ? reader.remaining : length)
        return h
    }

    /// Up to 32 bits, 7 per byte, high bit set on all but the last.
    private static func ue7(_ reader: inout ByteReader) throws -> Int {
        var value = 0
        for i in 0..<5 {
            let byte = try reader.u8()
            if i == 0, byte == 0x80 { throw OwnDecodeError.corrupt }
            value = value << 7 | Int(byte & 0x7F)
            if byte & 0x80 == 0 { return value }
        }
        throw OwnDecodeError.corrupt
    }

    // MARK: - HEVC stream

    /// The NAL units of the first picture, split by `nuh_layer_id` (0 colour, 1 alpha), alpha moved to layer 0.
    static func split(_ data: ArraySlice<UInt8>) throws -> (color: [[UInt8]], alpha: [[UInt8]]) {
        var units: [ArraySlice<UInt8>] = []
        var start = data.startIndex, i = data.startIndex
        while i + 2 < data.endIndex {
            if data[i] == 0, data[i + 1] == 0, data[i + 2] == 1 {
                units.append(data[start..<i])
                i += 3
                start = i
            } else {
                i += 1
            }
        }
        units.append(data[start..<data.endIndex])
        var color: [[UInt8]] = [], alpha: [[UInt8]] = []
        var seenPicture = [false, false]
        for unit in units {
            var nal = Array(unit)
            while nal.last == 0 { nal.removeLast() }  // the zero byte of a four-byte start code
            guard nal.count >= 3 else { continue }
            let type = Int(nal[0] >> 1 & 0x3F), layer = Int(nal[0] & 1) << 5 | Int(nal[1] >> 3)
            guard layer <= 1 else { continue }
            if type < 32 {  // a slice: stop at the second picture of an animation
                let firstSliceOfPicture = nal[2] & 0x80 != 0
                if firstSliceOfPicture, seenPicture[layer] { continue }
                seenPicture[layer] = true
            }
            nal[0] &= 0xFE
            nal[1] &= 0x07
            if layer == 0 { color.append(nal) } else { alpha.append(nal) }
        }
        return (color, alpha)
    }

    struct BitWriter {
        var bytes: [UInt8] = []
        var bit = 0

        mutating func u(_ value: Int, _ count: Int) {
            for i in stride(from: count - 1, through: 0, by: -1) {
                if bit == 0 { bytes.append(0) }
                bytes[bytes.count - 1] |= UInt8((value >> i) & 1) << (7 - bit)
                bit = (bit + 1) % 8
            }
        }

        mutating func ue(_ value: Int) {
            let v = value + 1, length = Int.bitWidth - v.leadingZeroBitCount
            u(0, length - 1)
            u(v, length)
        }

        mutating func flag(_ value: Bool) { u(value ? 1 : 0, 1) }

        /// rbsp_trailing_bits, then emulation prevention, behind a two-byte NAL header.
        func nal(type: Int) -> [UInt8] {
            var rbsp = self
            rbsp.u(1, 1)
            var out: [UInt8] = [UInt8(type << 1), 1]
            var zeros = 0
            for byte in rbsp.bytes {
                if zeros >= 2, byte <= 3 { out.append(3); zeros = 0 }
                out.append(byte)
                zeros = byte == 0 ? zeros + 1 : 0
            }
            return out
        }
    }

    struct BitReader {
        let bytes: ArraySlice<UInt8>
        var position = 0

        mutating func u(_ count: Int) throws -> Int {
            var value = 0
            for _ in 0..<count {
                let index = bytes.startIndex + position / 8
                guard index < bytes.endIndex else { throw OwnDecodeError.truncated }
                value = value << 1 | Int(bytes[index] >> (7 - position % 8) & 1)
                position += 1
            }
            return value
        }

        mutating func ue() throws -> Int {
            var zeros = 0
            while try u(1) == 0 {
                zeros += 1
                guard zeros < 32 else { throw OwnDecodeError.corrupt }
            }
            return (1 << zeros) - 1 + (try u(zeros))
        }
    }

    /// profile_tier_level for one sub-layer: Main, Main 10, or Format Range Extensions with the
    /// constraint flags for the chroma format and depth.
    static func profileTierLevel(chroma: Int, bitDepth: Int) -> [UInt8] {
        var w = BitWriter()
        let profile = chroma == 1 && bitDepth == 8 ? 1 : chroma == 1 && bitDepth <= 10 ? 2 : 4
        w.u(0, 2); w.u(0, 1); w.u(profile, 5)
        for i in 0..<32 { w.flag(i == profile || (profile == 1 && i == 2)) }
        w.flag(true); w.flag(false); w.flag(false); w.flag(true)  // progressive, frame only
        if profile == 4 {
            w.flag(bitDepth <= 12); w.flag(bitDepth <= 10); w.flag(bitDepth <= 8)
            w.flag(chroma <= 2); w.flag(chroma <= 1); w.flag(chroma == 0)
            w.flag(true); w.flag(true); w.flag(true)  // intra, one picture only, lower bit rate
            w.u(0, 34)
        } else {
            w.u(0, 43)
        }
        w.u(0, 1)
        w.u(186, 8)  // level 6.2
        return w.bytes
    }

    static func vps(_ ptl: [UInt8]) -> [UInt8] {
        var w = BitWriter()
        w.u(0, 4); w.flag(true); w.flag(true); w.u(0, 6); w.u(0, 3); w.flag(true); w.u(0xFFFF, 16)
        for byte in ptl { w.u(Int(byte), 8) }
        w.flag(true); w.ue(1); w.ue(0); w.ue(0)  // two pictures in the buffer, no reordering
        w.u(0, 6); w.ue(0); w.flag(false); w.flag(false)
        return w.nal(type: 32)
    }

    /// The SPS from a BPG hevc_header plus the values the BPG spec fixes.
    static func sps(_ header: ArraySlice<UInt8>, ptl: [UInt8], chroma: Int, width: Int, height: Int, bitDepth: Int,
                    matrix: Int, fullRange: Bool) throws -> [UInt8] {
        var r = BitReader(bytes: header)
        let log2MinCB = try r.ue() + 3, diffCB = try r.ue(), minTB = try r.ue(), diffTB = try r.ue()
        let depthIntra = try r.ue()
        guard log2MinCB <= 6, diffCB <= 3, minTB <= 3, diffTB <= 3, depthIntra <= 4 else { throw OwnDecodeError.corrupt }
        var w = BitWriter()
        w.u(0, 4); w.u(0, 3); w.flag(true)
        for byte in ptl { w.u(Int(byte), 8) }
        w.ue(0); w.ue(chroma)
        if chroma == 3 { w.flag(false) }
        let cb = 1 << log2MinCB
        w.ue((width + cb - 1) / cb * cb); w.ue((height + cb - 1) / cb * cb)
        w.flag(false)  // no conformance window: we crop
        w.ue(bitDepth - 8); w.ue(bitDepth - 8)
        w.ue(4)
        w.flag(true); w.ue(1); w.ue(0); w.ue(0)
        w.ue(log2MinCB - 3); w.ue(diffCB); w.ue(minTB); w.ue(diffTB)
        w.ue(depthIntra); w.ue(depthIntra)
        w.flag(false); w.flag(true)  // no scaling lists, AMP
        w.u(try r.u(1), 1)  // SAO
        let pcm = try r.u(1)
        w.u(pcm, 1)
        if pcm == 1 {
            w.u(try r.u(8), 8)
            w.ue(try r.ue()); w.ue(try r.ue())
            w.u(try r.u(1), 1)
        }
        w.ue(0); w.flag(false); w.flag(true)  // no reference picture sets, no long-term, temporal MVP
        w.u(try r.u(1), 1)  // strong intra smoothing
        // VUI with only the video signal type: ImageIO takes range and matrix from here, not from colr.
        w.flag(true); w.flag(false); w.flag(false); w.flag(true)
        w.u(5, 3); w.flag(fullRange); w.flag(true)
        w.u(1, 8); w.u(13, 8); w.u(matrix, 8)  // sRGB primaries and transfer
        w.u(0, 7)  // no chroma location, field, display window, timing or restriction info
        let extensions = try r.u(1)
        w.u(extensions, 1)
        if extensions == 1 {
            let range = try r.u(1)
            w.u(range, 1)
            w.u(try r.u(7), 7)
            if range == 1 { w.u(try r.u(9), 9) }
        }
        return w.nal(type: 33)
    }

    // MARK: - HEIF

    private static func box(_ type: String, _ payload: [UInt8]) -> [UInt8] {
        be32(payload.count + 8) + Array(type.utf8) + payload
    }

    private static func fullBox(_ type: String, version: UInt8 = 0, _ payload: [UInt8]) -> [UInt8] {
        box(type, [version, 0, 0, 0] + payload)
    }

    private static func be32(_ v: Int) -> [UInt8] { [UInt8(v >> 24 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)] }
    private static func be16(_ v: Int) -> [UInt8] { [UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)] }

    private static func hvcC(ptl: [UInt8], chroma: Int, bitDepth: Int, vps: [UInt8], sps: [UInt8], pps: [[UInt8]]) -> [UInt8] {
        var p: [UInt8] = [1] + ptl  // the 12 bytes of profile_tier_level match the record's layout
        p += [0xF0, 0x00, 0xFC, 0xFC | UInt8(chroma), 0xF8 | UInt8(bitDepth - 8), 0xF8 | UInt8(bitDepth - 8), 0, 0, 0x0F]
        let arrays: [(Int, [[UInt8]])] = [(32, [vps]), (33, [sps]), (34, pps)]
        p.append(UInt8(arrays.count))
        for (type, units) in arrays {
            p += [0x80 | UInt8(type)] + be16(units.count)
            for unit in units { p += be16(unit.count) + unit }
        }
        return box("hvcC", p)
    }

    static func heif(_ h: Header, color: [[UInt8]], alpha: [[UInt8]]?) throws -> [UInt8] {
        let chroma = [0, 1, 2, 3, 1, 2][h.pixelFormat]
        let cb = { (header: ArraySlice<UInt8>) throws -> (Int, Int) in
            var r = BitReader(bytes: header)
            let size = 1 << (try r.ue() + 3)
            return ((h.width + size - 1) / size * size, (h.height + size - 1) / size * size)
        }
        let matrix = [5, 0, 0, 1, 9][h.colorSpace]  // YCgCo (8) decodes as identity, see `fromYCgCo`
        func item(_ header: ArraySlice<UInt8>, chroma: Int, units: [[UInt8]]) throws -> (config: [UInt8], ispe: [UInt8], data: [UInt8]) {
            let ptl = profileTierLevel(chroma: chroma, bitDepth: h.bitDepth)
            let sps = try sps(header, ptl: ptl, chroma: chroma, width: h.width, height: h.height, bitDepth: h.bitDepth,
                              matrix: chroma == 0 ? 2 : matrix, fullRange: chroma == 0 || h.colorSpace == 2 || !h.limitedRange)
            let pps = units.filter { $0[0] >> 1 == 34 }
            let config = hvcC(ptl: ptl, chroma: chroma, bitDepth: h.bitDepth, vps: vps(ptl), sps: sps, pps: pps)
            let (w, hh) = try cb(header)
            let ispe = fullBox("ispe", be32(w) + be32(hh))
            let data = units.filter { $0[0] >> 1 != 34 }.flatMap { be32($0.count) + $0 }
            return (config, ispe, data)
        }
        let main = try item(h.hevcHeaders.last!, chroma: chroma, units: color)
        let aux = try alpha.map { try item(h.hevcHeaders[0], chroma: 0, units: $0) }

        // nclx: sRGB primaries and transfer, the matrix of the colour space, full or limited range.
        let colr = box("colr", Array("nclx".utf8) + be16(1) + be16(13) + be16(matrix) + [h.limitedRange ? 0 : 0x80])
        var properties = [main.config, main.ispe, colr]
        var associations: [UInt8] = be16(1) + [3, 0x81, 2, 3]
        var infos = fullBox("infe", version: 2, be16(1) + be16(0) + Array("hvc1".utf8) + [0])
        var references: [UInt8] = []
        if let aux {
            properties += [aux.config, aux.ispe, fullBox("auxC", Array("urn:mpeg:mpegB:cicp:systems:auxiliary:alpha".utf8) + [0])]
            associations += be16(2) + [3, 0x84, 5, 0x86]
            infos += fullBox("infe", version: 2, be16(2) + be16(0) + Array("hvc1".utf8) + [0])
            references = fullBox("iref", box("auxl", be16(2) + be16(1) + be16(1)))
        }
        let itemCount = aux == nil ? 1 : 2
        let ftyp = box("ftyp", Array("heic".utf8) + be32(0) + Array("mif1heic".utf8))
        let hdlr = fullBox("hdlr", be32(0) + Array("pict".utf8) + be32(0) + be32(0) + be32(0) + [0])
        let pitm = fullBox("pitm", be16(1))
        let iinf = fullBox("iinf", be16(itemCount) + infos)
        let iprp = box("iprp", box("ipco", properties.flatMap { $0 })
                       + fullBox("ipma", be32(itemCount) + associations))
        // iloc offsets depend on the meta box's size, which doesn't depend on their values.
        func iloc(_ base: Int) -> [UInt8] {
            var p: [UInt8] = [0x44, 0x00] + be16(itemCount)
            p += be16(1) + be16(0) + be16(1) + be32(base) + be32(main.data.count)
            if let aux { p += be16(2) + be16(0) + be16(1) + be32(base + main.data.count) + be32(aux.data.count) }
            return fullBox("iloc", p)
        }
        let meta = { (base: Int) in fullBox("meta", hdlr + pitm + iloc(base) + iinf + references + iprp) }
        let dataStart = ftyp.count + meta(0).count + 8
        return ftyp + meta(dataStart) + box("mdat", main.data + (aux?.data ?? []))
    }

    /// ImageIO doesn't know HEVC's YCgCo matrix, so it is decoded as identity (G = Y, B = Cg, R = Co)
    /// and turned into RGB here; the BPG spec puts a limited range on the RGB result.
    private static func fromYCgCo(_ image: inout RGBAImage, limitedRange: Bool) {
        for i in stride(from: 0, to: image.pixels.count, by: 4) {
            let y = Int(image.pixels[i + 1]), cg = Int(image.pixels[i + 2]) - 128, co = Int(image.pixels[i]) - 128
            let t = y - cg
            for (c, v) in [t + co, y + cg, t - co].enumerated() {
                let full = limitedRange ? (v - 16) * 255 / 219 : v
                image.pixels[i + c] = UInt8(max(0, min(255, full)))
            }
        }
    }

    private static func unpremultiply(_ image: inout RGBAImage) {
        for i in stride(from: 0, to: image.pixels.count, by: 4) {
            let alpha = Int(image.pixels[i + 3])
            guard alpha > 0, alpha < 255 else { continue }
            for c in 0..<3 { image.pixels[i + c] = UInt8(min(255, (Int(image.pixels[i + c]) * 255 + alpha / 2) / alpha)) }
        }
    }
}
