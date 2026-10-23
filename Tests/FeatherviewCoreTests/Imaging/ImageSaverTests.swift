import CoreGraphics
import Foundation
import Testing
@testable import FeatherviewCore

/// Saving an image that has no file (the suite itself is in OutputFormatTests.swift).
extension ImageSaverTests {
    private var image: CGImage { Fixtures.animationFrame(0, width: 8, height: 6) }

    @Test func tempURLIsHiddenUniqueAndInTheFolder() {
        let folder = URL(fileURLWithPath: "/tmp/x")
        let a = ImageSaver.tempURL(in: folder), b = ImageSaver.tempURL(in: folder, ext: "jpg")
        #expect(a.deletingLastPathComponent().path == "/tmp/x" && a.lastPathComponent.hasPrefix(".featherview-"))
        #expect(a.pathExtension == "tmp" && b.pathExtension == "jpg" && a.lastPathComponent != b.lastPathComponent)
    }

    @Test func saveImageWritesPNG() throws {
        let url = try Fixtures.makeTempDir().appendingPathComponent("pasted.png")
        try ImageSaver.save(image, to: url, as: .png, options: OutputFormat.png.defaultOptions)
        let back = try ImageDecoder.decode(url)
        #expect(back.width == 8 && back.height == 6)
    }

    @Test func saveImageLeavesNoTempFile() throws {
        let dir = try Fixtures.makeTempDir()
        try ImageSaver.save(image, to: dir.appendingPathComponent("pasted.png"), as: .png,
                            options: OutputFormat.png.defaultOptions)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["pasted.png"])
    }

    @Test func saveImageRefusesAFolder() throws {
        let folder = try Fixtures.makeTempDir().appendingPathComponent("folder.png")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        #expect(throws: (any Error).self) {
            try ImageSaver.save(image, to: folder, as: .png, options: OutputFormat.png.defaultOptions)
        }
        var isFolder: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: folder.path, isDirectory: &isFolder) && isFolder.boolValue)
    }

    @Test func saveImageReplacesExisting() throws {
        let url = try Fixtures.makeTempDir().appendingPathComponent("pasted.png")
        let old = Data("old".utf8)
        try old.write(to: url)
        try ImageSaver.save(image, to: url, as: .png, options: OutputFormat.png.defaultOptions)
        #expect(try Data(contentsOf: url) != old)
        #expect(try ImageDecoder.decode(url).width == 8)
    }
}
