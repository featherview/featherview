import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import FeatherviewCore

@Suite struct HDROutputTests {
    func convert(_ input: URL, to format: String, _ edit: (inout BatchSettings) -> Void = { _ in }) async throws -> URL {
        var s = BatchSettings()
        s.formatID = format
        s.outputFolder = try Fixtures.makeTempDir().path
        edit(&s)
        let results = await BatchConverter.run(BatchJob(inputs: [BatchInput(url: input, root: nil)], settings: s))
        #expect(results.map(\.status) == [.converted], "\(results.map(\.logLine))")
        return try #require(results.first?.output)
    }

    /// Decoded with the HDR request: an HDR colour space and, in extended linear sRGB, a value above 1.0.
    func isHDR(_ url: URL) throws -> Bool {
        let image = try ImageDecoder.decode(url, hdr: true)
        guard let space = image.colorSpace,
              CGColorSpaceUsesITUR_2100TF(space) || CGColorSpaceUsesExtendedRange(space) else { return false }
        let linear = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
        let width = image.width, height = image.height
        var pixels = [Float](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 32,
                                          bytesPerRow: width * 16, space: linear,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                                              | CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        #expect(drawn)
        return pixels.enumerated().contains { $0.offset % 4 != 3 && $0.element > 1.01 }
    }

    func hdrInput() throws -> URL {
        guard #available(macOS 15, *) else { throw CocoaError(.featureUnsupported) }
        return try Fixtures.writeHDRGainMap(to: try Fixtures.makeTempDir().appendingPathComponent("gm.heic"))
    }

    @Test(.enabled(if: ImageDecoder.supportsHDR)) func hdrInputIsHDR() throws {
        #expect(try isHDR(try hdrInput()))  // the check itself works
    }

    @Test(.enabled(if: ImageDecoder.supportsHDR)) func hdrHEICStaysHDR() async throws {
        #expect(try isHDR(try await convert(try hdrInput(), to: "heic")))
    }

    @Test(.enabled(if: ImageDecoder.supportsHDR)) func hdrToAVIFStaysHDR() async throws {
        #expect(try isHDR(try await convert(try hdrInput(), to: "avif")))
    }

    @Test(.enabled(if: ImageDecoder.supportsHDR)) func hdrToJPEGIsSDR() async throws {
        let output = try await convert(try hdrInput(), to: "jpg")
        #expect(try !isHDR(output))
        #expect(try ImageDecoder.decode(output).bitsPerComponent == 8)
    }

    @Test(.enabled(if: ImageDecoder.supportsHDR)) func sdrToHEICIsSDR() async throws {
        let sdr = try Fixtures.writeImage(to: try Fixtures.makeTempDir().appendingPathComponent("a.jpg"), width: 64, height: 48)
        #expect(try !isHDR(try await convert(sdr, to: "heic")))
    }

    @Test(.enabled(if: ImageDecoder.supportsHDR)) func hdrWithOperationsStaysHDR() async throws {
        let output = try await convert(try hdrInput(), to: "heic") {
            $0.resize.isOn = true
            $0.resize.side = 32
            $0.border.isOn = true
            $0.border.outerWidth = 2
        }
        #expect(try isHDR(output))
        #expect(ImageDecoder.displaySize(of: output) == CGSize(width: 36, height: 28))  // 32 × 24, then 2 each side
    }

    @Test(.enabled(if: ImageDecoder.supportsHDR)) func reduceColoursForcesSDR() async throws {
        let output = try await convert(try hdrInput(), to: "heic") {
            $0.colour.isOn = true
            $0.colour.reduceColours = 16
        }
        #expect(try !isHDR(output))
    }

    /// A 16×8 32-bit float greyscale TIFF of 0.5: ImageIO decodes it as extended linear grey.
    func greyFloatTIFF() throws -> URL {
        let url = try Fixtures.makeTempDir().appendingPathComponent("g.tiff")
        let context = try #require(CGContext(
            data: nil, width: 16, height: 8, bitsPerComponent: 32, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.extendedLinearGray)!,
            bitmapInfo: CGImageAlphaInfo.none.rawValue | CGBitmapInfo.floatComponents.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue))
        context.setFillColor(gray: 0.5, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 16, height: 8))
        let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.tiff.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, try #require(context.makeImage()), nil)
        #expect(CGImageDestinationFinalize(dest))
        return url
    }

    func firstPixel(_ url: URL) throws -> [UInt8] {
        let pixels = try #require(RGBAImage(try ImageDecoder.decode(url)))
        return Array(pixels.pixels.prefix(4))
    }

    func hasGainMap(_ url: URL) throws -> Bool {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        guard #available(macOS 15, *) else { return false }
        return CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypeISOGainMap) != nil
    }

    // GitHub's virtual Macs have no encoder for grey HDR HEIC and AVIF; real Macs do.
    @Test(.enabled(if: ImageDecoder.supportsHDR), .disabled(if: ProcessInfo.processInfo.environment["CI"] != nil),
          arguments: ["heic", "avif"])
    func greyFloatTIFFKeepsItsPixels(format: String) async throws {
        let input = try greyFloatTIFF()
        let pixel = try firstPixel(try await convert(input, to: format))
        #expect(pixel[3] == 255 && pixel[0] > 100, "\(pixel)")
        let saved = try Fixtures.makeTempDir().appendingPathComponent("g.\(format)")
        let output = try #require(FormatRegistry.format(id: format))
        // AVIF's encoder needs a free cooperative-pool thread: off the pool, as Save As runs it.
        try await offPool { try ImageSaver.save(input, page: 0, to: saved, as: output, options: FormatOptions()) }
        let savedPixel = try firstPixel(saved)
        #expect(savedPixel[3] == 255 && savedPixel[0] > 100, "\(savedPixel)")
    }

    /// ImageIO gives float TIFFs extended range even when every pixel is SDR: no gain map for those.
    @Test(.enabled(if: ImageDecoder.supportsHDR)) func sdrFloatTIFFGetsNoGainMap() async throws {
        let input = try Fixtures.writeImage(to: try Fixtures.makeTempDir().appendingPathComponent("f.tiff"),
                                            width: 16, height: 8, type: .tiff, bitsPerComponent: 32)
        #expect(try !hasGainMap(try await convert(input, to: "heic")))
        let saved = try Fixtures.makeTempDir().appendingPathComponent("f.heic")
        try ImageSaver.save(input, page: 0, to: saved, as: try #require(FormatRegistry.format(id: "heic")),
                            options: FormatOptions())
        #expect(try !hasGainMap(saved))
    }

    @Test(.enabled(if: ImageDecoder.supportsHDR)) func hdrHEICHasGainMap() async throws {
        #expect(try hasGainMap(try await convert(try hdrInput(), to: "heic")))  // the check itself works
    }
}
