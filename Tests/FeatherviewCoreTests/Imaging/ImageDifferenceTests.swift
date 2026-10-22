import CoreGraphics
import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct ImageDifferenceTests {
    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    /// A filled sRGB RGBA8 image.
    private func image(_ width: Int, _ height: Int, _ rgba: (Int, Int, Int, Int)) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: Self.sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: CGFloat(rgba.0) / 255, green: CGFloat(rgba.1) / 255,
                                     blue: CGFloat(rgba.2) / 255, alpha: CGFloat(rgba.3) / 255))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// RGB at (x, y), y from the top.
    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> (Int, Int, Int) {
        let data = image.dataProvider!.data! as Data
        let offset = y * image.bytesPerRow + x * 4
        return (Int(data[offset]), Int(data[offset + 1]), Int(data[offset + 2]))
    }

    @Test func identicalIsBlack() throws {
        let colour = (51, 102, 153, 255)
        let result = try ImageDifference.make(image(100, 100, colour), image(100, 100, colour), colorSpace: nil)
        for y in stride(from: 0, to: 100, by: 9) {
            for x in stride(from: 0, to: 100, by: 9) {
                #expect(pixel(result, x, y) == (0, 0, 0))
            }
        }
    }

    @Test func redAgainstHalfRed() throws {
        let result = try ImageDifference.make(image(100, 100, (255, 0, 0, 255)), image(100, 100, (128, 0, 0, 255)),
                                              colorSpace: nil)
        let (r, g, b) = pixel(result, 50, 50)
        #expect(abs(r - 127) <= 1 && g == 0 && b == 0)
    }

    @Test func smallerSecondIsScaled() throws {
        let result = try ImageDifference.make(image(100, 100, (255, 0, 0, 255)), image(50, 50, (128, 0, 0, 255)),
                                              colorSpace: nil)
        #expect(result.width == 100)
        let (r, g, b) = pixel(result, 50, 50)
        #expect(abs(r - 127) <= 1 && g == 0 && b == 0)
    }

    @Test func differentAspectShowsFirstOutside() throws {
        let white = (255, 255, 255, 255)
        let result = try ImageDifference.make(image(200, 100, white), image(100, 100, white), colorSpace: nil)
        #expect(pixel(result, 5, 50) == (255, 255, 255))
        #expect(pixel(result, 100, 50) == (0, 0, 0))
    }

    @Test func alphaFlattensOverBlack() throws {
        let result = try ImageDifference.make(image(10, 10, (0, 0, 0, 0)), image(10, 10, (0, 0, 0, 255)),
                                              colorSpace: nil)
        #expect(pixel(result, 5, 5) == (0, 0, 0))
    }

    @Test func greyAgainstRGB() throws {
        // Raw bytes: filling with a CGColor would colour-match 50 % to another byte value.
        let grey = CGImage(width: 10, height: 10, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: 10,
                           space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(),
                           provider: CGDataProvider(data: Data(repeating: 128, count: 100) as CFData)!,
                           decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let result = try ImageDifference.make(grey, image(10, 10, (128, 128, 128, 255)), colorSpace: nil)
        let (r, g, b) = pixel(result, 5, 5)
        #expect(r <= 2 && g <= 2 && b <= 2)
    }

    @Test func resultIsEightBitRGBA() throws {
        let result = try ImageDifference.make(image(30, 20, (10, 20, 30, 255)), image(60, 40, (40, 50, 60, 255)),
                                              colorSpace: nil)
        #expect(result.bitsPerComponent == 8)
        #expect(result.bitsPerPixel == 32)
        #expect(result.width == 30 && result.height == 20)
    }
}
