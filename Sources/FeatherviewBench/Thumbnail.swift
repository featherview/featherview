import Foundation
import ImageIO
import QuickLookThumbnailing
import UniformTypeIdentifiers

/// `thumbnail`: Finder's thumbnail for each file (or each file in a folder), through the system service.
func runThumbnail(_ path: URL, out: URL?) async {
    let isFolder = (try? path.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    let files = isFolder
        ? ((try? FileManager.default.contentsOfDirectory(at: path, includingPropertiesForKeys: nil)) ?? [])
            .filter { !$0.lastPathComponent.hasPrefix(".") }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        : [path]
    var missing = 0
    for file in files {
        let request = QLThumbnailGenerator.Request(fileAt: file, size: CGSize(width: 256, height: 256), scale: 2,
                                                   representationTypes: .thumbnail)
        let start = ContinuousClock.now
        do {
            let representation = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
            let image = representation.cgImage
            print("\(file.lastPathComponent): thumbnail \(image.width)x\(image.height) \(Int((.now - start).milliseconds)) ms")
            if let out, let destination = CGImageDestinationCreateWithURL(
                out.appending(path: file.lastPathComponent + ".png") as CFURL, UTType.png.identifier as CFString, 1, nil) {
                CGImageDestinationAddImage(destination, image, nil)
                CGImageDestinationFinalize(destination)
            }
        } catch {
            print("\(file.lastPathComponent): no thumbnail (\(error.localizedDescription))")
            missing += 1
        }
    }
    if missing > 0 { exit(1) }
}
