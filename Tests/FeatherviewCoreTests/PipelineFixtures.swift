import CoreGraphics
import CoreImage
import Foundation
@testable import FeatherviewCore

/// Images for the pipeline steps, built in code. Everything reasons in picture terms: row 0 is the top.
enum PipelineFixtures {
    static func solid(_ c: RGBAColor, width: Int, height: Int) -> CIImage {
        let color = CIColor(red: c.red, green: c.green, blue: c.blue, alpha: c.alpha,
                            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)!
        return CIImage(color: color).cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
    }

    /// Top-left red, top-right green, bottom-left blue, bottom-right white.
    static func quadrants(width: Int, height: Int) -> CIImage {
        var image = RGBAImage(width: width, height: height)
        for y in 0..<height {
            for x in 0..<width {
                let left = x < width / 2, top = y < height / 2
                image[x, y] = switch (top, left) {
                case (true, true): (255, 0, 0, 255)
                case (true, false): (0, 255, 0, 255)
                case (false, true): (0, 0, 255, 255)
                case (false, false): (255, 255, 255, 255)
                }
            }
        }
        return fromRGBA(image)
    }

    static func pixels(_ image: CIImage) throws -> RGBAImage {
        guard let rgba = RGBAImage(try PipelineRender.cgImage(image)) else { throw EncodeError.failed }
        return rgba
    }

    static func fromRGBA(_ image: RGBAImage) -> CIImage {
        CIImage(cgImage: image.makeCGImage()!)
    }
}
