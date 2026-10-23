import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import FeatherviewCore

@Suite struct OverlayStepsTests {
    let values = TextValues(name: "IMG_1", folder: "Trip", date: "2026-10-17", index: 7)

    // MARK: render

    @Test func renderPlaceholders() {
        #expect(TextStep.render("{name} in {folder} on {date} #{n}", values) == "IMG_1 in Trip on 2026-10-17 #7")
    }

    @Test func valuesFromAFile() {
        let url = URL(fileURLWithPath: "/p/Trip/IMG_1.jpg")
        let date = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 10, day: 17, hour: 12).date!
        #expect(TextValues(url: url, date: date, index: 7)
            == TextValues(name: "IMG_1", folder: "Trip", date: RenamePattern("{date}").baseName(original: "", index: 1, date: date), index: 7))
        #expect(TextValues(url: url, date: nil, index: 1) == TextValues(name: "IMG_1", folder: "Trip", date: "", index: 1))
    }

    @Test func renderKeepsUnknown() {
        #expect(TextStep.render("{foo} {name} {n:x}", values) == "{foo} IMG_1 {n:x}")
    }

    @Test func renderDoesNotReplaceTwice() {
        let v = TextValues(name: "{date}", folder: "{n}", date: "d", index: 1)
        #expect(TextStep.render("{name} {folder}", v) == "{date} {n}")
    }

    @Test func renderPadsCounter() {
        #expect(TextStep.render("{n:3}", values) == "007")
        #expect(TextStep.render("{n:1}", values) == "7")
        #expect(TextStep.render("{n:99999}", values).count == 10)
    }

    // MARK: text

    func text(_ string: String = "Hello", at position: ImageAnchor = .bottomRight) -> TextSettings {
        var s = TextSettings()
        s.isOn = true
        s.text = string
        s.position = position
        s.sizePercent = 10
        s.colour = .white
        return s
    }

    func black(_ w: Int = 400, _ h: Int = 300) -> CIImage { PipelineFixtures.solid(.black, width: w, height: h) }

    /// Picture-terms bounding box (row 0 = top) of pixels that differ by more than a rounding step.
    func changedBox(_ a: RGBAImage, _ b: RGBAImage) -> (minX: Int, minY: Int, maxX: Int, maxY: Int)? {
        var box: (minX: Int, minY: Int, maxX: Int, maxY: Int)?
        for y in 0..<a.height {
            for x in 0..<a.width {
                let p = a[x, y], q = b[x, y]
                let d = max(abs(Int(p.r) - Int(q.r)), abs(Int(p.g) - Int(q.g)), abs(Int(p.b) - Int(q.b)), abs(Int(p.a) - Int(q.a)))
                guard d > 2 else { continue }
                box = box.map { (min($0.minX, x), min($0.minY, y), max($0.maxX, x), max($0.maxY, y)) } ?? (x, y, x, y)
            }
        }
        return box
    }

    /// The text lands in its anchor's third of the picture and changes nothing on the far half.
    @Test(arguments: ImageAnchor.allCases)
    func textAtEachAnchorLandsInThatRegion(_ anchor: ImageAnchor) throws {
        let base = black()
        let out = TextStep.apply(base, text(at: anchor), values: values, scale: 1)
        #expect(out.extent == base.extent)
        let box = try #require(changedBox(try PipelineFixtures.pixels(base), try PipelineFixtures.pixels(out)))
        let column = (box.minX + box.maxX) / 2 / (400 / 3), row = (box.minY + box.maxY) / 2 / (300 / 3)
        let expected: (Int, Int) = switch anchor {
        case .topLeft: (0, 0)
        case .top: (1, 0)
        case .topRight: (2, 0)
        case .left: (0, 1)
        case .center: (1, 1)
        case .right: (2, 1)
        case .bottomLeft: (0, 2)
        case .bottom: (1, 2)
        case .bottomRight: (2, 2)
        }
        #expect(column == expected.0 && row == expected.1)
        if expected.0 == 0 { #expect(box.maxX < 200) }
        if expected.0 == 2 { #expect(box.minX >= 200) }
        if expected.1 == 0 { #expect(box.maxY < 150) }
        if expected.1 == 2 { #expect(box.minY >= 150) }
    }

    @Test func textOpacityZeroChangesNothing() throws {
        var s = text()
        s.opacity = 0
        s.backgroundBox = true
        s.boxColour = .white
        let base = black()
        #expect(try PipelineFixtures.pixels(TextStep.apply(base, s, values: values, scale: 1)) == PipelineFixtures.pixels(base))
    }

    @Test func textSizeFollowsShorterSide() throws {
        func height(_ w: Int, _ h: Int) throws -> Int {
            let base = black(w, h)
            let out = TextStep.apply(base, text("HELLO"), values: values, scale: 1)
            let box = try #require(changedBox(try PipelineFixtures.pixels(base), try PipelineFixtures.pixels(out)))
            return box.maxY - box.minY + 1
        }
        let small = try height(400, 300), big = try height(800, 600)
        #expect(small > 10)
        #expect(abs(Double(big) / Double(small) - 2) < 0.2)
    }

    @Test func stripBelowGrowsTheImage() throws {
        var s = text()
        s.placement = .stripBelow
        let base = PipelineFixtures.quadrants(width: 400, height: 300)
        let out = TextStep.apply(base, s, values: values, scale: 1)
        #expect(out.extent.origin == .zero && out.extent.width == 400 && out.extent.height > 300)
        let a = try PipelineFixtures.pixels(base), b = try PipelineFixtures.pixels(out)
        #expect(Array(b.pixels[0..<a.pixels.count]) == a.pixels)
        #expect(b[0, b.height - 1] == (0, 0, 0, 255))  // strip is black without a box
    }

    @Test func stripAboveShiftsTheImageDown() throws {
        var s = text()
        s.placement = .stripAbove
        s.backgroundBox = true
        s.boxColour = RGBAColor(red: 0, green: 0, blue: 1, alpha: 0.5)
        let base = PipelineFixtures.quadrants(width: 400, height: 300)
        let out = TextStep.apply(base, s, values: values, scale: 1)
        let a = try PipelineFixtures.pixels(base), b = try PipelineFixtures.pixels(out)
        #expect(b.height > 300)
        #expect(Array(b.pixels[(b.height - 300) * 400 * 4..<b.pixels.count]) == a.pixels)
        #expect(b[0, 0] == (0, 0, 255, 255))  // box colour, made opaque
    }

    @Test func emptyTextIsIdentity() throws {
        let base = PipelineFixtures.quadrants(width: 40, height: 30)
        #expect(TextStep.apply(base, text(""), values: values, scale: 1) === base)
        let noName = TextValues(name: "", folder: "", date: "", index: 1)
        var s = text("{name}")
        s.placement = .stripBelow
        #expect(TextStep.apply(base, s, values: noName, scale: 1) === base)
    }

    @Test func textOffIsIdentity() {
        var s = text()
        s.isOn = false
        let base = PipelineFixtures.quadrants(width: 40, height: 30)
        #expect(TextStep.apply(base, s, values: values, scale: 1) === base)
    }

    @Test(arguments: [TextPlacement.inImage, .stripBelow])
    func longTextWrapsInsideTheImage(_ placement: TextPlacement) throws {
        var s = text(String(repeating: "Wide words ", count: 8), at: .bottom)
        s.placement = placement
        let out = TextStep.apply(black(), s, values: values, scale: 1)
        let plain = black(Int(out.extent.width), Int(out.extent.height))  // the strip is black too
        let box = try #require(changedBox(try PipelineFixtures.pixels(plain), try PipelineFixtures.pixels(out)))
        #expect(box.minX >= 6 && box.maxX <= 399 - 6)  // margin 2 % of 300, so not cut at the edges
        #expect(box.maxY - box.minY > 60)  // 30 px font: wrapped onto several lines
    }

    @Test(arguments: [TextPlacement.stripBelow, .stripAbove])
    func stripGrowsWithEveryLineOnAShortImage(_ placement: TextPlacement) {
        func height(_ lines: Int) -> CGFloat {
            var s = text((1...lines).map { "L\($0)" }.joined(separator: "\n"))
            s.placement = placement
            s.sizePercent = 20
            s.shadow = false
            return TextStep.apply(black(400, 100), s, values: values, scale: 1).extent.height
        }
        let heights = (1...6).map(height)
        #expect(zip(heights, heights.dropFirst()).allSatisfy { $0 < $1 }, "\(heights)")
    }

    // MARK: watermark

    func mark(at position: ImageAnchor = .bottomRight, width: Double = 25, opacity: Double = 1) -> WatermarkSettings {
        var s = WatermarkSettings()
        s.isOn = true
        s.position = position
        s.widthPercent = width
        s.opacity = opacity
        s.marginPercent = 2
        return s
    }

    /// Solid red, 2:1.
    let red = PipelineFixtures.solid(RGBAColor(red: 1, green: 0, blue: 0), width: 100, height: 50)

    @Test func watermarkOffIsIdentity() {
        var s = mark()
        s.isOn = false
        let base = black()
        #expect(WatermarkStep.apply(base, watermark: red, s) === base)
    }

    @Test func watermarkAtBottomRight() throws {
        let base = black()
        let out = WatermarkStep.apply(base, watermark: red, mark())
        #expect(out.extent == base.extent)
        let box = try #require(changedBox(try PipelineFixtures.pixels(base), try PipelineFixtures.pixels(out)))
        #expect(box.minX >= 200 && box.minY >= 150)
        #expect(abs(box.maxX - (399 - 6)) <= 1 && abs(box.maxY - (299 - 6)) <= 1)  // margin 2 % of 300
    }

    @Test func watermarkWidthIsAShareOfTheImage() throws {
        let base = black()
        let out = WatermarkStep.apply(base, watermark: red, mark(at: .center))
        let box = try #require(changedBox(try PipelineFixtures.pixels(base), try PipelineFixtures.pixels(out)))
        #expect(abs(box.maxX - box.minX + 1 - 100) <= 1)
        #expect(abs(box.maxY - box.minY + 1 - 50) <= 1)
    }

    @Test func watermarkOpacity() throws {
        let out = try PipelineFixtures.pixels(WatermarkStep.apply(black(), watermark: red, mark(at: .center, opacity: 0.5)))
        let p = out[200, 150]
        #expect(abs(Int(p.r) - 128) <= 3 && p.g == 0 && p.b == 0 && p.a == 255)
    }

    @Test func missingWatermarkFileThrows() throws {
        #expect(throws: WatermarkError.unreadable("nope.png")) { try WatermarkStep.load("/no/such/folder/nope.png") }
        #expect(throws: WatermarkError.unreadable("")) { try WatermarkStep.load("") }
        let dir = try Fixtures.makeTempDir()
        let bad = try Fixtures.writeCorrupt(to: dir.appendingPathComponent("bad.png"))
        #expect(throws: WatermarkError.unreadable("bad.png")) { try WatermarkStep.load(bad.path) }
    }

    @Test func watermarkKeepsTransparency() throws {
        // 100 × 50 red with a transparent 20 × 10 hole in the middle.
        var rgba = RGBAImage(width: 100, height: 50)
        for y in 0..<50 { for x in 0..<100 { rgba[x, y] = (40..<60).contains(x) && (20..<30).contains(y) ? (0, 0, 0, 0) : (255, 0, 0, 255) } }
        let url = try Fixtures.makeTempDir().appendingPathComponent("hole.png")
        let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, try #require(rgba.makeCGImage()), nil)
        #expect(CGImageDestinationFinalize(dest))

        let watermark = try WatermarkStep.load(url.path)
        #expect(watermark.extent == CGRect(x: 0, y: 0, width: 100, height: 50))
        // Width 25 % of 400 = 100: no scaling, centred at (150…250, 125…175).
        let base = PipelineFixtures.solid(RGBAColor(red: 0, green: 1, blue: 0), width: 400, height: 300)
        let out = try PipelineFixtures.pixels(WatermarkStep.apply(base, watermark: watermark, mark(at: .center)))
        #expect(out[200, 150] == (0, 255, 0, 255))
        #expect(out[160, 135] == (255, 0, 0, 255))
    }
}
