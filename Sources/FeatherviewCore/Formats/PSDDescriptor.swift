import Foundation

/// One value in a Photoshop action descriptor (Adobe's Photoshop File Formats Specification,
/// "Descriptor structure").
public indirect enum PSDValue: Sendable, Equatable {
    case double(Double)
    case unit(String, Double)
    case int(Int)
    case bool(Bool)
    case text(String)
    case enumerated(type: String, value: String)
    case list([PSDValue])
    case object(PSDDescriptor)
    case raw(Data)
}

/// A Photoshop action descriptor: a class ID and keyed values, in file order. Fill layers, adjustments
/// and vector data store their settings this way inside tagged blocks.
public struct PSDDescriptor: Sendable, Equatable {
    public var classID: String
    public var items: [(key: String, value: PSDValue)]

    /// Nesting deeper than this is treated as damage.
    static let maxDepth = 32

    public subscript(key: String) -> PSDValue? {
        items.first { $0.key == key }?.value
    }

    /// Reads a descriptor starting at its Unicode class name. Throws `OwnDecodeError.corrupt` on
    /// damage: an unknown type, a length or count past the end, or nesting deeper than 32.
    public init(_ bytes: ArraySlice<UInt8>) throws {
        var reader = DescriptorReader(bytes: bytes, position: bytes.startIndex)
        self = try reader.descriptor(depth: 0)
    }

    /// Reads a descriptor preceded by its 4-byte version, which must be 16.
    public static func versioned(_ data: Data) throws -> PSDDescriptor {
        let bytes = [UInt8](data)
        var reader = DescriptorReader(bytes: bytes[...], position: 0)
        guard try reader.u32() == 16 else { throw OwnDecodeError.corrupt }
        return try reader.descriptor(depth: 0)
    }

    init(classID: String, items: [(key: String, value: PSDValue)]) {
        self.classID = classID
        self.items = items
    }

    public static func == (a: PSDDescriptor, b: PSDDescriptor) -> Bool {
        a.classID == b.classID && a.items.count == b.items.count
            && zip(a.items, b.items).allSatisfy { $0.key == $1.key && $0.value == $1.value }
    }
}

/// Big-endian reads over a slice; every read past the end throws `.corrupt`.
private struct DescriptorReader {
    let bytes: ArraySlice<UInt8>
    var position: Int

    var remaining: Int { bytes.endIndex - position }

    mutating func take(_ count: Int) throws -> ArraySlice<UInt8> {
        guard count >= 0, count <= remaining else { throw OwnDecodeError.corrupt }
        defer { position += count }
        return bytes[position..<position + count]
    }

    mutating func u32() throws -> UInt32 {
        try take(4).reduce(0) { $0 << 8 | UInt32($1) }
    }

    mutating func u64() throws -> UInt64 {
        try take(8).reduce(0) { $0 << 8 | UInt64($1) }
    }

    /// A count of items at least `size` bytes each, bounded by the bytes left.
    mutating func count(each size: Int) throws -> Int {
        let count = Int(try u32())
        guard count <= remaining / size else { throw OwnDecodeError.corrupt }
        return count
    }

    mutating func os() throws -> String {
        String(decoding: try take(4), as: UTF8.self)
    }

    /// A key or class ID: length 0 means four characters follow.
    mutating func id() throws -> String {
        let length = Int(try u32())
        return String(bytes: try take(length == 0 ? 4 : length), encoding: .isoLatin1) ?? ""
    }

    /// UTF-16 big-endian with a unit count first; trailing NULs dropped.
    mutating func unicode() throws -> String {
        let units = try take(try count(each: 2) * 2)
        var utf16 = stride(from: units.startIndex, to: units.endIndex, by: 2).map { UInt16(units[$0]) << 8 | UInt16(units[$0 + 1]) }
        while utf16.last == 0 { utf16.removeLast() }
        return String(decoding: utf16, as: UTF16.self)
    }

    mutating func double() throws -> Double { Double(bitPattern: try u64()) }

    mutating func descriptor(depth: Int) throws -> PSDDescriptor {
        guard depth <= PSDDescriptor.maxDepth else { throw OwnDecodeError.corrupt }
        _ = try unicode()
        let classID = try id()
        let count = try count(each: 9)  // key ≥ 5, type 4
        var items: [(key: String, value: PSDValue)] = []
        for _ in 0..<count {
            let key = try id()
            items.append((key, try value(type: try os(), depth: depth)))
        }
        return PSDDescriptor(classID: classID, items: items)
    }

    mutating func value(type: String, depth: Int) throws -> PSDValue {
        switch type {
        case "Objc", "GlbO":
            return .object(try descriptor(depth: depth + 1))
        case "VlLs":
            guard depth < PSDDescriptor.maxDepth else { throw OwnDecodeError.corrupt }
            let count = try count(each: 4)
            var list: [PSDValue] = []
            for _ in 0..<count { list.append(try value(type: try os(), depth: depth + 1)) }
            return .list(list)
        case "doub":
            return .double(try double())
        case "UntF":
            return .unit(try os(), try double())
        case "UnFl":
            let unit = try os()
            let count = try count(each: 8)
            var list: [PSDValue] = []
            for _ in 0..<count { list.append(.unit(unit, try double())) }
            return .list(list)
        case "long":
            return .int(Int(Int32(bitPattern: try u32())))
        case "comp":
            return .int(Int(Int64(bitPattern: try u64())))
        case "bool":
            return .bool(try take(1).first != 0)
        case "TEXT":
            return .text(try unicode())
        case "enum":
            return .enumerated(type: try id(), value: try id())
        case "type", "GlbC":
            _ = try unicode()
            return .text(try id())
        case "tdta", "alis":
            return .raw(Data(try take(Int(try u32()))))
        case "obj ":
            let start = position
            try reference()
            return .raw(Data(bytes[start..<position]))
        default:
            throw OwnDecodeError.corrupt
        }
    }

    /// Skips a reference structure: a count, then items whose layout depends on their type.
    mutating func reference() throws {
        let count = try count(each: 4)
        for _ in 0..<count {
            switch try os() {
            case "prop": _ = try unicode(); _ = try id(); _ = try id()
            case "Clss": _ = try unicode(); _ = try id()
            case "Enmr": _ = try unicode(); _ = try id(); _ = try id(); _ = try id()
            case "rele": _ = try unicode(); _ = try id(); _ = try take(4)
            case "Idnt", "indx": _ = try take(4)
            case "name": _ = try unicode()
            default: throw OwnDecodeError.corrupt
            }
        }
    }
}
