import Foundation
import ImageIO
import Testing
@testable import FeatherviewCore

@Suite struct MetadataCatalogTests {
    private func entry(_ catalog: MetadataCatalog, _ id: String) -> MetadataEntry? {
        catalog.sections.flatMap(\.entries).first { $0.id == id }
    }

    @Test func groupsInOrder() {
        let one: [String: Any] = ["Foo": "x"]
        let catalog = MetadataCatalog.make(properties: [
            "{TIFF}": one, "{PNG}": one, "{Exif}": one, "{JFIF}": one, "{GPS}": one, "{IPTC}": one,
            "PixelWidth": 64,  // top-level scalars belong to no group
        ], xmp: [("dc:title", "Alpine Dusk")])
        #expect(catalog.sections.map(\.id) == ["EXIF", "GPS", "IPTC", "XMP", "TIFF", "JFIF", "PNG"])
        #expect(entry(catalog, "XMP.dc:title")?.value == "Alpine Dusk")
    }

    @Test func readableLabels() {
        #expect(MetadataCatalog.label(for: "ExposureTime") == "Exposure time")
        #expect(MetadataCatalog.label(for: "FooBar") == "Foo bar")
        #expect(MetadataCatalog.label(for: "ISOSpeedLatitude") == "ISO speed latitude")
        #expect(MetadataCatalog.label(for: "dc:format") == "Format")
    }

    @Test func iptcKeysWithSlashGetTheirNames() {
        #expect(MetadataCatalog.label(for: kCGImagePropertyIPTCCaptionAbstract as String) == "Caption")
        #expect(MetadataCatalog.label(for: kCGImagePropertyIPTCProvinceState as String) == "State or province")
        #expect(MetadataCatalog.label(for: kCGImagePropertyIPTCCountryPrimaryLocationName as String) == "Country")
    }

    @Test func distinctTagsGetDistinctNames() {
        let catalog = MetadataCatalog.make(properties: [
            "{Exif}": ["SceneType": 1, "SceneCaptureType": 0, "ISOSpeed": 100, "ISOSpeedRatings": [100]] as [String: Any],
        ], xmp: [])
        let labels = catalog.sections.flatMap(\.entries).map(\.label)
        #expect(Set(labels).count == labels.count)
    }

    @Test func valuesFormatted() throws {
        let url = try Fixtures.makeTempDir().appendingPathComponent("tags.jpg")
        try Fixtures.writeImage(to: url, width: 8, height: 8, properties: [
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifExposureTime: 0.004,
                                             kCGImagePropertyExifISOSpeedRatings: [400]] as [CFString: Any],
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 46.6356,
                                            kCGImagePropertyGPSLatitudeRef: "N"] as [CFString: Any],
            kCGImagePropertyIPTCDictionary: [kCGImagePropertyIPTCKeywords: ["snow", "dusk"]] as [CFString: Any],
        ])
        let catalog = MetadataCatalog.read(url)
        let degrees = 46.6356.formatted(.number.grouping(.never).precision(.fractionLength(4)))
        #expect(entry(catalog, "EXIF.ExposureTime")?.value == "1/250 s")
        #expect(entry(catalog, "EXIF.ExposureTime")?.label == "Exposure time")
        #expect(entry(catalog, "EXIF.ISOSpeedRatings")?.value == "400")
        #expect(entry(catalog, "GPS.Latitude")?.value == "\(degrees)° N")
        #expect(entry(catalog, "IPTC.Keywords")?.value == "snow, dusk")
        let xmp = catalog.sections.first { $0.id == "XMP" }?.entries.map(\.tag) ?? []
        #expect(xmp.contains("dc:subject"))
        #expect(!xmp.contains { $0.hasPrefix("exif:") || $0.hasPrefix("tiff:") || $0.hasPrefix("iio:") })
        #expect(entry(catalog, "XMP.dc:subject")?.value == "snow, dusk")
    }

    @Test func binaryEntriesHidden() {
        let catalog = MetadataCatalog.make(properties: [
            "{Exif}": ["MakerNote": Data(count: 1_000_000), "ExposureTime": 0.004,
                       "OffsetTimeOriginal": "+02:00"] as [String: Any],
            "{TIFF}": ["JPEGInterchangeFormat": 1234, "JPEGInterchangeFormatLength": 5678,
                       "StripOffsets": [8], "Make": "Canon"] as [String: Any],
            "{ThumbnailData}": ["Data": Data(count: 4)],
        ], xmp: [("xmpGImg:Thumbnails", "abc")])
        #expect(catalog.hiddenCount == 6)
        #expect(catalog.sections.map(\.id) == ["EXIF", "TIFF"])
        #expect(catalog.sections.flatMap(\.entries).map(\.tag).sorted()
                == ["ExposureTime", "Make", "OffsetTimeOriginal"])
    }

    @Test func filterMatchesTagLabelValue() {
        let catalog = MetadataCatalog.make(properties: [
            "{Exif}": ["ISOSpeedRatings": [400], "ExposureTime": 0.004] as [String: Any],
            "{IPTC}": ["City": "Andermatt"],
        ], xmp: [])
        #expect(catalog.filtered("iso").sections.flatMap(\.entries).map(\.tag) == ["ISOSpeedRatings"])
        #expect(catalog.filtered("Ändermatt").sections.map(\.id) == ["IPTC"])
        #expect(catalog.filtered("exposure TIME").sections.flatMap(\.entries).map(\.tag) == ["ExposureTime"])
        #expect(catalog.filtered("1/250").sections.flatMap(\.entries).map(\.tag) == ["ExposureTime"])
        #expect(catalog.filtered("").sections == catalog.sections)
        #expect(catalog.filtered("nothing").sections.isEmpty)
    }

    @Test func copyTextFormat() {
        let entries = [
            MetadataEntry(id: "EXIF.ExposureTime", label: "Exposure time", tag: "ExposureTime", value: "1/250 s"),
            MetadataEntry(id: "TIFF.Make", label: "Camera maker", tag: "Make", value: "Canon"),
        ]
        #expect(MetadataCatalog.copyText(entries)
                == "Exposure time (ExposureTime): 1/250 s\nCamera maker (Make): Canon")
    }
}
