import Foundation
import ImageIO
import Testing
@testable import FeatherviewCore

@Suite struct MetadataReaderTests {
    @Test func mapsCameraFields() {
        let props: [CFString: Any] = [
            kCGImagePropertyPixelWidth: 3000,
            kCGImagePropertyPixelHeight: 2000,
            kCGImagePropertyOrientation: 6,
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFMake: "Canon ",
                kCGImagePropertyTIFFModel: "EOS R6",
            ] as [CFString: Any],
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifExposureTime: 0.004,
                kCGImagePropertyExifFNumber: 8.0,
                kCGImagePropertyExifISOSpeedRatings: [400],
                kCGImagePropertyExifFocalLength: 49.6,
            ] as [CFString: Any],
        ]
        let fields = MetadataReader.fields(from: props, fileSize: nil)
        let byLabel = Dictionary(uniqueKeysWithValues: fields.map { ($0.label, $0.value) })
        #expect(byLabel == [
            "Dimensions": "2000 × 3000",  // orientation 6 swaps width and height
            "Camera": "Canon EOS R6",
            "Exposure": "1/250 s",
            "Aperture": "f/8",
            "ISO": "400",
            "Focal length": "50 mm",
        ])
    }

    @Test func missingValuesAreOmitted() {
        #expect(MetadataReader.fields(from: [:], fileSize: nil).isEmpty)
    }

    @Test func readsFileSizeFromDisk() throws {
        let dir = try Fixtures.makeTempDir()
        let url = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 8, height: 8)
        #expect(MetadataReader.fields(for: url).contains { $0.label == "File size" })
    }
}
