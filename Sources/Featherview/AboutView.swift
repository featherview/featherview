import AppKit
import FeatherviewCore
import SwiftUI

/// Spec "About window": icon, name, version, links, supported formats, licence and bug-report text.
struct AboutView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @State private var sheetText: String?
    @State private var showingCopy = false

    private static let info = Bundle.main.infoDictionary ?? [:]
    private static let version = info["CFBundleShortVersionString"] as? String ?? "?"
    private static let build = info["CFBundleVersion"] as? String ?? "?"
    private static let licenseURL = Bundle.main.url(forResource: "LICENSE", withExtension: nil)
    private static let acknowledgementsURL = Bundle.main.url(forResource: "Acknowledgements", withExtension: "txt")
    private static let macOSVersion: String = {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return v.patchVersion == 0 ? "\(v.majorVersion).\(v.minorVersion)" : "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }()

    var body: some View {
        VStack(spacing: 0) {
            tile
            Text("Featherview")
                .font(Theme.aboutName)
                .foregroundStyle(Theme.aboutNameColour)
                .padding(.top, Theme.aboutNameGap)
            Text("Fast, keyboard-driven image viewer")
                .font(Theme.aboutTagline)
                .foregroundStyle(Theme.labelSecondary)
                .padding(.top, Theme.aboutTaglineGap)
            HStack(spacing: Theme.keyCapGap) {
                Text("Version").foregroundStyle(Theme.aboutCaption)
                // Like a value in iOS settings: click it, and a "Copy" bubble offers the details for a bug report.
                Button { showingCopy = true } label: {
                    Text(verbatim: "\(Self.version) (\(Self.build))")
                        .font(Theme.aboutVersion)
                        .foregroundStyle(Theme.keyCapText)
                        .padding(Theme.aboutVersionPadding)
                        .background(Theme.keyCapFill, in: .rect(cornerRadius: Theme.Radius.keyCap))
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.keyCap).strokeBorder(Theme.keyCapLine, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("Click to copy the version, macOS version and Mac model")
                .popover(isPresented: $showingCopy, arrowEdge: .bottom) {
                    Button("Copy") {
                        let text = AboutInfo.reportText(version: Self.version, build: Self.build,
                                                        macOS: ProcessInfo.processInfo.operatingSystemVersionString,
                                                        model: AboutInfo.modelIdentifier())
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                        showingCopy = false
                    }
                    .buttonStyle(.borderless)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
            }
            .font(Theme.aboutSmall)
            .padding(.top, Theme.aboutVersionGap)
            VStack(spacing: Theme.aboutFooterGap) {
                Theme.aboutHairline.frame(height: 1)
                Text(verbatim: Self.info["NSHumanReadableCopyright"] as? String ?? "© Joachim Rütter")
                    .foregroundStyle(Theme.aboutCaption)
                // Two to a row, centred, so none wraps at 320 pt.
                HStack(spacing: Theme.aboutLinkGap) {
                    link("Website") { openURL(URL(string: "https://featherview.github.io")!) }
                    LinkSeparator()
                    link("Source Code") { openURL(URL(string: "https://github.com/mynetx/featherview")!) }
                }
                HStack(spacing: Theme.aboutLinkGap) {
                    link("Report a Problem") { openURL(URL(string: "https://github.com/mynetx/featherview/issues/new")!) }
                    LinkSeparator()
                    link("Supported Formats") { sheetText = Self.formatsText }
                }
                if Self.licenseURL != nil || Self.acknowledgementsURL != nil {
                    HStack(spacing: Theme.aboutLinkGap) {
                        if let url = Self.licenseURL {
                            link("MIT License") { sheetText = try? String(contentsOf: url, encoding: .utf8) }
                        }
                        if Self.licenseURL != nil, Self.acknowledgementsURL != nil { LinkSeparator() }
                        if let url = Self.acknowledgementsURL {
                            link("Acknowledgements") { sheetText = try? String(contentsOf: url, encoding: .utf8) }
                        }
                    }
                }
            }
            .font(Theme.aboutSmall)
            .padding(.top, Theme.aboutFooterTop)
        }
        .padding(Theme.aboutPadding)
        .frame(width: Theme.aboutWidth)
        .background { glow }
        .background(Theme.aboutBackground)
        // Esc closes the window, wherever the focus is (a hidden button's shortcut doesn't need focus).
        .background { Button("Close") { dismiss() }.keyboardShortcut(.cancelAction).opacity(0) }
        .background(WindowAccessor { window in
            // A relaunch never brings About back, as in other Mac apps.
            window.isRestorable = false
            // Close button only (docs/DESIGN.md "About").
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
        })
        .sheet(isPresented: Binding(get: { sheetText != nil }, set: { if !$0 { sheetText = nil } })) {
            VStack(alignment: .trailing) {
                ScrollView {
                    Text(sheetText ?? "")
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button("Done") { sheetText = nil }.keyboardShortcut(.defaultAction)
            }
            .padding()
            .frame(width: 520, height: 420)
        }
    }

    /// The app icon as the design draws it: the tile gradient with the feather, 128 pt, E4.
    private var tile: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.aboutTile, style: .continuous)
            .fill(Theme.aboutTile)
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.aboutTile, style: .continuous)
                    .subtracting(RoundedRectangle(cornerRadius: Theme.Radius.aboutTile, style: .continuous).offset(y: 1))
                    .fill(Theme.aboutTileHighlight)
            }
            .elevation(.e4)
            .overlay(alignment: .topLeading) {
                // Feather.svg spans 8…54 of the icon's 64-unit grid.
                FeatherMark(size: Theme.aboutTileSize * 46 / 64)
                    .offset(x: Theme.aboutTileSize * 8 / 64, y: Theme.aboutTileSize * 8 / 64)
            }
            .frame(width: Theme.aboutTileSize, height: Theme.aboutTileSize)
    }

    /// The one place the feather colours fill an area: a soft radial glow behind the icon.
    private var glow: some View {
        // CSS's default radial size reaches the box's corner: radius √2 × half the box.
        RadialGradient(stops: [.init(color: Theme.aboutGlowStart, location: 0),
                               .init(color: Theme.aboutGlowMid, location: 0.42),
                               .init(color: .clear, location: 0.70)],
                       center: .center, startRadius: 0, endRadius: Theme.aboutGlowSize / 2 * 2.squareRoot())
            .frame(width: Theme.aboutGlowSize, height: Theme.aboutGlowSize)
            .frame(maxHeight: .infinity, alignment: .top)
            .offset(y: Theme.aboutGlowTop)
            .allowsHitTesting(false)
    }

    /// The formats Featherview reads and writes, for the text sheet.
    private static var formatsText: String {
        let read = FormatRegistry.readableNames
        return [String(localized: "Read"),
                String(localized: "macOS \(macOSVersion): \(read.macOS.formatted(.list(type: .and, width: .narrow)))"),
                String(localized: "Featherview: \(read.own.formatted(.list(type: .and, width: .narrow)))"),
                "",
                String(localized: "Write"),
                FormatRegistry.writable.map(\.name).formatted(.list(type: .and, width: .narrow))].joined(separator: "\n")
    }

    /// An accent link.
    private func link(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.link)
            .fixedSize()
            .foregroundStyle(Theme.accent)
    }
}

/// The 1 × 10 line between links.
private struct LinkSeparator: View {
    var body: some View { Theme.stripSeparator.frame(width: 1, height: Theme.footerSeparatorHeight) }
}
