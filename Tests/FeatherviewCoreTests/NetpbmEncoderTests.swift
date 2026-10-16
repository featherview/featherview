import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct NetpbmEncoderTests {
    static let image = RGBAImage(width: 2, height: 1, pixels: [255, 0, 0, 255, 10, 20, 30, 0])

    @Test func pgmIsRoundedLumaAfterTheHeader() {
        #expect(NetpbmEncoder.pgm(Self.image) == Data("P5\n2 1\n255\n".utf8) + [76, 18])
    }

    @Test func ppmIsRGBAfterTheHeaderWithoutAlpha() {
        #expect(NetpbmEncoder.ppm(Self.image) == Data("P6\n2 1\n255\n".utf8) + [255, 0, 0, 10, 20, 30])
    }
}
