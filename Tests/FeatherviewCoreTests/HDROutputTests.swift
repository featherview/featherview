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
}
