import Foundation

/// Where Set as Desktop Picture puts the image on each screen.
public enum DesktopPlacement: CaseIterable, Sendable {
    case fill, fit, stretch, center

    /// `NSImageScaling`'s raw value for `NSWorkspace`'s `.imageScaling` (Core doesn't import AppKit).
    public var scalingRawValue: UInt {
        switch self {
        case .fill, .fit: 3      // scaleProportionallyUpOrDown
        case .stretch: 1         // scaleAxesIndependently
        case .center: 2          // scaleNone
        }
    }

    /// Fill crops the overhang; the others show the whole image.
    public var allowsClipping: Bool { self == .fill }
}
