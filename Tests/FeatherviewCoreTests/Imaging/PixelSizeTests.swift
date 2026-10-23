import CoreGraphics
import Testing
@testable import FeatherviewCore

@Suite struct PixelSizeTests {
    @Test func screenPixelsArePointsTimesScaleRounded() {
        #expect(PixelSize(points: CGSize(width: 1512, height: 982), scale: 2) == PixelSize(width: 3024, height: 1964))
        // A scaled display's fractional points round to the nearest pixel instead of losing one.
        #expect(PixelSize(points: CGSize(width: 1706.67, height: 959.9), scale: 1.5) == PixelSize(width: 2560, height: 1440))
    }

    @Test func noScreenFallsBackToOneRetinaSize() {
        #expect(PixelSize.screens([]) == [PixelSize.fallbackScreen])
        let screens = [(CGSize(width: 1920, height: 1080), CGFloat(1)), (CGSize(width: 1512, height: 982), CGFloat(2))]
        #expect(PixelSize.screens(screens) == [PixelSize(width: 1920, height: 1080), PixelSize(width: 3024, height: 1964)])
    }
}
