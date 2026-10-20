import CoreGraphics
import Foundation
import ImageIO

/// Windows animated cursors (.ani): a RIFF "ACON" file whose frames are ICO or CUR files, which
/// ImageIO reads. Shows the first frame of the animation (first in "seq " if present), largest size,
/// like GIFs show their first frame.
enum ANIDecoder {
    static let format = OwnFormat(name: "ANI", extensions: ["ani"],
                                  size: { data, _ in
                                      guard let (source, index) = try? firstFrame(data),
                                            let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
                                            let width = props[kCGImagePropertyPixelWidth] as? Int,
                                            let height = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
                                      return CGSize(width: width, height: height)
                                  },
                                  decode: { data, _, _ in
                                      let (source, index) = try firstFrame(data)
                                      guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else { throw OwnDecodeError.corrupt }
                                      return image
                                  })

    /// The first frame's ICO/CUR and the index of its largest image.
    private static func firstFrame(_ data: Data) throws -> (CGImageSource, Int) {
        var reader = ByteReader(data)
        guard try reader.take(4).elementsEqual("RIFF".utf8) else { throw OwnDecodeError.notThisFormat }
        try reader.skip(4)
        guard try reader.take(4).elementsEqual("ACON".utf8) else { throw OwnDecodeError.notThisFormat }
        var isIcon = false, sequence: Int?, frames: [ArraySlice<UInt8>] = []
        while !reader.isAtEnd {
            let id = String(decoding: try reader.take(4), as: UTF8.self), length = try reader.u32le()
            var body = ByteReader(Data(try reader.take(length)))
            if length % 2 == 1, !reader.isAtEnd { try reader.skip(1) }
            switch id {
            case "anih":
                try body.skip(32)
                isIcon = try body.u32le() & 1 == 1
            case "seq ":
                sequence = try body.u32le()
            case "LIST" where try body.take(4).elementsEqual("fram".utf8):
                while !body.isAtEnd {
                    let sub = String(decoding: try body.take(4), as: UTF8.self), size = try body.u32le()
                    let frame = try body.take(size)
                    if size % 2 == 1, !body.isAtEnd { try body.skip(1) }
                    if sub == "icon" { frames.append(frame) }
                }
            default: break
            }
        }
        guard isIcon else { throw OwnDecodeError.unsupported }  // raw bitmap frames: hardly used
        let first = sequence ?? 0
        guard frames.indices.contains(first) else { throw frames.isEmpty ? OwnDecodeError.truncated : OwnDecodeError.corrupt }
        guard let source = CGImageSourceCreateWithData(Data(frames[first]) as CFData, nil), CGImageSourceGetCount(source) > 0
        else { throw OwnDecodeError.corrupt }
        let largest = (0..<CGImageSourceGetCount(source)).max { a, b in
            func width(_ i: Int) -> Int {
                (CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any])?[kCGImagePropertyPixelWidth] as? Int ?? 0
            }
            return width(a) < width(b)
        } ?? 0
        return (source, largest)
    }
}
