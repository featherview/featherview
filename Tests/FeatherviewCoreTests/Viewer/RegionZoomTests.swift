import CoreGraphics
import FeatherviewCore
import Testing

struct RegionZoomTests {
    @Test func bigStepUsesRegion() {
        let screen = [PixelSize(width: 3024, height: 1964)]
        #expect(RegionZoom.usesRegion(image: PixelSize(width: 69536, height: 22230), step: 0, screens: screen))
        #expect(RegionZoom.usesRegion(image: PixelSize(width: 69536, height: 22230), step: 2, screens: screen))
        #expect(!RegionZoom.usesRegion(image: PixelSize(width: 4032, height: 3024), step: 0, screens: screen))  // 12 MP
        #expect(!RegionZoom.usesRegion(image: PixelSize(width: 12000, height: 8000), step: 3, screens: screen))
    }

    @Test func regionGrowsAndClamps() {
        let image = PixelSize(width: 69536, height: 22230)
        #expect(RegionZoom.region(visible: CGRect(x: 1000, y: 1000, width: 3000, height: 2000), image: image, step: 0)
                == CGRect(x: 0, y: 0, width: 5500, height: 4000))
        #expect(RegionZoom.region(visible: CGRect(x: 68000, y: 21000, width: 3000, height: 2000), image: image, step: 0)
                == CGRect(x: 66500, y: 20000, width: 3036, height: 2230))
    }

    @Test func regionAlignsToStep() {
        let r = RegionZoom.region(visible: CGRect(x: 10001, y: 10003, width: 3000, height: 2000),
                                  image: PixelSize(width: 69536, height: 22230), step: 2)
        #expect(r == CGRect(x: 8500, y: 9000, width: 6004, height: 4004))  // grown 8501…14501 × 9003…13003, snapped to 4
        #expect(RegionZoom.decodeSize(region: r, step: 2) == PixelSize(width: 1501, height: 1001))
    }

    @Test func newRegionNearTheMarginOnly() {
        let image = PixelSize(width: 69536, height: 22230)
        let decoded = CGRect(x: 8500, y: 9000, width: 6000, height: 4000)
        #expect(!RegionZoom.needsNewRegion(visible: CGRect(x: 10000, y: 10000, width: 3000, height: 2000), decoded: decoded, image: image))
        #expect(RegionZoom.needsNewRegion(visible: CGRect(x: 11400, y: 10000, width: 3000, height: 2000), decoded: decoded, image: image))
        #expect(!RegionZoom.needsNewRegion(visible: CGRect(x: 0, y: 0, width: 3000, height: 2000),
                                           decoded: CGRect(x: 0, y: 0, width: 4500, height: 3000), image: image))  // picture's edge
    }
}
