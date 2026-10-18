// Writes the disk image background for one language. Used by scripts/dmg.sh.
// Usage: featherview-dmg --app <Featherview.app> --lang <code> --out <dir>
import FeatherviewCore
import Foundation
import ImageIO
import UniformTypeIdentifiers

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

var options: [String: String] = [:]
var args = CommandLine.arguments.dropFirst().makeIterator()
while let flag = args.next() {
    guard ["--app", "--lang", "--out"].contains(flag), let value = args.next() else {
        fail("Usage: featherview-dmg --app <Featherview.app> --lang <code> --out <dir>")
    }
    options[String(flag.dropFirst(2))] = value
}
guard let app = options["app"], let lang = options["lang"], let out = options["out"] else {
    fail("Usage: featherview-dmg --app <Featherview.app> --lang <code> --out <dir>")
}

// A missing or unreadable table means English.
let table = URL(fileURLWithPath: app).appending(path: "Contents/Resources/\(lang).lproj/Localizable.strings")
let strings = (try? Data(contentsOf: table))
    .flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: String] } ?? [:]
let help = DiskImageText.firstOpenHelp(from: strings)
let rightToLeft = DiskImageText.helpIsRightToLeft(language: lang, strings: strings)
guard DiskImageArt.helpFits(help, rightToLeft: rightToLeft) else {
    fail("The \(lang) first-open help is longer than four lines. Shorten the translation.")
}

let outDir = URL(fileURLWithPath: out)
do { try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true) } catch {
    fail("Can't create \(out)")
}
for (name, scale) in [("background.png", 1), ("background@2x.png", 2)] {
    let url = outDir.appending(path: name)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fail("Can't write \(url.path)")
    }
    // 72 dpi per point, so tiffutil pairs the two as 1x and 2x.
    let dpi = 72 * scale
    CGImageDestinationAddImage(dest, DiskImageArt.render(help: help, scale: scale, rightToLeft: rightToLeft),
                               [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi] as CFDictionary)
    guard CGImageDestinationFinalize(dest) else { fail("Can't write \(url.path)") }
}
