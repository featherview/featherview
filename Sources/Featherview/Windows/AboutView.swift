import AppKit
import FeatherviewCore
import SwiftUI

/// The text About shows in a sheet (formats, licence, acknowledgements); Help's items set it, then open About.
@MainActor @Observable
final class AboutSheet {
    static let shared = AboutSheet()
    var text: String?
}

/// Spec "About window": icon, name, version, links, supported formats, licence and bug-report text.
struct AboutView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    private let sheet = AboutSheet.shared
    @State private var showingCopy = false

    private static let info = Bundle.main.infoDictionary ?? [:]
    static let version = info["CFBundleShortVersionString"] as? String ?? "?"
    static let build = info["CFBundleVersion"] as? String ?? "?"
    static let licenseURL = Bundle.main.url(forResource: "LICENSE", withExtension: nil)
    static let acknowledgementsURL = Bundle.main.url(forResource: "Acknowledgements", withExtension: "txt")
    /// The bug report form with this Mac's details filled in (About and Help › Report a Bug…).
    static var bugReportURL: URL {
        AboutInfo.bugReportURL(version: version, build: build, macOS: ProcessInfo.processInfo.operatingSystemVersionString,
                               model: AboutInfo.modelIdentifier())
    }
    static let macOSVersion: String = {
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
                    link("Website") { openURL(AboutInfo.website) }
                    LinkSeparator()
                    link("Source Code") { openURL(AboutInfo.repository) }
                }
                HStack(spacing: Theme.aboutLinkGap) {
                    link("Report a Problem") { openURL(Self.bugReportURL) }
                    LinkSeparator()
                    link("Supported Formats") { sheet.text = Self.formatsText }
                }
                if Self.licenseURL != nil || Self.acknowledgementsURL != nil {
                    HStack(spacing: Theme.aboutLinkGap) {
                        if let url = Self.licenseURL {
                            link("MIT License") { sheet.text = try? String(contentsOf: url, encoding: .utf8) }
                        }
                        if Self.licenseURL != nil, Self.acknowledgementsURL != nil { LinkSeparator() }
                        if let url = Self.acknowledgementsURL {
                            link("Acknowledgements") { sheet.text = try? String(contentsOf: url, encoding: .utf8) }
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
        .sheet(isPresented: Binding(get: { sheet.text != nil }, set: { if !$0 { sheet.text = nil } })) {
            VStack(alignment: .trailing) {
                ScrollView {
                    Text(Self.linked(sheet.text ?? ""))
                        .font(Font(Theme.aboutTextFont))
                        .textSelection(.enabled)
                        .frame(width: Theme.aboutTextWidth, alignment: .leading)
                        .padding([.horizontal, .top])  // inside the scroll view: its scroller sits in the margin
                }
                Button { sheet.text = nil } label: { Text("Done").foregroundStyle(Theme.onAccent) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .padding([.horizontal, .bottom])
            }
            .frame(height: Theme.aboutTextHeight)
        }
    }

    /// The sheet's text with its web addresses clickable.
    private static func linked(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        for match in detector?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? [] {
            guard let url = match.url, let range = Range(match.range, in: text),
                  let linkRange = Range(range, in: result) else { continue }
            result[linkRange].link = url
        }
        return result
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
    static var formatsText: String {
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
