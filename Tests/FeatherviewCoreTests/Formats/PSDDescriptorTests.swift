import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct PSDDescriptorTests {
    /// Builds descriptor bytes the way Photoshop writes them (big-endian).
    struct Bytes {
        var data: [UInt8] = []
        mutating func u32(_ v: UInt32) { data += withUnsafeBytes(of: v.bigEndian, Array.init) }
        mutating func i64(_ v: Int64) { data += withUnsafeBytes(of: v.bigEndian, Array.init) }
        mutating func double(_ v: Double) { data += withUnsafeBytes(of: v.bitPattern.bigEndian, Array.init) }
        mutating func os(_ s: String) { data += Array(s.utf8) }
        /// A key or class ID: length 0 and four characters, or the length and a longer string.
        mutating func id(_ s: String) {
            u32(s.utf8.count == 4 ? 0 : UInt32(s.utf8.count))
            os(s)
        }
        /// A Unicode string with Photoshop's trailing NUL.
        mutating func unicode(_ s: String) {
            let units = Array(s.utf16) + [0]
            u32(UInt32(units.count))
            for u in units { data += [UInt8(u >> 8), UInt8(u & 0xFF)] }
        }
        mutating func header(_ classID: String, count: Int) { unicode(""); id(classID); u32(UInt32(count)) }
    }

    @Test func readsNestedObjectsAndLists() throws {
        var b = Bytes()
        b.header("null", count: 2)
        b.id("Clr "); b.os("Objc")
        b.header("RGBC", count: 3)
        b.id("Rd  "); b.os("doub"); b.double(255)
        b.id("Grn "); b.os("doub"); b.double(128)
        b.id("Bl  "); b.os("doub"); b.double(0)
        b.id("Lst "); b.os("VlLs"); b.u32(2)
        b.os("long"); b.u32(7)
        b.os("bool"); b.data.append(1)

        let descriptor = try PSDDescriptor(b.data[...])
        #expect(descriptor.classID == "null")
        let colour = PSDDescriptor(classID: "RGBC", items: [("Rd  ", .double(255)), ("Grn ", .double(128)), ("Bl  ", .double(0))])
        #expect(descriptor["Clr "] == .object(colour))
        #expect(descriptor["Lst "] == .list([.int(7), .bool(true)]))
        #expect(descriptor.items.map(\.key) == ["Clr ", "Lst "])
        #expect(descriptor["none"] == nil)
    }

    @Test func readsUnitsTextEnumsAndRaw() throws {
        var b = Bytes()
        b.u32(16)
        b.header("GdFl", count: 7)
        b.id("Opct"); b.os("UntF"); b.os("#Prc"); b.double(50)
        b.id("Nm  "); b.os("TEXT"); b.unicode("Gradient")
        b.id("Md  "); b.os("enum"); b.id("BlnM"); b.id("Mltp")
        b.id("Data"); b.os("tdta"); b.u32(3); b.data += [1, 2, 3]
        b.id("Pts "); b.os("UnFl"); b.os("#Pxl"); b.u32(2); b.double(1); b.double(2)
        b.id("Big "); b.os("comp"); b.i64(1 << 40)
        b.id("longKeyName"); b.os("type"); b.unicode("Class"); b.id("Grdn")

        let descriptor = try PSDDescriptor.versioned(Data(b.data))
        #expect(descriptor.classID == "GdFl")
        #expect(descriptor["Opct"] == .unit("#Prc", 50))
        #expect(descriptor["Nm  "] == .text("Gradient"))
        #expect(descriptor["Md  "] == .enumerated(type: "BlnM", value: "Mltp"))
        #expect(descriptor["Data"] == .raw(Data([1, 2, 3])))
        #expect(descriptor["Pts "] == .list([.unit("#Pxl", 1), .unit("#Pxl", 2)]))
        #expect(descriptor["Big "] == .int(1 << 40))
        #expect(descriptor["longKeyName"] == .text("Grdn"))
    }

    /// A reference (`obj `) is parsed to find its end and kept as its bytes.
    @Test func readsReferencesAsRaw() throws {
        var b = Bytes()
        b.header("null", count: 2)
        b.id("null"); b.os("obj ")
        let start = b.data.count
        b.u32(1)
        b.os("Enmr"); b.unicode(""); b.id("Lyr "); b.id("Ordn"); b.id("Trgt")
        let reference = Array(b.data[start...])
        b.id("Aftr"); b.os("long"); b.u32(3)

        let descriptor = try PSDDescriptor(b.data[...])
        #expect(descriptor["null"] == .raw(Data(reference)))
        #expect(descriptor["Aftr"] == .int(3))
    }

    @Test func rejectsUnknownTypeAndOverruns() throws {
        var unknown = Bytes()
        unknown.header("null", count: 1)
        unknown.id("Key "); unknown.os("zzzz"); unknown.u32(0)
        #expect(throws: OwnDecodeError.self) { try PSDDescriptor(unknown.data[...]) }

        var overrun = Bytes()
        overrun.header("null", count: 1)
        overrun.id("Lst "); overrun.os("VlLs"); overrun.u32(1_000_000)
        overrun.os("long"); overrun.u32(1)
        #expect(throws: OwnDecodeError.self) { try PSDDescriptor(overrun.data[...]) }

        var tooMany = Bytes()
        tooMany.header("null", count: 1_000_000)
        #expect(throws: OwnDecodeError.self) { try PSDDescriptor(tooMany.data[...]) }

        var rawPastEnd = Bytes()
        rawPastEnd.header("null", count: 1)
        rawPastEnd.id("Data"); rawPastEnd.os("tdta"); rawPastEnd.u32(100); rawPastEnd.data += [1, 2]
        #expect(throws: OwnDecodeError.self) { try PSDDescriptor(rawPastEnd.data[...]) }

        var deep = Bytes()
        for _ in 0..<40 { deep.header("null", count: 1); deep.id("Nest"); deep.os("Objc") }
        deep.header("null", count: 0)
        #expect(throws: OwnDecodeError.self) { try PSDDescriptor(deep.data[...]) }

        var shallow = Bytes()
        for _ in 0..<5 { shallow.header("null", count: 1); shallow.id("Nest"); shallow.os("Objc") }
        shallow.header("null", count: 0)
        #expect(throws: Never.self) { try PSDDescriptor(shallow.data[...]) }

        var wrongVersion = Bytes()
        wrongVersion.u32(15); wrongVersion.header("null", count: 0)
        #expect(throws: OwnDecodeError.self) { try PSDDescriptor.versioned(Data(wrongVersion.data)) }
    }

    /// A slice that doesn't start at index 0 reads the same.
    @Test func readsFromAnOffsetSlice() throws {
        var b = Bytes()
        b.data = [9, 9, 9]
        b.header("null", count: 1)
        b.id("Rd  "); b.os("long"); b.u32(UInt32(bitPattern: -5))
        #expect(try PSDDescriptor(b.data[3...])["Rd  "] == .int(-5))
    }
}
