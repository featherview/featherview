import CoreGraphics
import Foundation
import ImageIO

/// Paint.NET 3.5 and later, shown flattened: `PDN3`, an XML header (size, PNG thumbnail), then a
/// .NET BinaryFormatter graph of the document whose layer pixels follow it as gzip chunks.
// shortcut: layer blend modes are drawn as normal, implement them if users send files that look wrong.
enum PDNDecoder {
    static let format = OwnFormat.raster(name: "Paint.NET", extensions: ["pdn"],
                                         size: { data, _ in try size(data) }, decode: { data, _ in try decode(data) })

    static func size(_ data: Data) throws -> (width: Int, height: Int) {
        var reader = ByteReader(data)
        return try header(&reader).size
    }

    static func decode(_ data: Data) throws -> RGBAImage {
        var reader = ByteReader(data)
        let (size, xml) = try header(&reader)
        // Paint.NET renders the thumbnail with every blend mode, so a canvas-sized one is the image.
        if let thumb = thumbnail(xml, size: size) { return thumb }

        // shortcut: only the `00 01` body of Paint.NET 3.5 and later, add 2.x/3.0x if such files turn up.
        guard try reader.u8() == 0, try reader.u8() == 1 else { throw OwnDecodeError.unsupported }
        let graph = try NRBFReader.read(&reader)
        func object(_ value: NRBFValue?) throws -> NRBFObject {
            guard case .reference(let id) = value, let object = graph.objects[id] else { throw OwnDecodeError.corrupt }
            return object
        }
        func int(_ value: NRBFValue?) throws -> Int {
            switch value {
            case .int(let v)? where v >= 0 && v <= Int32.max: return Int(v)
            case .uint(let v)? where v <= Int32.max: return Int(v)
            default: throw OwnDecodeError.corrupt
            }
        }

        let document = try object(.reference(graph.root))
        let list = try object(document.members["layers"])
        guard case .array(let items) = try object(list.members["ArrayList+_items"]).members["items"],
              let count = try? int(list.members["ArrayList+_size"]), count <= items.count
        else { throw OwnDecodeError.corrupt }

        struct Layer { let width, height, stride: Int; let visible: Bool; let opacity: Double }
        var layers: [Int32: Layer] = [:]  // by MemoryBlock id
        for item in items.prefix(count) {
            let layer = try object(item)
            let properties = try object(layer.members["Layer+properties"] ?? layer.members["properties"])
            let surface = try object(layer.members["surface"])
            guard case .reference(let block)? = surface.members["scan0"] else { throw OwnDecodeError.corrupt }
            let width = try int(surface.members["width"]), height = try int(surface.members["height"])
            let stride = try int(surface.members["stride"])
            // Every Paint.NET layer is canvas-sized; anything else is a damaged file.
            guard width == size.width, height == size.height, stride >= width * 4 else { throw OwnDecodeError.corrupt }
            layers[block] = Layer(width: width, height: height, stride: stride,
                                  visible: properties.members["visible"] != .bool(false),
                                  opacity: Double((try? int(properties.members["opacity"])) ?? 255) / 255)
        }

        var canvas = try LayerCanvas(width: size.width, height: size.height)
        // The deferred blocks follow the graph in the order their MemoryBlock records appeared.
        let blocks = graph.order.filter {
            graph.objects[$0]?.className == "PaintDotNet.MemoryBlock" && graph.objects[$0]?.members["deferred"] == .bool(true)
        }
        // Pixels stored inside the graph instead: no sample has them.
        guard Set(layers.keys).isSubset(of: blocks) else { throw OwnDecodeError.unsupported }
        for id in blocks {
            let block = graph.objects[id]!
            let length = try int(block.members["length64"])
            let layer = layers[id]
            if let layer, length < layer.stride * (layer.height - 1) + layer.width * 4 { throw OwnDecodeError.corrupt }
            let draw = layer.map { $0.visible && $0.opacity > 0 } ?? false
            let pixels = try readBlock(&reader, length: length, layer: draw ? layer.map { ($0.width, $0.height, $0.stride) } : nil)
            if let layer, let pixels, draw { canvas.draw(pixels, x: 0, y: 0, opacity: layer.opacity) }
        }
        return canvas.image
    }

    /// One deferred MemoryBlock: format `0`, big-endian chunk size, then gzip chunks in any order.
    /// With `layer`, its BGRA rows become an `RGBAImage`; without, the chunks are only checked and skipped.
    private static func readBlock(_ reader: inout ByteReader, length: Int,
                                  layer: (width: Int, height: Int, stride: Int)?) throws -> RGBAImage? {
        guard try reader.u8() == 0 else { throw OwnDecodeError.unsupported }
        let chunkSize = try reader.u32be()
        guard chunkSize > 0 else { throw OwnDecodeError.corrupt }
        let chunkCount = (length + chunkSize - 1) / chunkSize
        guard chunkCount <= reader.remaining / 8 else { throw OwnDecodeError.truncated }
        var seen = [Bool](repeating: false, count: chunkCount)
        var image = layer.map { RGBAImage(width: $0.width, height: $0.height, pixels: [UInt8](repeating: 0, count: $0.width * $0.height * 4)) }
        for _ in 0..<chunkCount {
            let index = try reader.u32be(), packedLength = try reader.u32be()
            guard index < chunkCount, !seen[index] else { throw OwnDecodeError.corrupt }
            seen[index] = true
            let packed = try reader.take(packedLength)
            guard let layer, image != nil else { continue }
            let start = index * chunkSize, count = min(chunkSize, length - start)
            // DEFLATE can't expand more than about 1032:1, so a bigger claim is refused before allocating.
            guard count <= packedLength * 1032 + 64 else { throw OwnDecodeError.corrupt }
            let bytes = try Inflate.gzip(packed, size: count)
            image!.pixels.withUnsafeMutableBufferPointer { dst in
                bytes.withUnsafeBufferPointer { src in
                    let rowBytes = layer.width * 4
                    var k = 0
                    while k < count {  // one run per row the chunk touches; chunk edges may fall inside a pixel
                        let row = (start + k) / layer.stride, column = (start + k) % layer.stride
                        let run = min(count - k, layer.stride - column)
                        if row < layer.height, column < rowBytes {
                            let base = row * rowBytes, from = k - column
                            // BGRA to RGBA: bytes 0 and 2 of each pixel swap (c ^ 2), green and alpha stay.
                            for c in column..<min(column + run, rowBytes) { dst[base + (c & 1 == 0 ? c ^ 2 : c)] = src[from + c] }
                        }
                        k += run
                    }
                }
            }
        }
        return image
    }

    private static func header(_ reader: inout ByteReader) throws -> (size: (width: Int, height: Int), xml: String) {
        guard reader.remaining >= 7, Array(try reader.take(4)) == Array("PDN3".utf8) else { throw OwnDecodeError.notThisFormat }
        let length = Int(try reader.u8()) | Int(try reader.u8()) << 8 | Int(try reader.u8()) << 16
        let xml = String(decoding: try reader.take(length), as: UTF8.self)
        guard let tagEnd = xml.firstIndex(of: ">") else { throw OwnDecodeError.corrupt }
        let tag = xml[..<tagEnd]
        func attribute(_ name: String) throws -> Int {
            guard let range = tag.range(of: " \(name)=\""), let value = Int(tag[range.upperBound...].prefix { $0.isNumber })
            else { throw OwnDecodeError.corrupt }
            return value
        }
        return (try checkedSize(attribute("width"), attribute("height")), xml)
    }

    /// The base64 PNG in `<thumb png="…">` if it is exactly `size`; nil if missing, unreadable or another size.
    /// Its size is checked before decoding, since the PNG can claim any size.
    private static func thumbnail(_ xml: String, size: (width: Int, height: Int)) -> RGBAImage? {
        guard let start = xml.range(of: "png=\"")?.upperBound,
              let end = xml[start...].firstIndex(of: "\""),
              let png = Data(base64Encoded: String(xml[start..<end])),
              let source = CGImageSourceCreateWithData(png as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              properties[kCGImagePropertyPixelWidth] as? Int == size.width,
              properties[kCGImagePropertyPixelHeight] as? Int == size.height,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width == size.width, image.height == size.height else { return nil }
        return RGBAImage(image)
    }
}
