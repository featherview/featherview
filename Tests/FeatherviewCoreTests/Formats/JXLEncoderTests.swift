import CoreGraphics
import Foundation
import ImageIO
import os
import Testing
@testable import FeatherviewCore
@testable import FeatherviewJXL

@Suite struct JXLEncoderTests {
    @Test func writesJXLImageIOReads() throws {
        let data = try JXLEncoder.encode(Self.image(64, 48), quality: 90, lossless: false, effort: 7, xmp: nil)
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        #expect(CGImageSourceGetType(source) as String? == "public.jpeg-xl")
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(decoded.width == 64 && decoded.height == 48)
    }

    @Test func losslessRoundTripsExactly() throws {
        let image = Self.image(64, 48, opaque: false)
        let data = try JXLEncoder.encode(image, quality: 90, lossless: true, effort: 7, xmp: nil)
        #expect(try Self.rgba8(Self.decode(data)) == Self.rgba8(image))
    }

    @Test func sixteenBitLosslessRoundTrips() throws {
        let (width, height) = (16, 8)
        var samples = [UInt16]()
        for i in 0..<(width * height * 3) { samples.append(UInt16(truncatingIfNeeded: i &* 2_731 &+ 1)) }
        let bytes = samples.withUnsafeBytes { Data($0) }
        let image = try #require(CGImage(
            width: width, height: height, bitsPerComponent: 16, bitsPerPixel: 48, bytesPerRow: width * 6,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue | CGBitmapInfo.byteOrder16Little.rawValue),
            provider: CGDataProvider(data: bytes as CFData)!, decode: nil, shouldInterpolate: false,
            intent: .defaultIntent))
        let data = try JXLEncoder.encode(image, quality: 90, lossless: true, effort: 7, xmp: nil)
        let decoded = try Self.decode(data)
        #expect(decoded.bitsPerComponent == 16)
        #expect(Self.rgba16(decoded) == Self.rgba16(image))
    }

    @Test func qualityChangesSize() throws {
        let image = Self.image(128, 96)
        let low = try JXLEncoder.encode(image, quality: 20, lossless: false, effort: 7, xmp: nil)
        let high = try JXLEncoder.encode(image, quality: 95, lossless: false, effort: 7, xmp: nil)
        let top = try JXLEncoder.encode(image, quality: 100, lossless: false, effort: 7, xmp: nil)
        #expect(low.count < high.count)
        #expect(top.count >= high.count)
    }

    @Test func keepsDisplayP3() throws {
        let p3 = try JXLEncoder.encode(Self.image(32, 32, space: CGColorSpace(name: CGColorSpace.displayP3)!),
                                       quality: 90, lossless: false, effort: 7, xmp: nil)
        #expect(Self.properties(p3)[kCGImagePropertyProfileName as String] as? String == "Display P3")
        let srgb = try JXLEncoder.encode(Self.image(32, 32), quality: 90, lossless: false, effort: 7, xmp: nil)
        #expect(Self.properties(srgb)[kCGImagePropertyProfileName as String] as? String == "sRGB IEC61966-2.1")
    }

    @Test func greyAndCMYKBecomeSRGB() throws {
        let grey = CGContext(data: nil, width: 40, height: 30, bitsPerComponent: 8, bytesPerRow: 0,
                             space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        grey.setFillColor(gray: 0.4, alpha: 1)
        grey.fill(CGRect(x: 0, y: 0, width: 20, height: 30))
        let cmyk = CGContext(data: nil, width: 40, height: 30, bitsPerComponent: 8, bytesPerRow: 0,
                             space: CGColorSpaceCreateDeviceCMYK(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        cmyk.setFillColor(cyan: 0.8, magenta: 0.1, yellow: 0.3, black: 0.1, alpha: 1)
        cmyk.fill(CGRect(x: 0, y: 0, width: 20, height: 30))
        for image in [grey.makeImage()!, cmyk.makeImage()!] {
            let data = try JXLEncoder.encode(image, quality: 90, lossless: false, effort: 7, xmp: nil)
            let decoded = try Self.decode(data)
            #expect(decoded.width == 40 && decoded.height == 30)
            #expect(Self.properties(data)[kCGImagePropertyColorModel as String] as? String
                    == kCGImagePropertyColorModelRGB as String)
        }
    }

    @Test func keepsAlphaOnlyWhenPresent() throws {
        let context = Self.context(8, 8)
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 128.0 / 255)
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let translucent = try JXLEncoder.encode(context.makeImage()!, quality: 90, lossless: true, effort: 7, xmp: nil)
        #expect(Self.rgba8(try Self.decode(translucent))[3] == 128)

        let opaque = try JXLEncoder.encode(Self.image(8, 8), quality: 90, lossless: true, effort: 7, xmp: nil)
        let alpha = try Self.decode(opaque).alphaInfo
        #expect([CGImageAlphaInfo.none, .noneSkipFirst, .noneSkipLast].contains(alpha))
    }

    @Test func xmpBoxIsRead() throws {
        let metadata = CGImageMetadataCreateMutable()
        CGImageMetadataSetValueWithPath(metadata, nil, "exif:DateTimeOriginal" as CFString, "2024-05-01T10:20:30" as CFString)
        CGImageMetadataSetValueWithPath(metadata, nil, "tiff:Model" as CFString, "Test Camera" as CFString)
        let xmp = try #require(CGImageMetadataCreateXMPData(metadata, nil)) as Data
        let data = try JXLEncoder.encode(Self.image(16, 16), quality: 90, lossless: false, effort: 7, xmp: xmp)
        let properties = Self.properties(data)
        let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any]
        let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
        #expect((exif?[kCGImagePropertyExifDateTimeOriginal as String] as? String)?.hasPrefix("2024") == true)
        #expect(tiff?[kCGImagePropertyTIFFModel as String] as? String == "Test Camera")

        let bare = try JXLEncoder.encode(Self.image(16, 16), quality: 90, lossless: false, effort: 7, xmp: nil)
        #expect(Self.properties(bare)[kCGImagePropertyExifDictionary as String] == nil)
    }

    @Test(arguments: [1, 9]) func lowestAndHighestEffortEncode(effort: Int) throws {
        let data = try JXLEncoder.encode(Self.image(32, 32), quality: 90, lossless: false, effort: effort, xmp: nil)
        #expect(try Self.decode(data).width == 32)
    }

    @Test func outOfRangeOptionsAreClamped() throws {
        for (quality, effort) in [(0, 0), (500, 12)] {
            let data = try JXLEncoder.encode(Self.image(32, 32), quality: quality, lossless: false, effort: effort, xmp: nil)
            #expect(try Self.decode(data).width == 32)
        }
    }

    @Test func atMostTwoEncodesAtOnce() throws {
        let image = Self.image(256, 256)
        let results = OSAllocatedUnfairLock(initialState: [Data?](repeating: nil, count: 6))
        JXLEncoder.resetPeakInFlight()
        DispatchQueue.concurrentPerform(iterations: 6) { i in
            let data = try? JXLEncoder.encode(image, quality: 90, lossless: false, effort: 7, xmp: nil)
            results.withLock { $0[i] = data }
        }
        #expect(JXLEncoder.peakInFlight <= JXLEncoder.maxConcurrentEncodes)
        for data in results.withLock({ $0 }) {
            #expect(try Self.decode(try #require(data)).width == 256)
        }
    }

    @Test func parallelEncodesMatchASerialOne() throws {
        let image = Self.image(256, 192)
        let serial = try JXLEncoder.encode(image, quality: 90, lossless: false, effort: 7, xmp: nil)
        let results = OSAllocatedUnfairLock(initialState: [Data?](repeating: nil, count: 6))
        DispatchQueue.concurrentPerform(iterations: 6) { i in
            let data = try? JXLEncoder.encode(image, quality: 90, lossless: false, effort: 7, xmp: nil)
            results.withLock { $0[i] = data }
        }
        for data in results.withLock({ $0 }) { #expect(data == serial) }
    }

    // MARK: - Helpers

    private static func context(_ width: Int, _ height: Int,
                                space: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!,
                                opaque: Bool = false) -> CGContext {
        let alpha: CGImageAlphaInfo = opaque ? .noneSkipLast : .premultipliedLast
        return CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                         space: space, bitmapInfo: alpha.rawValue)!
    }

    /// Varied opaque pixels: a gradient with a hard edge, so lossy encodes differ by quality.
    private static func image(_ width: Int, _ height: Int,
                              space: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!,
                              opaque: Bool = true) -> CGImage {
        let context = context(width, height, space: space, opaque: opaque)
        let pixels = context.data!.assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                pixels[i] = UInt8((x * 255) / max(width - 1, 1))
                pixels[i + 1] = UInt8((y * 255) / max(height - 1, 1))
                pixels[i + 2] = UInt8(((x ^ y) * 37) & 0xFF)
                pixels[i + 3] = 255
            }
        }
        return context.makeImage()!
    }

    private static func decode(_ data: Data) throws -> CGImage {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    private static func properties(_ data: Data) -> [String: Any] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return [:] }
        return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] ?? [:]
    }

    private static func rgba8(_ image: CGImage) -> [UInt8] {
        let context = context(image.width, image.height)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Array(UnsafeBufferPointer(start: context.data!.assumingMemoryBound(to: UInt8.self),
                                         count: image.width * image.height * 4))
    }

    private static func rgba16(_ image: CGImage) -> [UInt16] {
        let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 16,
                                bytesPerRow: image.width * 8, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                                    | CGBitmapInfo.byteOrder16Little.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Array(UnsafeBufferPointer(start: context.data!.assumingMemoryBound(to: UInt16.self),
                                         count: image.width * image.height * 4))
    }
}
