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
            "Focal length": Measurement(value: 50, unit: UnitLength.millimeters)
                .formatted(.measurement(width: .abbreviated, usage: .asProvided)),
        ])
    }

    @Test func missingValuesAreOmitted() {
        #expect(MetadataReader.fields(from: [:], fileSize: nil).isEmpty)
    }

    private func camera(make: String?, model: String?) -> String? {
        var tiff: [CFString: Any] = [:]
        tiff[kCGImagePropertyTIFFMake] = make
        tiff[kCGImagePropertyTIFFModel] = model
        return MetadataReader.fields(from: [kCGImagePropertyTIFFDictionary: tiff], fileSize: nil)
            .first { $0.label == "Camera" }?.value
    }

    @Test func cameraDoesNotRepeatTheMake() {
        #expect(camera(make: "Canon", model: "Canon EOS R6") == "Canon EOS R6")
        #expect(camera(make: "NIKON CORPORATION", model: "NIKON D850") == "NIKON D850")
        #expect(camera(make: "Apple", model: "iPhone 15 Pro") == "Apple iPhone 15 Pro")
        #expect(camera(make: "   ", model: "X100") == "X100")
        #expect(camera(make: "", model: "X100") == "X100")
        #expect(camera(make: "FUJIFILM", model: nil) == "FUJIFILM")
    }

    private func exposure(_ seconds: Double) -> String? {
        let props: [CFString: Any] = [
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifExposureTime: seconds] as [CFString: Any],
        ]
        return MetadataReader.fields(from: props, fileSize: nil).first { $0.label == "Exposure" }?.value
    }

    @Test func formatsExposureTimes() {
        let decimal = { (x: Double) in
            Measurement(value: x, unit: UnitDuration.seconds).formatted(.measurement(width: .abbreviated, usage: .asProvided))
        }
        #expect(exposure(0.004) == "1/250 s")
        #expect(exposure(1.0 / 3) == "1/3 s")
        #expect(exposure(0.5) == "1/2 s")
        #expect(exposure(0.8) == decimal(0.8))
        #expect(exposure(0.6) == decimal(0.6))
        #expect(exposure(0.4) == decimal(0.4))
        #expect(exposure(1) == decimal(1))
        #expect(exposure(2) == decimal(2))
        #expect(exposure(2.5) == decimal(2.5))
    }

    @Test func formatsDateTakenWithTheSystemFormatter() {
        let date = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 8, day: 14, hour: 18, minute: 32, second: 5))!
        #expect(MetadataReader.taken("2026:08:14 18:32:05") == date.formatted(date: .abbreviated, time: .shortened))
        #expect(MetadataReader.taken("0000:00:00 00:00:00") == nil)  // cameras without a clock write this
        #expect(MetadataReader.taken("garbage") == nil)
    }

    @Test func dateTakenPrefersExif() throws {
        let dir = try Fixtures.makeTempDir()
        let exif: [CFString: Any] = [
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2024:03:05 14:30:00"] as [CFString: Any],
        ]
        let url = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 8, height: 8, properties: exif)
        let local = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2024, month: 3, day: 5, hour: 14, minute: 30))
        #expect(MetadataReader.dateTaken(of: url) == local)
    }

    @Test func dateTakenFallsBackToModificationDate() throws {
        let dir = try Fixtures.makeTempDir()
        let url = try Fixtures.writeImage(to: dir.appendingPathComponent("a.png"), width: 8, height: 8, type: .png)
        let modified = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        #expect(MetadataReader.dateTaken(of: url) == modified)
        #expect(MetadataReader.dateTaken(of: dir.appendingPathComponent("missing.jpg")) == nil)
    }

    @Test func fileSizeFollowsSymlinks() throws {
        let dir = try Fixtures.makeTempDir()
        let target = try Fixtures.writeImage(to: dir.appendingPathComponent("r.jpg"), width: 8, height: 8)
        let link = dir.appendingPathComponent("link.jpg")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let size = { (url: URL) in MetadataReader.fields(for: url).first { $0.label == "File size" }?.value }
        #expect(size(target) != nil)
        #expect(size(link) == size(target))
    }
}
