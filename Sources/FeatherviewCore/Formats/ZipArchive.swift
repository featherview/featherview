import CoreGraphics
import Foundation
import ImageIO

/// Zip archives (PKWARE APPNOTE): the central directory, stored and deflated entries, no ZIP64 and
/// no encryption. Enough for the app formats that are zips with a PNG inside.
struct ZipArchive {
    struct Entry {
        let method, compressedSize, size, localOffset: Int
    }

    let data: Data
    let entries: [String: Entry]

    init(_ data: Data) throws {
        self.data = data
        // The end record is the last 22 bytes, unless a comment (up to 64 KiB) follows it.
        let bytes = [UInt8](data.suffix(22 + 0xFFFF))
        guard let end = stride(from: bytes.count - 22, through: 0, by: -1).first(where: {
            bytes[$0] == 0x50 && bytes[$0 + 1] == 0x4B && bytes[$0 + 2] == 5 && bytes[$0 + 3] == 6
        }) else { throw OwnDecodeError.notThisFormat }
        var reader = ByteReader(Array(bytes[end...]))
        try reader.skip(10)
        let count = try reader.u16le()
        _ = try reader.u32le()  // central directory size
        var central = ByteReader(data)
        central.offset = try reader.u32le()
        var entries: [String: Entry] = [:]
        for _ in 0..<count {
            guard try central.u32le() == 0x0201_4B50 else { throw OwnDecodeError.corrupt }
            try central.skip(6)
            let method = try central.u16le()
            try central.skip(8)
            let compressedSize = try central.u32le(), size = try central.u32le()
            let nameLength = try central.u16le(), extraLength = try central.u16le(), commentLength = try central.u16le()
            try central.skip(8)
            let localOffset = try central.u32le()
            let name = String(decoding: try central.take(nameLength), as: UTF8.self)
            try central.skip(extraLength + commentLength)
            entries[name] = Entry(method: method, compressedSize: compressedSize, size: size, localOffset: localOffset)
        }
        self.entries = entries
    }

    /// The entry's bytes; nil if the archive has no entry of that name.
    func read(_ name: String) throws -> Data? {
        guard let entry = entries[name] else { return nil }
        // 0xFFFFFFFF sizes mean ZIP64; anything past 1 GiB is beyond any image we'd show.
        guard entry.size < 1 << 30, entry.compressedSize < 1 << 30 else { throw OwnDecodeError.unsupported }
        var local = ByteReader(data)
        local.offset = entry.localOffset
        guard try local.u32le() == 0x0403_4B50 else { throw OwnDecodeError.corrupt }
        try local.skip(22)
        let nameLength = try local.u16le(), extraLength = try local.u16le()
        try local.skip(nameLength + extraLength)
        let payload = try local.take(entry.compressedSize)
        switch entry.method {
        case 0: return Data(payload)
        // Deflate packs at most ~1032:1, so a size claim beyond that is a lie: fail before allocating.
        case 8 where entry.size <= entry.compressedSize * 1032 + 64: return Data(try Inflate.raw(payload, size: entry.size))
        case 8: throw OwnDecodeError.corrupt
        default: throw OwnDecodeError.unsupported
        }
    }
}

/// App formats that are zip archives with a flattened PNG of the picture inside (spec "Formats").
enum ZippedImage {
    static let openRaster = format(name: "OpenRaster", extensions: ["ora"], entry: "mergedimage.png")
    static let krita = format(name: "Krita", extensions: ["kra"], entry: "mergedimage.png")
    // shortcut: Procreate keeps the full picture in LZO-compressed tiles; we show its stored preview, decode the tiles if people ask.
    static let procreate = format(name: "Procreate", extensions: ["procreate"], entry: "QuickLook/Thumbnail.png")

    static func format(name: String, extensions: [String], entry: String) -> OwnFormat {
        OwnFormat(name: name, extensions: extensions,
                  size: { data, _ in
                      guard let source = try? source(data, entry),
                            let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                            let width = props[kCGImagePropertyPixelWidth] as? Int,
                            let height = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
                      return CGSize(width: width, height: height)
                  },
                  decode: { data, _, maxPixelSize in
                      let source = try source(data, entry)
                      let options: [CFString: Any] = maxPixelSize.map {
                          [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: $0]
                      } ?? [:]
                      guard let image = maxPixelSize == nil
                          ? CGImageSourceCreateImageAtIndex(source, 0, nil)
                          : CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
                      else { throw OwnDecodeError.corrupt }
                      return image
                  })
    }

    private static func source(_ data: Data, _ entry: String) throws -> CGImageSource {
        guard let png = try ZipArchive(data).read(entry) else { throw OwnDecodeError.unsupported }
        guard let source = CGImageSourceCreateWithData(png as CFData, nil) else { throw OwnDecodeError.corrupt }
        return source
    }
}
