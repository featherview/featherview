import Foundation

/// One setting: its UserDefaults key and the default the spec gives it.
public struct Setting<Value: Sendable>: Sendable {
    public let key: String
    public let defaultValue: Value

    /// The stored value, or the default when nothing (or something of another type) is stored.
    public func value(in defaults: UserDefaults = .standard) -> Value {
        defaults.object(forKey: key) as? Value ?? defaultValue
    }
}

/// What → does past the last image (and ← before the first).
public enum PastEndBehavior: String, CaseIterable, Sendable {
    case folderChooser, loop, stop
}

/// Every setting from spec "Settings" with its default. The app binds them with
/// `@AppStorage(AppSettings.x.key)`; models read them with `AppSettings.x.value()`.
public enum AppSettings {
    // Browsing
    public static let pastEnd = Setting(key: "pastEnd", defaultValue: PastEndBehavior.folderChooser.rawValue)
    public static let showHiddenFiles = Setting(key: "showHiddenFiles", defaultValue: false)
    public static let showNextAfterRemoval = Setting(key: "showNextAfterRemoval", defaultValue: true)
    public static let moveSidecars = Setting(key: "moveSidecars", defaultValue: true)
    // Viewer
    public static let backgroundColor = Setting(key: "backgroundColor", defaultValue: "#000000")
    public static let checkerboard = Setting(key: "checkerboard", defaultValue: true)
    public static let rememberWindowFrame = Setting(key: "rememberWindowFrame", defaultValue: true)
    public static let zoomStepPercent = Setting(key: "zoomStepPercent", defaultValue: 10)
    // Full screen
    public static let showOverlay = Setting(key: "showOverlay", defaultValue: false)
    public static let overlayTemplate = Setting(key: "overlayTemplate", defaultValue: "{name} — {index} / {count}")
    public static let hidePointer = Setting(key: "hidePointer", defaultValue: true)
    // Move / copy
    public static let askBeforeMoveCopy = Setting(key: "askBeforeMoveCopy", defaultValue: false)
    // Open with: app paths for ⌥1, ⌥2, ⌥3 ("" = none)
    public static let openWith = (1...3).map { Setting(key: "openWith\($0)", defaultValue: "") }

    public static var pastEndBehavior: PastEndBehavior {
        PastEndBehavior(rawValue: pastEnd.value()) ?? .folderChooser
    }

    /// Registers every default, so `UserDefaults.bool(forKey:)` and friends agree with the spec.
    public static func registerDefaults(in defaults: UserDefaults = .standard) {
        var values: [String: Any] = [
            pastEnd.key: pastEnd.defaultValue,
            showHiddenFiles.key: showHiddenFiles.defaultValue,
            showNextAfterRemoval.key: showNextAfterRemoval.defaultValue,
            moveSidecars.key: moveSidecars.defaultValue,
            backgroundColor.key: backgroundColor.defaultValue,
            checkerboard.key: checkerboard.defaultValue,
            rememberWindowFrame.key: rememberWindowFrame.defaultValue,
            zoomStepPercent.key: zoomStepPercent.defaultValue,
            showOverlay.key: showOverlay.defaultValue,
            overlayTemplate.key: overlayTemplate.defaultValue,
            hidePointer.key: hidePointer.defaultValue,
            askBeforeMoveCopy.key: askBeforeMoveCopy.defaultValue,
        ]
        for setting in openWith { values[setting.key] = setting.defaultValue }
        defaults.register(defaults: values)
    }
}

/// `#RRGGBB` colours, the form the background colour setting is stored in.
public enum HexColor {
    /// Components 0...1, or nil if `hex` isn't `#RRGGBB`.
    public static func parse(_ hex: String) -> (red: Double, green: Double, blue: Double)? {
        guard hex.count == 7, hex.first == "#", let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        return (Double(value >> 16 & 0xFF) / 255, Double(value >> 8 & 0xFF) / 255, Double(value & 0xFF) / 255)
    }

    public static func format(red: Double, green: Double, blue: Double) -> String {
        func byte(_ c: Double) -> Int { Int((min(max(c, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }
}
