import AppKit
import FeatherviewCore
import SwiftUI

/// Spec "Updates": checks the appcast and tells about a newer version; the user downloads it by hand.
@MainActor
enum Updater {
    private static var controller: NSWindowController?
    private static var checking = false

    /// The automatic check, 10 s after launch, when the preference is on and the last check is a day old.
    static func scheduleAutomaticCheck() {
        Task {
            try? await Task.sleep(for: .seconds(10))
            guard UpdateCheck.isDue(enabled: AppSettings.checkForUpdates.value(), lastCheck: AppSettings.lastUpdateCheck.value(),
                                    now: .now) else { return }
            await check(manual: false)
        }
    }

    /// A manual check ignores the schedule and the skipped version and always answers; the automatic one speaks only for an update.
    static func check(manual: Bool) async {
        guard !checking else { return }
        checking = true
        defer { checking = false }
        let current = AboutView.version
        let releases = await Task.detached { () -> [Release]? in
            guard let (data, response) = try? await UpdateCheck.session().data(for: UpdateCheck.request(appVersion: current)),
                  (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return UpdateCheck.releases(from: data)
        }.value
        guard let releases else {
            if manual { alert(String(localized: "Can't check for updates right now.")) }
            return
        }
        UserDefaults.standard.set(Date.now, forKey: AppSettings.lastUpdateCheck.key)
        let skipped = AppSettings.skippedVersion.value()
        if let release = UpdateCheck.update(in: releases, current: current, macOS: AboutView.macOSVersion,
                                            skipped: manual || skipped.isEmpty ? nil : skipped) {
            show(release)
        } else if manual {
            alert(String(localized: "Featherview \(current) is the newest version."))
        }
    }

    private static func alert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
    }

    private static func show(_ release: Release) {
        controller?.close()
        let host = NSHostingController(rootView: UpdateView(release: release) { controller?.close() })
        host.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: host)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = String(localized: "Featherview \(release.version) is available")
        window.isRestorable = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.center()
        controller = NSWindowController(window: window)
        controller?.showWindow(nil)
    }
}

/// The update notice: what's new, then Download, Skip This Version or Later.
private struct UpdateView: View {
    let release: Release
    let close: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Theme.panelGap) {
            FeatherMark(size: Theme.featherSize)
            VStack(alignment: .leading, spacing: Theme.panelGap) {
                VStack(alignment: .leading, spacing: Theme.titleGap) {
                    Text("Featherview \(release.version) is available")
                        .font(Theme.panelTitle)
                        .foregroundStyle(Theme.labelTitle)
                    Text("You have \(AboutView.version).")
                        .foregroundStyle(Theme.labelSecondary)
                }
                if !release.notes.isEmpty {
                    ScrollView {
                        Text(release.notes)
                            .textSelection(.enabled)
                            .foregroundStyle(Theme.labelPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Theme.rowPadding)
                            // The notes are English: left to right even in a right-to-left language.
                            .environment(\.layoutDirection, .leftToRight)
                    }
                    .frame(height: Theme.updateNotesHeight)
                    .background(Theme.cardFill, in: .rect(cornerRadius: Theme.Radius.group))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.group).strokeBorder(Theme.cardLine, lineWidth: 1))
                }
                HStack {
                    Button("Skip This Version") {
                        UserDefaults.standard.set(release.version, forKey: AppSettings.skippedVersion.key)
                        close()
                    }
                    Spacer()
                    Button("Later", action: close).keyboardShortcut(.cancelAction)
                    // The label's own colour: a prominent button ignores one set on the button.
                    Button {
                        NSWorkspace.shared.open(release.download ?? release.link)
                        close()
                    } label: {
                        Text("Download").foregroundStyle(Theme.onAccent)
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(Theme.updatePadding)
        .frame(width: Theme.updateWidth)
        .background(Theme.aboutBackground)
    }
}
