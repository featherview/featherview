import CoreGraphics
import Foundation
import ImageIO

/// Windows animated cursors (.ani): a RIFF "ACON" file whose frames are ICO or CUR files, which
/// ImageIO reads. Index n is step n of the animation (the "seq " order if present, else frame order),
/// largest size of that frame; the delays come from the "rate" chunk or the header's rate.
enum ANIDecoder {
    static let format = OwnFormat(name: "ANI", extensions: ["ani"],
                                  size: { data, step in
                                      guard let (source, index) = try? frame(data, step: step),
                                            let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
                                            let width = props[kCGImagePropertyPixelWidth] as? Int,
                                            let height = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
                                      return CGSize(width: width, height: height)
                                  },
                                  decode: { data, step, _ in
                                      let (source, index) = try frame(data, step: step)
                                      guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else { throw OwnDecodeError.corrupt }
                                      return image
                                  },
                                  delays: { data in
                                      (try? parse(data)).map { file in file.rates.map { Double($0) / 60 } }
                                  })

    /// The frames' ICO/CUR files, the frame index of each step and each step's rate in jiffies (1/60 s).
    private struct File {
        var frames: [ArraySlice<UInt8>], steps: [Int], rates: [Int]
    }

    private static func parse(_ data: Data) throws -> File {
        var reader = ByteReader(data)
        guard try reader.take(4).elementsEqual("RIFF".utf8) else { throw OwnDecodeError.notThisFormat }
        try reader.skip(4)
        guard try reader.take(4).elementsEqual("ACON".utf8) else { throw OwnDecodeError.notThisFormat }
        var isIcon = false, headerRate = 0, sequence: [Int]?, rates: [Int]?, frames: [ArraySlice<UInt8>] = []
        func u32s(_ body: inout ByteReader) -> [Int] {
            var values: [Int] = []
            while let value = try? body.u32le() { values.append(value) }  // a stray trailing byte is ignored
            return values
        }
        while !reader.isAtEnd {
            let id = String(decoding: try reader.take(4), as: UTF8.self), length = try reader.u32le()
            var body = ByteReader(Data(try reader.take(length)))
            if length % 2 == 1, !reader.isAtEnd { try reader.skip(1) }
            switch id {
            case "anih":
                try body.skip(28)
                headerRate = try body.u32le()
                isIcon = try body.u32le() & 1 == 1
            case "seq ":
                sequence = u32s(&body)
            case "rate":
                rates = u32s(&body)
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
        guard !frames.isEmpty else { throw OwnDecodeError.truncated }
        let steps = sequence.flatMap { $0.isEmpty ? nil : $0 } ?? Array(frames.indices)
        let stepRates = rates?.count == steps.count ? rates! : Array(repeating: headerRate, count: steps.count)
        return File(frames: frames, steps: steps, rates: stepRates)
    }

    /// Step `step`'s ICO/CUR and the index of its largest image.
    private static func frame(_ data: Data, step: Int) throws -> (CGImageSource, Int) {
        let file = try parse(data)
        guard file.steps.indices.contains(step), file.frames.indices.contains(file.steps[step]) else { throw OwnDecodeError.corrupt }
        guard let source = CGImageSourceCreateWithData(Data(file.frames[file.steps[step]]) as CFData, nil),
              CGImageSourceGetCount(source) > 0
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
