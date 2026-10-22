import Foundation

/// The texts of compare mode that the app builds outside SwiftUI literals.
public enum CompareText {
    /// The window title while comparing.
    public static func title(first: String, second: String) -> String {
        String(localized: "\(first) and \(second)", comment: "Window title while comparing two images")
    }

    /// The open panel's message when choosing the second image.
    public static func choose(_ name: String) -> String {
        String(localized: "Choose an image to compare with \(name)", comment: "Open panel message for Compare With…")
    }

    /// The second pane's strip while it shows the difference.
    public static var difference: String {
        String(localized: "Difference", comment: "Status strip of the second pane while it shows the difference")
    }
}
