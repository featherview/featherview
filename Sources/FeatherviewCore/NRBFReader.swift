import Foundation

/// One member value of an MS-NRBF object. Objects held by another object are `.reference`s into
/// `NRBFGraph.objects`; primitive arrays of bytes are `.bytes`.
enum NRBFValue: Equatable {
    case null, bool(Bool), int(Int64), uint(UInt64), double(Double), string(String), reference(Int32)
    case array([NRBFValue]), bytes([UInt8])
}

/// A class instance, or an array (`members["items"]`), or a string (`members["value"]`).
struct NRBFObject: Equatable {
    let className: String
    let members: [String: NRBFValue]
}

struct NRBFGraph {
    var objects: [Int32: NRBFObject] = [:]
    var root: Int32 = 0
    /// Object ids in the order their records appeared.
    var order: [Int32] = []
}

/// Reads a .NET BinaryFormatter stream (MS-NRBF sections 2.1–2.7) into an object graph, without
/// running or knowing any of its classes.
struct NRBFReader {
    static let maxDepth = 64
    /// Records, plus array elements (a null run counts each null) and class members, so a tiny file can't claim billions.
    static let maxRecords = 1_000_000

    private enum MemberType { case primitive(UInt8), string, object, systemClass, classType, objectArray, stringArray, primitiveArray(UInt8) }
    private struct ClassInfo { let name: String; let members: [(name: String, type: MemberType)] }
    /// What a record stands for where a value is expected.
    private enum Item { case value(NRBFValue), nulls(Int), end, header(root: Int32) }

    private var graph = NRBFGraph()
    private var classes: [Int32: ClassInfo] = [:]
    private var records = 0

    /// Reads records up to and including MessageEnd, leaving `reader` just after it.
    static func read(_ reader: inout ByteReader) throws -> NRBFGraph {
        var state = NRBFReader()
        guard case .header(let root) = try state.item(&reader, depth: 0) else { throw OwnDecodeError.notThisFormat }
        state.graph.root = root
        while true {
            switch try state.item(&reader, depth: 0) {
            case .end: return state.graph
            case .header: throw OwnDecodeError.corrupt
            case .value, .nulls: continue  // top-level objects are stored as they're read
            }
        }
    }

    private mutating func count(_ n: Int) throws {
        records += n
        guard n >= 0, records <= Self.maxRecords else { throw OwnDecodeError.corrupt }
    }

    private mutating func store(_ id: Int32, _ object: NRBFObject) {
        graph.objects[id] = object
        graph.order.append(id)
    }

    private mutating func item(_ r: inout ByteReader, depth: Int) throws -> Item {
        guard depth <= Self.maxDepth else { throw OwnDecodeError.corrupt }
        while true {
            let kind = try r.u8()
            try count(1)
            switch kind {
            case 0:
                let root = try Self.i32(&r)
                try r.skip(12)  // header id, major and minor version
                return .header(root: root)
            case 1:
                let id = try Self.i32(&r)
                guard let info = classes[try Self.i32(&r)] else { throw OwnDecodeError.corrupt }
                try object(&r, id: id, info, depth: depth)
                return .value(.reference(id))
            case 2, 3: throw OwnDecodeError.unsupported  // no member types: unreadable without the classes
            case 4, 5:
                let id = try Self.i32(&r)
                let name = try Self.string(&r)
                let memberCount = Int(try Self.i32(&r))
                guard memberCount >= 0, memberCount <= r.remaining else { throw OwnDecodeError.truncated }
                let names = try (0..<memberCount).map { _ in try Self.string(&r) }
                let kinds = try (0..<memberCount).map { _ in try r.u8() }
                let types = try kinds.map { kind -> MemberType in
                    switch kind {
                    case 0: return .primitive(try r.u8())
                    case 1: return .string
                    case 2: return .object
                    case 3: _ = try Self.string(&r); return .systemClass
                    case 4: _ = try Self.string(&r); _ = try Self.i32(&r); return .classType
                    case 5: return .objectArray
                    case 6: return .stringArray
                    case 7: return .primitiveArray(try r.u8())
                    default: throw OwnDecodeError.corrupt
                    }
                }
                if kind == 5 { _ = try Self.i32(&r) }  // library id
                let info = ClassInfo(name: name, members: Array(zip(names, types)))
                classes[id] = info
                try object(&r, id: id, info, depth: depth)
                return .value(.reference(id))
            case 6:
                let id = try Self.i32(&r)
                let value = try Self.string(&r)
                store(id, NRBFObject(className: "System.String", members: ["value": .string(value)]))
                return .value(.string(value))
            case 7:
                let id = try Self.i32(&r)
                let shape = try r.u8()
                let rank = Int(try Self.i32(&r))
                guard rank >= 1, rank <= 32 else { throw OwnDecodeError.corrupt }
                var length = 1
                for _ in 0..<rank {
                    let (product, overflow) = length.multipliedReportingOverflow(by: Int(try Self.i32(&r)))
                    guard !overflow, product >= 0 else { throw OwnDecodeError.corrupt }
                    length = product
                }
                if [3, 4, 5].contains(shape) { try r.skip(4 * rank) }  // lower bounds
                let type: MemberType
                switch try r.u8() {
                case 0: type = .primitive(try r.u8())
                case 1: type = .string
                case 2: type = .object
                case 3: _ = try Self.string(&r); type = .systemClass
                case 4: _ = try Self.string(&r); _ = try Self.i32(&r); type = .classType
                case 5: type = .objectArray
                case 6: type = .stringArray
                case 7: type = .primitiveArray(try r.u8())
                default: throw OwnDecodeError.corrupt
                }
                let items: NRBFValue
                if case .primitive(let p) = type { items = try primitiveArray(&r, p, length: length) }
                else { items = try elements(&r, length: length, depth: depth) }
                store(id, NRBFObject(className: "Array", members: ["items": items]))
                return .value(.reference(id))
            case 8: return .value(try Self.primitive(&r, try r.u8()))
            case 9: return .value(.reference(try Self.i32(&r)))
            case 10: return .nulls(1)
            case 11: return .end
            case 12: _ = try Self.i32(&r); _ = try Self.string(&r)  // a library name, then the record it's for
            case 13: return .nulls(Int(try r.u8()))
            case 14: return .nulls(Int(try Self.i32(&r)))
            case 15, 16, 17:
                let id = try Self.i32(&r)
                let length = Int(try Self.i32(&r))
                guard length >= 0 else { throw OwnDecodeError.corrupt }
                let items = kind == 15 ? try primitiveArray(&r, try r.u8(), length: length)
                                       : try elements(&r, length: length, depth: depth)
                store(id, NRBFObject(className: "Array", members: ["items": items]))
                return .value(.reference(id))
            default: throw OwnDecodeError.unsupported  // method calls and returns: not a stored object graph
            }
        }
    }

    private mutating func object(_ r: inout ByteReader, id: Int32, _ info: ClassInfo, depth: Int) throws {
        // Stored before its members, so `order` follows the records and a member record nested inside comes after.
        graph.order.append(id)
        try count(info.members.count)  // Null-typed primitives read no bytes, so the input alone doesn't bound this
        var members: [String: NRBFValue] = [:]
        for member in info.members {
            if case .primitive(let p) = member.type {
                members[member.name] = try Self.primitive(&r, p)
                continue
            }
            switch try item(&r, depth: depth + 1) {
            case .value(let v): members[member.name] = v
            case .nulls(1): members[member.name] = .null
            default: throw OwnDecodeError.corrupt
            }
        }
        graph.objects[id] = NRBFObject(className: info.name, members: members)
    }

    private mutating func elements(_ r: inout ByteReader, length: Int, depth: Int) throws -> NRBFValue {
        try count(length)
        var items: [NRBFValue] = []
        while items.count < length {
            switch try item(&r, depth: depth + 1) {
            case .value(let v): items.append(v)
            case .nulls(let n):
                guard n >= 1, n <= length - items.count else { throw OwnDecodeError.corrupt }
                items += repeatElement(.null, count: n)
            default: throw OwnDecodeError.corrupt
            }
        }
        return .array(items)
    }

    private mutating func primitiveArray(_ r: inout ByteReader, _ type: UInt8, length: Int) throws -> NRBFValue {
        if type == 2 { return .bytes(Array(try r.take(length))) }
        let size: Int = switch type { case 6, 9, 12, 13, 16: 8; case 7, 14: 2; case 8, 11, 15: 4; default: 1 }
        guard length <= r.remaining / size else { throw OwnDecodeError.truncated }
        try count(length)
        return .array(try (0..<length).map { _ in try Self.primitive(&r, type) })
    }

    // MARK: Primitives (section 2.1.2.3), little-endian

    private static func i32(_ r: inout ByteReader) throws -> Int32 { Int32(truncatingIfNeeded: try r.u32le()) }

    private static func u64(_ r: inout ByteReader) throws -> UInt64 {
        UInt64(try r.u32le()) | UInt64(try r.u32le()) << 32
    }

    /// Length-prefixed UTF-8: the length in 7-bit groups, low first, at most 5 bytes.
    private static func string(_ r: inout ByteReader) throws -> String {
        var length = 0
        for shift in stride(from: 0, through: 28, by: 7) {
            let byte = try r.u8()
            length |= Int(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return String(decoding: try r.take(length), as: UTF8.self) }
        }
        throw OwnDecodeError.corrupt
    }

    private static func primitive(_ r: inout ByteReader, _ type: UInt8) throws -> NRBFValue {
        switch type {
        case 1: return .bool(try r.u8() != 0)
        case 2: return .uint(UInt64(try r.u8()))
        case 3:  // one UTF-8 character
            let first = try r.u8()
            let extra = first < 0x80 ? 0 : first >= 0xF0 ? 3 : first >= 0xE0 ? 2 : 1
            return .string(String(decoding: [first] + (try r.take(extra)), as: UTF8.self))
        case 5, 18: return .string(try string(&r))  // decimal as text, string
        case 6: return .double(Double(bitPattern: try u64(&r)))
        case 7: return .int(Int64(Int16(truncatingIfNeeded: try r.u16le())))
        case 8: return .int(Int64(try i32(&r)))
        case 9, 12: return .int(Int64(bitPattern: try u64(&r)))  // Int64, TimeSpan ticks
        case 10: return .int(Int64(Int8(bitPattern: try r.u8())))
        case 11: return .double(Double(Float(bitPattern: UInt32(try r.u32le()))))
        case 13, 16: return .uint(try u64(&r))  // DateTime, UInt64
        case 14: return .uint(UInt64(try r.u16le()))
        case 15: return .uint(UInt64(try r.u32le()))
        case 17: return .null
        default: throw OwnDecodeError.corrupt
        }
    }
}
