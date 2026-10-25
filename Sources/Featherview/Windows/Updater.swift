import FeatherviewCore
import Sparkle

/// Spec "Updates": Sparkle checks the appcast, shows its update window, downloads, verifies and installs.
@MainActor
enum Updater {
    private static let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil,
                                                                 userDriverDelegate: nil)
    private static var started = false

    /// Sparkle starts 10 s after launch, so it costs launch nothing; its schedule then checks at most once a day.
    static func startLater() {
        Task {
            try? await Task.sleep(for: .seconds(10))
            start()
        }
    }

    /// Check for Updates…: at once, and always answers.
    static func check() {
        start()
        controller.checkForUpdates(nil)
    }

    /// Settings › "Check for updates automatically" (our key, so a choice made in 0.10 carries over).
    static func automaticChecks(_ on: Bool) {
        controller.updater.automaticallyChecksForUpdates = on
    }

    private static func start() {
        guard !started else { return }
        started = true
        automaticChecks(AppSettings.checkForUpdates.value())
        controller.startUpdater()
    }
}
