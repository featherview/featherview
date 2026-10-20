import CoreGraphics
import CoreText
import Foundation

/// The disk image window's background: dark, a faint feather, an arrow from the app to Applications,
/// and the first-open help along the bottom. Drawn in points from the bottom-leading corner (Core Graphics).
public enum DiskImageArt {
    public static let size = CGSize(width: 920, height: 408)
    /// Icon centres in Finder's coordinates (points from the top-leading corner); `scripts/dmg.sh` uses the same.
    static let appSlot = CGPoint(x: 300, y: 170), applicationsSlot = CGPoint(x: 620, y: 170)
    /// Where Finder centres an icon's name at icon size 96, from the window's top (measured).
    static let labelCentreFromTop = 234

    public static func render(help: String, scale: Int, rightToLeft: Bool = false) -> CGImage {
        let scale = max(1, scale)
        let ctx = CGContext(data: nil, width: Int(size.width) * scale, height: Int(size.height) * scale,
                            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        background(ctx)
        feather(ctx)
        arrow(ctx)
        labelPlates(ctx)
        if !help.isEmpty { helpBox(ctx, help, rightToLeft: rightToLeft) }
        return ctx.makeImage()!
    }

    static func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255,
                blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
    }

    private static func background(_ ctx: CGContext) {
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                  colors: [rgb(0x2b2b36), rgb(0x0f0f13)] as CFArray, locations: [0, 1])!
        let centre = CGPoint(x: size.width / 2, y: size.height - 150)
        ctx.drawRadialGradient(gradient, startCenter: centre, startRadius: 0, endCenter: centre, endRadius: 620,
                               options: [.drawsAfterEndLocation])
    }

    /// A quill of thin lines in the bottom-trailing corner, above the help box.
    private static func feather(_ ctx: CGContext) {
        ctx.saveGState()
        ctx.setStrokeColor(rgb(0xffc766, 0.14))
        ctx.setLineWidth(1.25)
        ctx.setLineCap(.round)
        let start = CGPoint(x: 892, y: 100), control = CGPoint(x: 870, y: 190), end = CGPoint(x: 800, y: 262)
        ctx.move(to: start)
        ctx.addQuadCurve(to: end, control: control)
        // Barbs: from points along the shaft, swept back towards the quill's base, longest in the middle.
        for i in 3...18 {
            let t = CGFloat(i) / 20, u = 1 - t
            let p = CGPoint(x: u * u * start.x + 2 * u * t * control.x + t * t * end.x,
                            y: u * u * start.y + 2 * u * t * control.y + t * t * end.y)
            let length = 34 * sin(t * .pi)
            ctx.move(to: p)
            ctx.addLine(to: CGPoint(x: p.x - length * 0.9, y: p.y - length * 0.55))
            ctx.move(to: p)
            ctx.addLine(to: CGPoint(x: p.x + length * 0.55, y: p.y - length * 0.75))
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    /// Finder writes icon names in dark grey over a background picture, in light and dark mode alike, so
    /// each name sits on a light plate.
    private static func labelPlates(_ ctx: CGContext) {
        let y = size.height - CGFloat(labelCentreFromTop)
        ctx.setFillColor(rgb(0xe7e7ec, 0.92))
        for slot in [appSlot, applicationsSlot] {
            let plate = CGRect(x: slot.x - 56, y: y - 10, width: 112, height: 20)
            ctx.addPath(CGPath(roundedRect: plate, cornerWidth: 10, cornerHeight: 10, transform: nil))
            ctx.fillPath()
        }
    }

    private static func arrow(_ ctx: CGContext) {
        let y = size.height - appSlot.y, from = appSlot.x + 72, to = applicationsSlot.x - 72
        ctx.saveGState()
        ctx.setStrokeColor(rgb(0xffffff, 0.35))
        ctx.setLineWidth(3)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.move(to: CGPoint(x: from, y: y))
        ctx.addLine(to: CGPoint(x: to, y: y))
        ctx.move(to: CGPoint(x: to - 12, y: y + 12))
        ctx.addLine(to: CGPoint(x: to, y: y))
        ctx.addLine(to: CGPoint(x: to - 12, y: y - 12))
        ctx.strokePath()
        ctx.restoreGState()
    }

    static let helpMargin: CGFloat = 24, helpPad: CGFloat = 8
    /// Lines, not a height: Arabic, Hebrew, Thai and Devanagari lines are taller than Latin ones.
    static let maxHelpLines = 4
    static var helpWidth: CGFloat { size.width - 2 * helpMargin - 2 * helpPad }

    /// Whether all of `help` fits in the help box; `featherview-dmg` refuses a translation that doesn't.
    public static func helpFits(_ help: String, rightToLeft: Bool = false) -> Bool {
        let setter = CTFramesetterCreateWithAttributedString(attributed(help, rightToLeft: rightToLeft))
        return helpLines(setter).count <= maxHelpLines
    }

    /// The help laid out at the box's width with no height limit.
    private static func helpLines(_ setter: CTFramesetter) -> [CTLine] {
        let rect = CGRect(x: 0, y: 0, width: helpWidth, height: 10_000)
        let frame = CTFramesetterCreateFrame(setter, CFRange(), CGPath(rect: rect, transform: nil), nil)
        return CTFrameGetLines(frame) as! [CTLine]
    }

    private static func helpBox(_ ctx: CGContext, _ help: String, rightToLeft: Bool) {
        let margin = helpMargin, bottom: CGFloat = 10, pad = helpPad
        let textWidth = helpWidth
        let setter = CTFramesetterCreateWithAttributedString(attributed(help, rightToLeft: rightToLeft))
        // Longer help is cut after four lines (featherview-dmg refuses it before it gets here).
        let shown = helpLines(setter).prefix(maxHelpLines).reduce(0) { $0 + CTLineGetStringRange($1).length }
        let range = CFRange(location: 0, length: shown)
        let fitted = CTFramesetterSuggestFrameSizeWithConstraints(setter, range, nil,
                                                                  CGSize(width: textWidth, height: .greatestFiniteMagnitude), nil)
        let textHeight = fitted.height.rounded(.up)
        let box = CGRect(x: margin, y: bottom, width: size.width - 2 * margin, height: textHeight + 2 * pad)
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: box, cornerWidth: 10, cornerHeight: 10, transform: nil))
        ctx.setFillColor(rgb(0xffffff, 0.06))
        ctx.setStrokeColor(rgb(0xffffff, 0.12))
        ctx.setLineWidth(1)
        ctx.drawPath(using: .fillStroke)
        let textRect = CGRect(x: margin + pad, y: bottom + pad, width: textWidth, height: textHeight)
        let frame = CTFramesetterCreateFrame(setter, range, CGPath(rect: textRect, transform: nil), nil)
        CTFrameDraw(frame, ctx)
        ctx.restoreGState()
    }

    /// The help in `#c9c9d2`; a lead ending in a colon in the first sentence ("First open:") in bold `#ffd28f`.
    static func attributed(_ help: String, rightToLeft: Bool) -> CFAttributedString {
        let regular = CTFontCreateUIFontForLanguage(.system, 11, nil)!
        let bold = CTFontCreateUIFontForLanguage(.emphasizedSystem, 11, nil)!
        var alignment: CTTextAlignment = rightToLeft ? .right : .left
        var direction: CTWritingDirection = rightToLeft ? .rightToLeft : .leftToRight
        let paragraph = withUnsafeBytes(of: &alignment) { a in
            withUnsafeBytes(of: &direction) { d in
                let settings = [CTParagraphStyleSetting(spec: .alignment, valueSize: a.count, value: a.baseAddress!),
                                CTParagraphStyleSetting(spec: .baseWritingDirection, valueSize: d.count, value: d.baseAddress!)]
                return CTParagraphStyleCreate(settings, settings.count)
            }
        }
        let text = NSMutableAttributedString(string: help, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): regular,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): rgb(0xc9c9d2),
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraph,
        ])
        if let colon = help.firstIndex(where: { $0 == ":" || $0 == "：" }),
           !help[..<colon].contains(where: { ".。!?".contains($0) }) {
            let lead = NSRange(help.startIndex...colon, in: help)
            text.addAttributes([NSAttributedString.Key(kCTFontAttributeName as String): bold,
                                NSAttributedString.Key(kCTForegroundColorAttributeName as String): rgb(0xffd28f)], range: lead)
        }
        return text
    }
}
