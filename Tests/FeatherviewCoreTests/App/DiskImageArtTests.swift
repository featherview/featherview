import CoreGraphics
import Testing
@testable import FeatherviewCore

@Suite struct DiskImageArtTests {
    func pixels(_ image: CGImage) throws -> RGBAImage { try #require(RGBAImage(image)) }

    @Test func renderHasTheSize() {
        let image = DiskImageArt.render(help: "x", scale: 2)
        #expect(image.width == 1840)
        #expect(image.height == 816)
    }

    @Test func renderIsDark() throws {
        let image = try pixels(DiskImageArt.render(help: DiskImageText.firstOpenHelp, scale: 1))
        var sum = 0.0
        for y in 0..<image.height / 2 {
            for x in 0..<image.width {
                let p = image[x, y]
                sum += (0.2126 * Double(p.r) + 0.7152 * Double(p.g) + 0.0722 * Double(p.b)) / 255
            }
        }
        #expect(sum / Double(image.width * image.height / 2) < 0.2)
    }

    /// Finder writes the icon names in dark grey over a background picture, in light and dark mode alike,
    /// so each name sits on a light plate.
    @Test func iconNamesSitOnLightPlates() throws {
        let image = try pixels(DiskImageArt.render(help: "", scale: 1))
        for x in [300, 620] {
            let p = image[x, DiskImageArt.labelCentreFromTop]
            #expect((0.2126 * Double(p.r) + 0.7152 * Double(p.g) + 0.0722 * Double(p.b)) / 255 > 0.8)
        }
    }

    @Test(arguments: [false, true])
    func helpTextAppears(rightToLeft: Bool) throws {
        let empty = try pixels(DiskImageArt.render(help: "", scale: 1, rightToLeft: rightToLeft))
        let help = try pixels(DiskImageArt.render(help: DiskImageText.firstOpenHelp, scale: 1, rightToLeft: rightToLeft))
        let bottomFifth = empty.height * 4 / 5
        var changedAbove = 0, changedBelow = 0
        for y in 0..<empty.height {
            for x in 0..<empty.width where empty[x, y] != help[x, y] {
                if y < bottomFifth { changedAbove += 1 } else { changedBelow += 1 }
            }
        }
        #expect(changedAbove == 0)
        #expect(changedBelow > 0)
    }

    @Test func missingTranslationFallsBackToEnglish() {
        let english = DiskImageText.firstOpenHelp
        #expect(DiskImageText.firstOpenHelp(from: [:]) == english)
        #expect(DiskImageText.firstOpenHelp(from: [english: "Erstes Öffnen …"]) == "Erstes Öffnen …")
    }

    @Test func englishFallbackStaysLeftToRight() {
        let english = DiskImageText.firstOpenHelp
        #expect(!DiskImageText.helpIsRightToLeft(language: "he", strings: [:]))
        #expect(!DiskImageText.helpIsRightToLeft(language: "ar", strings: ["other": "x"]))
        #expect(DiskImageText.helpIsRightToLeft(language: "ar", strings: [english: "افتح"]))
        #expect(!DiskImageText.helpIsRightToLeft(language: "de", strings: [english: "Erstes Öffnen …"]))
    }

    @Test(arguments: [false, true])
    func helpBoxHoldsFourLines(rightToLeft: Bool) {
        #expect(DiskImageArt.helpFits(DiskImageText.firstOpenHelp, rightToLeft: rightToLeft))
        #expect(DiskImageArt.helpFits("a\nb\nc\nd", rightToLeft: rightToLeft))
        #expect(!DiskImageArt.helpFits("a\nb\nc\nd\ne", rightToLeft: rightToLeft))
    }

    /// Arabic, Hebrew, Thai and Devanagari lines are taller than Latin ones: four still fit, five don't.
    @Test(arguments: [("افتح", true), ("פתח", true), ("ไทย", false), ("खोलें", false)])
    func helpBoxHoldsFourLinesInTallScripts(word: String, rightToLeft: Bool) {
        let lines = { (n: Int) in Array(repeating: word, count: n).joined(separator: "\n") }
        #expect(DiskImageArt.helpFits(lines(4), rightToLeft: rightToLeft))
        #expect(!DiskImageArt.helpFits(lines(5), rightToLeft: rightToLeft))
    }
}
