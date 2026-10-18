import AppKit
import SwiftUI

/// The feather from Resources/Feather.svg (the app icon's mark without its tile). Only the empty window,
/// "Use Featherview for Images" and About show it.
struct FeatherMark: View {
    let size: Double

    private static let image = Bundle.main.url(forResource: "Feather", withExtension: "svg").flatMap(NSImage.init(contentsOf:))

    var body: some View {
        if let image = Self.image {
            Image(nsImage: image).resizable().frame(width: size, height: size).accessibilityHidden(true)
        }
    }
}
