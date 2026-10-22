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

    /// Whether back (or forward) can act at `index` of `count` images: only Stop ends at the folder's ends;
    /// the chooser and Start Again act there too.
    public func canStep(forward: Bool, index: Int, count: Int) -> Bool {
        guard self == .stop else { return true }
        return forward ? index < count - 1 : index > 0
    }
}

/// Every setting from spec "Settings" with its default. The app binds them with
/// `@AppStorage(AppSettings.x.key)`; models read them with `AppSettings.x.value()`.
public enum AppSettings {
    // Browsing
    public static let pastEnd = Setting(key: "pastEnd", defaultValue: PastEndBehavior.folderChooser.rawValue)
    public static let showHiddenFiles = Setting(key: "showHiddenFiles", defaultValue: false)
    public static let showNextAfterRemoval = Setting(key: "showNextAfterRemoval", defaultValue: true)
    public static let moveSidecars = Setting(key: "moveSidecars", defaultValue: true)
    /// True once the launch offer to open images instead of Preview was shown (spec "Default viewer").
    public static let offeredDefaultViewer = Setting(key: "offeredDefaultViewer", defaultValue: false)
    // Viewer
    public static let appearance = Setting(key: "appearance", defaultValue: AppearanceMode.system.rawValue)
    public static let hideBarsWhileViewing = Setting(key: "hideBarsWhileViewing", defaultValue: false)
    public static let checkerboard = Setting(key: "checkerboard", defaultValue: true)
    public static let rememberWindowFrame = Setting(key: "rememberWindowFrame", defaultValue: true)
    public static let zoomStepPercent = Setting(key: "zoomStepPercent", defaultValue: 10)
    /// Where every new image starts: a `FitMode` raw value, set by Zoom to Fit / Width / Height.
    public static let fitMode = Setting(key: "fitMode", defaultValue: FitMode.fit.rawValue)
    /// View › Keep Zoom: a new image keeps the zoom and scroll position of the one before.
    public static let keepZoom = Setting(key: "keepZoom", defaultValue: false)
    // Full screen
    public static let showOverlay = Setting(key: "showOverlay", defaultValue: true)
    public static let overlayTemplate = Setting(key: "overlayTemplate", defaultValue: "{path} — {index} / {count}")
    public static let hidePointer = Setting(key: "hidePointer", defaultValue: true)
    // Move / copy
    public static let askBeforeMoveCopy = Setting(key: "askBeforeMoveCopy", defaultValue: false)
    // Open with: app paths for ⌥1, ⌥2, ⌥3 ("" = none)
    public static let openWith = (1...3).map { Setting(key: "openWith\($0)", defaultValue: "") }
    // Updates
    public static let checkForUpdates = Setting(key: "checkForUpdates", defaultValue: true)
    public static let lastUpdateCheck = Setting(key: "lastUpdateCheck", defaultValue: Date.distantPast)
    /// The version Skip This Version was clicked for ("" = none).
    public static let skippedVersion = Setting(key: "skippedVersion", defaultValue: "")

    public static var appearanceMode: AppearanceMode { AppearanceMode(stored: appearance.value()) }

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
            offeredDefaultViewer.key: offeredDefaultViewer.defaultValue,
            appearance.key: appearance.defaultValue,
            hideBarsWhileViewing.key: hideBarsWhileViewing.defaultValue,
            checkerboard.key: checkerboard.defaultValue,
            rememberWindowFrame.key: rememberWindowFrame.defaultValue,
            zoomStepPercent.key: zoomStepPercent.defaultValue,
            fitMode.key: fitMode.defaultValue,
            keepZoom.key: keepZoom.defaultValue,
            showOverlay.key: showOverlay.defaultValue,
            overlayTemplate.key: overlayTemplate.defaultValue,
            hidePointer.key: hidePointer.defaultValue,
            askBeforeMoveCopy.key: askBeforeMoveCopy.defaultValue,
            checkForUpdates.key: checkForUpdates.defaultValue,
            lastUpdateCheck.key: lastUpdateCheck.defaultValue,
            skippedVersion.key: skippedVersion.defaultValue,
        ]
        for setting in openWith { values[setting.key] = setting.defaultValue }
        defaults.register(defaults: values)
    }
}
