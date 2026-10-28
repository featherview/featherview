import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
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

    private func packet(_ body: String) -> String {
        #"<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">"#
            + #"<rdf:Description rdf:about="" xmlns:dc="http://purl.org/dc/elements/1.1/""#
            + #" xmlns:photoshop="http://ns.adobe.com/photoshop/1.0/" xmlns:xmp="http://ns.adobe.com/xap/1.0/">"#
            + body + "</rdf:Description></rdf:RDF></x:xmpmeta>"
    }

    @Test func xmpListsOnlyThePacketsTags() throws {
        let url = try Fixtures.writeImage(to: Fixtures.makeTempDir().appendingPathComponent("artist.jpg"),
                                          width: 8, height: 8, properties: [
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFArtist: "X"] as [CFString: Any],
        ])
        try Fixtures.insertJPEGMetadata(into: url, xmp: packet(
            #"<dc:title><rdf:Alt><rdf:li xml:lang="x-default">T</rdf:li></rdf:Alt></dc:title>"#))
        let catalog = MetadataCatalog.read(url)
        #expect(catalog.sections.first { $0.id == "XMP" }?.entries.map(\.tag) == ["dc:title"])
        #expect(!catalog.sections.contains { $0.id == "IPTC" })
    }

    @Test func iptcShowsTheFilesOwnRecords() throws {
        let url = try Fixtures.writeImage(to: Fixtures.makeTempDir().appendingPathComponent("both.jpg"),
                                          width: 8, height: 8)
        try Fixtures.insertJPEGMetadata(into: url, xmp: packet(
            "<dc:subject><rdf:Bag><rdf:li>alpha</rdf:li></rdf:Bag></dc:subject>"
            + "<dc:creator><rdf:Seq><rdf:li>Me</rdf:li></rdf:Seq></dc:creator>"
            + #"<dc:title><rdf:Alt><rdf:li xml:lang="x-default">Hello</rdf:li></rdf:Alt></dc:title>"#
            + "<photoshop:City>Zug</photoshop:City><xmp:Rating>4</xmp:Rating>"),
            iptc: [(25, "alpha"), (25, "beta"), (120, "Andermatt")])
        let catalog = MetadataCatalog.read(url)
        #expect(entry(catalog, "IPTC.Keywords")?.value == "alpha, beta")
        #expect(entry(catalog, "IPTC.Caption/Abstract")?.value == "Andermatt")
        #expect(catalog.sections.first { $0.id == "IPTC" }?.entries.map(\.tag).sorted()
                == ["Caption/Abstract", "Keywords"])
        #expect(entry(catalog, "XMP.dc:subject")?.value == "alpha")
        #expect(entry(catalog, "XMP.dc:description") == nil)
    }

    @Test func onlyTheFilesOwnSegmentsCount() throws {
        // An IPTC resource and an XMP packet after the image data, as in a placed photo or a second image.
        let url = try Fixtures.writeImage(to: Fixtures.makeTempDir().appendingPathComponent("trailer.jpg"),
                                          width: 8, height: 8)
        let records = [0x1C, 2, 25] + Fixtures.be16(5) + Array("alpha".utf8) + [0]
        let trailer = Array("8BIM".utf8) + [0x04, 0x04, 0, 0] + Fixtures.be32(records.count) + records
            + Array(packet("<photoshop:City>Zug</photoshop:City>").utf8)
        try (Data(contentsOf: url) + trailer).write(to: url)
        let catalog = MetadataCatalog.read(url)
        #expect(!catalog.sections.contains { $0.id == "IPTC" || $0.id == "XMP" })
    }

    @Test(arguments: [UTType.jpeg, .heic]) func gainMapXMPIsNotThePictures(type: UTType) throws {
        let url = try Fixtures.writeAppleGainMap(to: Fixtures.makeTempDir().appendingPathComponent("hdr")
            .appendingPathExtension(for: type), type: type)
        #expect(!MetadataCatalog.read(url).sections.contains { $0.id == "XMP" })
    }

    @Test func tiffShowsItsOwnIPTCAndXMP() throws {
        let url = try Fixtures.writeImage(to: Fixtures.makeTempDir().appendingPathComponent("tags.tif"),
                                          width: 8, height: 8, type: .tiff, properties: [
            kCGImagePropertyIPTCDictionary: [kCGImagePropertyIPTCKeywords: ["snow", "dusk"]] as [CFString: Any],
        ])
        let catalog = MetadataCatalog.read(url)
        #expect(entry(catalog, "IPTC.Keywords")?.value == "snow, dusk")
        #expect(entry(catalog, "XMP.dc:subject")?.value == "snow, dusk")
    }

    @Test func pngHasNoIPTCOfItsOwn() throws {
        // ImageIO keeps IPTC in a PNG's XMP and reads an "{IPTC}" back from it.
        let url = try Fixtures.writeImage(to: Fixtures.makeTempDir().appendingPathComponent("tags.png"),
                                          width: 8, height: 8, type: .png, properties: [
            kCGImagePropertyIPTCDictionary: [kCGImagePropertyIPTCKeywords: ["snow"]] as [CFString: Any],
        ])
        let catalog = MetadataCatalog.read(url)
        #expect(!catalog.sections.contains { $0.id == "IPTC" })
        #expect(entry(catalog, "XMP.dc:subject")?.value == "snow")
    }

    @Test func iptcOverOneSegmentShows() throws {
        let keywords = (0..<3_000).map { "keyword \($0) of a long list" }  // about 90 KB of records
        let jpeg = try Fixtures.writeImage(to: Fixtures.makeTempDir().appendingPathComponent("big.jpg"),
                                           width: 8, height: 8)
        try Fixtures.insertJPEGMetadata(into: jpeg, iptc: keywords.map { (25, $0) } + [(120, "Andermatt")])
        let tiff = try Fixtures.writeImage(to: Fixtures.makeTempDir().appendingPathComponent("big.tif"),
                                           width: 8, height: 8, type: .tiff, properties: [
            kCGImagePropertyIPTCDictionary: [kCGImagePropertyIPTCKeywords: keywords] as [CFString: Any],
        ])
        for url in [jpeg, tiff] {
            let catalog = MetadataCatalog.read(url)
            #expect(entry(catalog, "IPTC.Keywords")?.value == keywords.joined(separator: ", "), "\(url.lastPathComponent)")
        }
        #expect(entry(MetadataCatalog.read(jpeg), "IPTC.Caption/Abstract")?.value == "Andermatt")
    }

    @Test func xmpWithoutItsXmpmetaWrapper() {
        let packet = #"<?xpacket begin="" id="W5M0MpCehiHzreSzNTczkc9d"?>"#
            + #"<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">"#
            + #"<rdf:Description rdf:about="" xmlns:photoshop="http://ns.adobe.com/photoshop/1.0/">"#
            + #"<photoshop:City>Zug</photoshop:City></rdf:Description></rdf:RDF><?xpacket end="w"?>"#
        #expect(MetadataCatalog.xmp(in: Data(packet.utf8)).map(\.0) == ["photoshop:City"])
    }

    @Test func makerNoteDictionariesHidden() {
        let catalog = MetadataCatalog.make(properties: [
            "{MakerApple}": ["1": 14, "8": [0.1, 0.2]] as [String: Any],
            "{MakerCanon}": ["LensModel": "EF50mm"],
            "{Exif}": ["ExposureTime": 0.004],
        ], xmp: [])
        #expect(catalog.sections.map(\.id) == ["EXIF"])
        #expect(catalog.hiddenCount == 3)
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
