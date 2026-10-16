import CoreGraphics
import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct PDFPagesTests {
    /// Pages of `sizes` points; each a red square in the lower-left quarter on a transparent page.
    func pdf(_ sizes: [CGSize], rotate: Int = 0) throws -> URL {
        let url = try Fixtures.makeTempDir().appendingPathComponent("doc.pdf")
        let context = try #require(CGContext(url as CFURL, mediaBox: nil, nil))
        for size in sizes {
            var box = CGRect(origin: .zero, size: size)
            var info: [CFString: Any] = [kCGPDFContextMediaBox: Data(bytes: &box, count: MemoryLayout<CGRect>.size)]
            if rotate != 0 { info["Rotate" as CFString] = rotate }
            context.beginPDFPage(info as CFDictionary)
            context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: size.width / 2, height: size.height / 2))
            context.endPDFPage()
        }
        context.closePDF()
        return url
    }

    @Test func pagesAreListedAndSizedAt144dpi() throws {
        let url = try pdf([CGSize(width: 595, height: 842), CGSize(width: 200, height: 100)])
        #expect(ImageFormats.isDecodable(url) && ImageFormats.mayHavePages(url))
        #expect(ImageDecoder.pageCount(of: url) == 2)
        #expect(ImageDecoder.displaySize(of: url) == CGSize(width: 1190, height: 1684))
        #expect(ImageDecoder.displaySize(of: url, page: 1) == CGSize(width: 400, height: 200))
    }

    @Test func rendersOnWhiteAtTheSizeAsked() throws {
        let url = try pdf([CGSize(width: 200, height: 100)])
        let fit = try ImageDecoder.decode(url, maxPixelSize: 100, halvingSteps: true)
        #expect(fit.width == 100 && fit.height == 50)
        let full = try #require(RGBAImage(try ImageDecoder.decode(url)))
        #expect(full.width == 400)
        let red = full[0, 199]  // lower left: the red square (rows run top to bottom); colour-managed, so roughly red
        #expect(red.r > 200 && red.g < 60 && red.b < 60, "\(red)")
        #expect(full[399, 0] == (255, 255, 255, 255))  // elsewhere: white paper, not transparent
    }

    @Test func hugePagesRenderFullSizeWithinTheDecodeLimits() throws {
        // A poster: ×2 would be 20000 px a side, 400 MP, over the 256 MP limit; reported and rendered smaller instead.
        let poster = try pdf([CGSize(width: 10000, height: 10000)])
        #expect(ImageDecoder.displaySize(of: poster) == CGSize(width: 16384, height: 16384))
        // A banner: ×2 would be 80000 px wide, over 65,536 px a side.
        let banner = try pdf([CGSize(width: 40000, height: 10)])
        #expect(ImageDecoder.displaySize(of: banner) == CGSize(width: 65536, height: 16))
        let full = try ImageDecoder.decode(banner)
        #expect(full.width == 65536 && full.height == 16)
    }

    @Test func rotatedPagesTurnClockwise() throws {
        let url = try pdf([CGSize(width: 200, height: 100)], rotate: 90)
        #expect(ImageDecoder.displaySize(of: url) == CGSize(width: 200, height: 400))
        let image = try #require(RGBAImage(try ImageDecoder.decode(url)))
        let corner = image[0, 0]  // the page's lower-left square turns to the top left
        #expect(corner.r > 200 && corner.g < 60, "\(corner)")
        #expect(image[199, 399] == (255, 255, 255, 255))
    }

    @Test func pageBeyondTheLastIsUnreadable() throws {
        let url = try pdf([CGSize(width: 100, height: 100)])
        #expect(throws: DecodeError.unreadable(url)) { try ImageDecoder.decode(url, page: 1) }
    }

    @Test func notAPDFIsUnreadable() throws {
        let url = try Fixtures.writeCorrupt(to: Fixtures.makeTempDir().appendingPathComponent("bad.pdf"))
        #expect(ImageDecoder.displaySize(of: url) == nil)
        #expect(throws: DecodeError.unreadable(url)) { try ImageDecoder.decode(url) }
    }

    @Test func encryptedPDFIsUnreadable() throws {
        let url = try Fixtures.makeTempDir().appendingPathComponent("locked.pdf")
        var box = CGRect(x: 0, y: 0, width: 100, height: 100)
        let info: [CFString: Any] = [kCGPDFContextUserPassword: "secret", kCGPDFContextOwnerPassword: "owner"]
        let context = try #require(CGContext(url as CFURL, mediaBox: &box, info as CFDictionary))
        context.beginPDFPage(nil); context.endPDFPage(); context.closePDF()
        #expect(throws: DecodeError.unreadable(url)) { try ImageDecoder.decode(url) }
    }
}

/// Shared by PDF and SVG (in the app): a vector image too large for a bitmap renders smaller instead of failing.
@Suite struct VectorPixelSizeTests {
    @Test func twoPixelsPerPointWhenItFits() {
        let s = vectorPixelSize(CGSize(width: 9000, height: 6000), maxPixelSize: nil)
        #expect((s.width, s.height, s.scale) == (18000, 12000, 2))
    }

    @Test func hugeImageScalesDownToTheBitmapLimits() throws {
        for points in [CGSize(width: 40000, height: 100), CGSize(width: 30000, height: 30000)] {
            let s = vectorPixelSize(points, maxPixelSize: nil)
            #expect(s.scale < 2)
            _ = try checkedSize(s.width, s.height)
        }
    }

    @Test func maxPixelSizeCapsTheLongestSide() {
        let s = vectorPixelSize(CGSize(width: 9000, height: 6000), maxPixelSize: 3456)
        #expect((s.width, s.height) == (3456, 2304))
    }
}
