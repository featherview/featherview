import CoreGraphics
import Foundation

/// PDFs shown like multi-page images (spec "Formats"), rendered by Core Graphics.
enum PDFPages {
    /// 144 dpi: a page's points × 2, sharp on Retina at 100 %.
    static let pixelsPerPoint = 2.0

    static let format = OwnFormat(
        name: "PDF", extensions: ["pdf"], hasPages: true,
        size: { data, page in pageBox(data, page).map { let s = pixelSize($0, maxPixelSize: nil)
                                                        return CGSize(width: s.width, height: s.height) } },
        pageCount: { data in document(data)?.numberOfPages ?? 0 },
        decode: { data, page, maxPixelSize in try render(data, page: page, maxPixelSize: maxPixelSize) })

    static func document(_ data: Data) -> CGPDFDocument? {
        CGDataProvider(data: data as CFData).flatMap(CGPDFDocument.init)
    }

    /// The page's visible size in points, its rotation applied; nil past the last page.
    static func pageBox(_ data: Data, _ page: Int) -> CGSize? {
        guard let pdfPage = document(data)?.page(at: page + 1) else { return nil }  // Core Graphics counts from 1
        let box = pdfPage.getBoxRect(.cropBox)
        return pdfPage.rotationAngle % 180 == 0 ? box.size : CGSize(width: box.height, height: box.width)
    }

    /// The bitmap size for a page of `points`: 2 px per point, at most `maxPixelSize` a side, and always within
    /// `checkedSize`'s limits, since a vector page renders at any scale instead of failing.
    static func pixelSize(_ points: CGSize, maxPixelSize: Int?) -> (width: Int, height: Int, scale: Double) {
        let scale = min(pixelsPerPoint, Double(maxPixelSize ?? 1 << 16) / max(points.width, points.height),
                        (Double(maxOwnPixels) / (points.width * points.height)).squareRoot())
        func pixels(_ rule: FloatingPointRoundingRule) -> (Int, Int) {
            (max(1, Int((points.width * scale).rounded(rule))), max(1, Int((points.height * scale).rounded(rule))))
        }
        var (width, height) = pixels(.toNearestOrAwayFromZero)
        if width * height > maxOwnPixels { (width, height) = pixels(.down) }  // rounding up overshot the pixel cap
        return (width, height, scale)
    }

    /// Renders straight at the size asked for, so fit mode never scales a bitmap.
    static func render(_ data: Data, page: Int, maxPixelSize: Int?) throws -> CGImage {
        guard let document = document(data) else { throw OwnDecodeError.corrupt }
        // shortcut: no password prompt, a locked PDF shows "Can't open"; add one if people ask.
        if document.isEncrypted && !document.isUnlocked { throw OwnDecodeError.unsupported }
        guard let pdfPage = document.page(at: page + 1), let points = pageBox(data, page),
              points.width >= 1, points.height >= 1 else { throw OwnDecodeError.corrupt }
        let (width, height, scale) = pixelSize(points, maxPixelSize: maxPixelSize)
        _ = try checkedSize(width, height)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw OwnDecodeError.corrupt }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))  // pages are paper: white, not transparent
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        // Not getDrawingTransform: it never scales a page up.
        let box = pdfPage.getBoxRect(.cropBox)
        context.scaleBy(x: scale, y: scale)
        switch (pdfPage.rotationAngle % 360 + 360) % 360 {  // the page's /Rotate, clockwise
        case 90: context.translateBy(x: 0, y: box.width); context.rotate(by: -.pi / 2)
        case 180: context.translateBy(x: box.width, y: box.height); context.rotate(by: .pi)
        case 270: context.translateBy(x: box.height, y: 0); context.rotate(by: .pi / 2)
        default: break
        }
        context.translateBy(x: -box.minX, y: -box.minY)
        context.clip(to: box)
        context.drawPDFPage(pdfPage)
        guard let image = context.makeImage() else { throw OwnDecodeError.corrupt }
        return image
    }
}
