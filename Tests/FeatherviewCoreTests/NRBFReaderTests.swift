import Foundation
import Testing
@testable import FeatherviewCore

/// Writes MS-NRBF records byte by byte, for these tests and the PDN builder.
struct NRBFBytes {
    var bytes: [UInt8] = []

    /// A typed member of a ClassWithMembersAndTypes record.
    enum Member {
        case int32(Int), int64(Int), bool(Bool), byte(UInt8), double(Double)
        case string(id: Int, String)
        case reference(Int, className: String)  // a class member pointing at an object written elsewhere
        case objectArray(Int)                   // an object[] member pointing at an ArraySingleObject
        case null
    }

    static func le32(_ v: Int) -> [UInt8] { (0..<4).map { UInt8(truncatingIfNeeded: v >> ($0 * 8)) } }
    static func le64(_ v: Int) -> [UInt8] { (0..<8).map { UInt8(truncatingIfNeeded: v >> ($0 * 8)) } }

    mutating func u8(_ v: UInt8) { bytes.append(v) }
    mutating func i32(_ v: Int) { bytes += Self.le32(v) }

    /// Length-prefixed string: 7-bit variable-length count, then UTF-8.
    mutating func string(_ s: String) {
        var n = s.utf8.count
        repeat { bytes.append(UInt8(n & 0x7F) | (n > 0x7F ? 0x80 : 0)); n >>= 7 } while n > 0
        bytes += Array(s.utf8)
    }

    mutating func header(root: Int = 1) { u8(0); i32(root); i32(-1); i32(1); i32(0) }
    mutating func library(_ id: Int, _ name: String = "Lib") { u8(12); i32(id); string(name) }
    mutating func end() { u8(11) }

    mutating func classRecord(id: Int, name: String, library: Int = 2, members: [(String, Member)]) {
        u8(5); i32(id); string(name); i32(members.count)
        for (memberName, _) in members { string(memberName) }
        for (_, member) in members {
            switch member {
            case .int32, .int64, .bool, .byte, .double: u8(0)
            case .string: u8(1)
            case .reference: u8(4)
            case .objectArray: u8(5)
            case .null: u8(2)
            }
        }
        for (_, member) in members {
            switch member {
            case .int32: u8(8)
            case .int64: u8(9)
            case .bool: u8(1)
            case .byte: u8(2)
            case .double: u8(6)
            case .reference(_, let className): string(className); i32(library)
            default: break
            }
        }
        i32(library)
        values(members.map(\.1))
    }

    mutating func values(_ members: [Member]) {
        for member in members {
            switch member {
            case .int32(let v): i32(v)
            case .int64(let v): bytes += Self.le64(v)
            case .bool(let v): u8(v ? 1 : 0)
            case .byte(let v): u8(v)
            case .double(let v): bytes += Self.le64(Int(truncatingIfNeeded: v.bitPattern))
            case .string(let id, let s): u8(6); i32(id); string(s)
            case .reference(let id, _), .objectArray(let id): u8(9); i32(id)
            case .null: u8(10)
            }
        }
    }

    /// ClassWithId: a second object reusing the member layout of `metadata`.
    mutating func classWithId(id: Int, metadata: Int, values members: [Member]) {
        u8(1); i32(id); i32(metadata)
        values(members)
    }

    /// ArraySingleObject of references, with `nulls` trailing null entries (ObjectNullMultiple256).
    mutating func objectArray(id: Int, references: [Int], nulls: Int = 0) {
        u8(16); i32(id); i32(references.count + nulls)
        for ref in references { u8(9); i32(ref) }
        if nulls > 0 { u8(13); u8(UInt8(nulls)) }
    }

    var data: Data { Data(bytes) }
}

@Suite struct NRBFReaderTests {
    static func read(_ bytes: [UInt8]) throws -> NRBFGraph {
        var reader = ByteReader(bytes)
        return try NRBFReader.read(&reader)
    }

    static func person(_ w: inout NRBFBytes, id: Int = 1) {
        w.classRecord(id: id, name: "Test.Person", members: [
            ("age", .int32(42)), ("alive", .bool(true)), ("height", .double(1.75)), ("name", .string(id: 50, "Ada")),
        ])
    }

    @Test func headerAndEnd() throws {
        var w = NRBFBytes()
        w.header(root: 7); w.end()
        w.bytes += [0xAA, 0xBB]  // what follows the stream stays unread
        var reader = ByteReader(w.bytes)
        let graph = try NRBFReader.read(&reader)
        #expect(graph.root == 7 && graph.objects.isEmpty)
        #expect(reader.remaining == 2)
    }

    @Test func classWithMembersAndTypes() throws {
        var w = NRBFBytes()
        w.header(); w.library(2); Self.person(&w); w.end()
        let graph = try Self.read(w.bytes)
        let person = try #require(graph.objects[1])
        #expect(person.className == "Test.Person")
        #expect(person.members["age"] == .int(42))
        #expect(person.members["alive"] == .bool(true))
        #expect(person.members["height"] == .double(1.75))
        #expect(person.members["name"] == .string("Ada"))
        #expect(graph.order == [1, 50])
    }

    @Test func classWithIdReusesMetadata() throws {
        var w = NRBFBytes()
        w.header(); w.library(2); Self.person(&w)
        w.classWithId(id: 3, metadata: 1, values: [.int32(7), .bool(false), .double(2), .string(id: 51, "Bo")])
        w.end()
        let graph = try Self.read(w.bytes)
        let other = try #require(graph.objects[3])
        #expect(other.className == "Test.Person")
        #expect(other.members["age"] == .int(7) && other.members["name"] == .string("Bo"))
    }

    @Test func classWithIdOfUnknownMetadataIsCorrupt() {
        var w = NRBFBytes()
        w.header(); w.classWithId(id: 3, metadata: 99, values: []); w.end()
        #expect(throws: OwnDecodeError.corrupt) { try Self.read(w.bytes) }
    }

    @Test func memberReferenceResolves() throws {
        var w = NRBFBytes()
        w.header(); w.library(2)
        w.classRecord(id: 1, name: "Test.Holder", members: [("child", .reference(2, className: "Test.Child"))])
        w.classRecord(id: 2, name: "Test.Child", members: [("value", .int64(1 << 40))])
        w.end()
        let graph = try Self.read(w.bytes)
        #expect(graph.objects[1]?.members["child"] == .reference(2))
        #expect(graph.objects[2]?.members["value"] == .int(1 << 40))
        #expect(graph.order == [1, 2])
    }

    @Test func nestedObjectIsStoredAndReferenced() throws {
        var w = NRBFBytes()
        w.header(); w.library(2)
        // The child's record sits inline where the member value goes.
        w.u8(5); w.i32(1); w.string("Test.Holder"); w.i32(1); w.string("child"); w.u8(4); w.string("Test.Child"); w.i32(2); w.i32(2)
        w.classRecord(id: 2, name: "Test.Child", members: [("value", .byte(9))])
        w.end()
        let graph = try Self.read(w.bytes)
        #expect(graph.objects[1]?.members["child"] == .reference(2))
        #expect(graph.objects[2]?.members["value"] == .uint(9))
    }

    @Test func arraySinglePrimitiveBytes() throws {
        var w = NRBFBytes()
        w.header(); w.u8(15); w.i32(4); w.i32(3); w.u8(2); w.bytes += [1, 2, 3]; w.end()
        let graph = try Self.read(w.bytes)
        #expect(graph.objects[4]?.members["items"] == .bytes([1, 2, 3]))
    }

    @Test func arraySinglePrimitiveInts() throws {
        var w = NRBFBytes()
        w.header(); w.u8(15); w.i32(4); w.i32(2); w.u8(8); w.i32(-1); w.i32(5); w.end()
        let graph = try Self.read(w.bytes)
        #expect(graph.objects[4]?.members["items"] == .array([.int(-1), .int(5)]))
    }

    @Test func arraySingleObject() throws {
        var w = NRBFBytes()
        w.header(); w.objectArray(id: 3, references: [8, 9], nulls: 2); w.end()
        let graph = try Self.read(w.bytes)
        #expect(graph.objects[3]?.members["items"] == .array([.reference(8), .reference(9), .null, .null]))
    }

    @Test func arraySingleString() throws {
        var w = NRBFBytes()
        w.header(); w.u8(17); w.i32(3); w.i32(2); w.u8(6); w.i32(4); w.string("a"); w.u8(10); w.end()
        let graph = try Self.read(w.bytes)
        #expect(graph.objects[3]?.members["items"] == .array([.string("a"), .null]))
    }

    @Test func binaryArray() throws {
        var w = NRBFBytes()
        // Rectangular 2 × 2 of Int16, then a single array of strings.
        w.header()
        w.u8(7); w.i32(3); w.u8(2); w.i32(2); w.i32(2); w.i32(2); w.u8(0); w.u8(7)
        w.bytes += [1, 0, 2, 0, 3, 0, 0xFF, 0xFF]
        w.u8(7); w.i32(4); w.u8(0); w.i32(1); w.i32(2); w.u8(1)
        w.u8(6); w.i32(5); w.string("x"); w.u8(9); w.i32(5)
        w.end()
        let graph = try Self.read(w.bytes)
        #expect(graph.objects[3]?.members["items"] == .array([.int(1), .int(2), .int(3), .int(-1)]))
        #expect(graph.objects[4]?.members["items"] == .array([.string("x"), .reference(5)]))
    }

    @Test func objectNullMultiple() throws {
        var w = NRBFBytes()
        w.header(); w.u8(16); w.i32(3); w.i32(5); w.u8(14); w.i32(4); w.u8(10); w.end()
        let graph = try Self.read(w.bytes)
        #expect(graph.objects[3]?.members["items"] == .array(Array(repeating: .null, count: 5)))
    }

    @Test func nullRunPastTheArrayIsCorrupt() {
        var w = NRBFBytes()
        w.header(); w.u8(16); w.i32(3); w.i32(2); w.u8(13); w.u8(3); w.end()
        #expect(throws: OwnDecodeError.corrupt) { try Self.read(w.bytes) }
    }

    @Test func classWithoutTypesIsUnsupported() {
        var w = NRBFBytes()
        w.header(); w.library(2)
        w.u8(3); w.i32(1); w.string("Test.Untyped"); w.i32(1); w.string("a"); w.i32(2)
        w.end()
        #expect(throws: OwnDecodeError.unsupported) { try Self.read(w.bytes) }
        var s = NRBFBytes()
        s.header(); s.u8(2); s.i32(1); s.string("System.Untyped"); s.i32(0); s.end()
        #expect(throws: OwnDecodeError.unsupported) { try Self.read(s.bytes) }
    }

    @Test func missingHeaderIsNotThisFormat() {
        var w = NRBFBytes()
        w.end()
        #expect(throws: OwnDecodeError.notThisFormat) { try Self.read(w.bytes) }
    }

    @Test func deepNestingThrows() {
        // 100,000 objects each holding the next inline: refused at depth 64, without recursing that deep.
        var w = NRBFBytes()
        w.header(); w.library(2)
        w.u8(5); w.i32(1); w.string("Test.Node"); w.i32(1); w.string("next"); w.u8(2); w.i32(2)
        for id in 2...100_000 { w.u8(1); w.i32(id); w.i32(1) }
        w.u8(10); w.end()
        #expect(throws: OwnDecodeError.corrupt) { try Self.read(w.bytes) }
    }

    @Test func hugeStringLengthThrows() {
        var w = NRBFBytes()
        w.header(); w.u8(6); w.i32(1)
        w.bytes += [0xFF, 0xFF, 0xFF, 0xFF, 0x07]  // 2^31 − 1 bytes claimed
        w.bytes += Array("short".utf8); w.end()
        #expect(throws: OwnDecodeError.truncated) { try Self.read(w.bytes) }
    }

    @Test func hugeArrayLengthThrows() {
        var w = NRBFBytes()
        w.header(); w.u8(16); w.i32(3); w.i32(Int(Int32.max)); w.u8(14); w.i32(Int(Int32.max)); w.end()
        #expect(throws: OwnDecodeError.corrupt) { try Self.read(w.bytes) }
        var p = NRBFBytes()
        p.header(); p.u8(15); p.i32(3); p.i32(Int(Int32.max)); p.u8(9); p.end()
        #expect(throws: OwnDecodeError.truncated) { try Self.read(p.bytes) }
    }

    @Test func truncatedAtEveryLengthThrows() {
        var w = NRBFBytes()
        w.header(); w.library(2); Self.person(&w)
        w.classRecord(id: 2, name: "Test.Holder", members: [("p", .reference(1, className: "Test.Person")), ("n", .null)])
        w.objectArray(id: 3, references: [1, 2], nulls: 1)
        w.u8(15); w.i32(4); w.i32(3); w.u8(2); w.bytes += [1, 2, 3]
        w.end()
        #expect(throws: Never.self) { try Self.read(w.bytes) }
        for length in 0..<w.bytes.count {
            #expect(throws: OwnDecodeError.self, "\(length)") { try Self.read(Array(w.bytes.prefix(length))) }
        }
    }
}
