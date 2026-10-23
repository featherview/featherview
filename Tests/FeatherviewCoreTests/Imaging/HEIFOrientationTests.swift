import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import FeatherviewCore

@Suite struct HEIFOrientationTests {
    @available(macOS 15, *)
    func gainMapHEIC(orientation: Int = 1) throws -> Data {
        let url = try Fixtures.writeHDRGainMap(to: try Fixtures.makeTempDir().appendingPathComponent("gm.heic"),
                                               orientation: orientation)
        return try Data(contentsOf: url)
    }

    /// ImageIO's reading of `data`: orientation, the stored pixels and the gain map's bytes.
    @available(macOS 15, *)
    func readBack(_ data: Data) -> (orientation: Int?, pixels: Data?, gainMap: Data?) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return (nil, nil, nil) }
        let gainMap = CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypeISOGainMap)
            as? [CFString: Any]
        return (props[kCGImagePropertyOrientation] as? Int ?? 1, image.dataProvider?.data as Data?,
                gainMap?[kCGImageAuxiliaryDataInfoData] as? Data)
    }

    static let layouts: [HEIFLayout.Options] = [
        .init(mdatFirst: true),
        .init(baseSize: 4, useBase: true),
        .init(ilocVersion: 2, offsetSize: 8, baseSize: 8, useBase: true),
        .init(ilocVersion: 2, offsetSize: 8),
        .init(wideIPMA: true),
        .init(mdatFirst: true, ilocVersion: 2, offsetSize: 8, baseSize: 8, useBase: true, wideIPMA: true),
    ]

    @Test(arguments: layouts)
    func otherLayoutsTakeTheOrientationAndKeepTheirData(_ layout: HEIFLayout.Options) throws {
        guard #available(macOS 15, *) else { return }
        let file = HEIFLayout.relayout(try gainMapHEIC(), layout)
        let before = readBack(file)
        #expect(before.orientation == 1 && before.pixels != nil && before.gainMap != nil)  // the layout itself is valid
        #expect(HEIFLayout.exifOrientation(file) == 1)

        for orientation in [6, 7, 2, 1] {
            let rewritten = try #require(HEIFOrientation.setting(orientation, in: file), "\(layout)")
            let after = readBack(rewritten)
            #expect(after.orientation == orientation && after.pixels == before.pixels && after.gainMap == before.gainMap)
            #expect(HEIFLayout.exifOrientation(rewritten) == orientation)
            // Only the Exif orientation tag (2 bytes) may differ in the data.
            let (old, new) = (HEIFLayout.mdatPayload(file), HEIFLayout.mdatPayload(rewritten))
            #expect(old.count == new.count && zip(old, new).filter { $0 != $1 }.count <= 2)
        }
    }

    @Test func refusesABoxSizeThatOverflows() throws {
        guard #available(macOS 15, *) else { return }
        var file = try gainMapHEIC()
        file += HEIFLayout.be(1, 4) + Array("free".utf8) + HEIFLayout.be(0x7FFF_FFFF_FFFF_FFF0, 8)
        #expect(CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithData(file as CFData, nil)!, 0, nil) != nil)
        #expect(HEIFOrientation.setting(6, in: file) == nil)
    }

    @Test func refusesABaseOffsetThatOverflows() throws {
        guard #available(macOS 15, *) else { return }
        let file = HEIFLayout.relayout(try gainMapHEIC(), .init(
            ilocVersion: 2, offsetSize: 8, baseSize: 8, useBase: true, baseOverride: 0x7FFF_FFFF_FFFF_FFF0))
        #expect(HEIFOrientation.setting(6, in: file) == nil)
    }

    @Test func refusesSequences() throws {
        guard #available(macOS 15, *) else { return }
        // A moov's chunk offsets would not move with the data.
        let file = try gainMapHEIC() + HEIFLayout.box("moov", [])
        #expect(HEIFOrientation.setting(6, in: file) == nil)
    }

    @Test func survivesTruncatedFiles() throws {
        guard #available(macOS 15, *) else { return }
        let data = try gainMapHEIC()
        #expect(HEIFOrientation.setting(6, in: data) != nil)
        for length in 0..<data.count { _ = HEIFOrientation.setting(6, in: data.prefix(length)) }  // must not trap
    }
}
