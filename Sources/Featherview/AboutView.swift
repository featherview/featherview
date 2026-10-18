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
            // The app icon's 824 pt tile on its 1024 pt grid, drawn so the tile is 128 pt.
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: Theme.aboutIconSize, height: Theme.aboutIconSize)
                .elevation(.e4)
                .frame(width: Theme.aboutTileSize, height: Theme.aboutTileSize)
                .background { glow }
            Text("Featherview")
                .font(Theme.aboutName)
                .foregroundStyle(Theme.labelTitle)
                .padding(.top, Theme.aboutNameGap)
            Text("A fast, keyboard-driven image viewer with batch conversion")
                .font(Theme.aboutTagline)
                .foregroundStyle(Theme.labelSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Theme.aboutTaglineGap)
            HStack(spacing: Theme.keyCapGap) {
                Text("Version").foregroundStyle(Theme.labelTertiary)
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
                Theme.separator.frame(height: 1)
                Text(verbatim: Self.info["NSHumanReadableCopyright"] as? String ?? "© Joachim Rütter")
                    .foregroundStyle(Theme.labelTertiary)
                HStack(spacing: Theme.aboutLinkGap) {
                    link("Website") { openURL(URL(string: "https://featherview.github.io")!) }
                    FooterSeparator()
                    link("Source Code") { openURL(URL(string: "https://github.com/mynetx/featherview")!) }
                    FooterSeparator()
                    link("Report a Problem") { openURL(URL(string: "https://github.com/mynetx/featherview/issues/new")!) }
                }
                HStack(spacing: Theme.aboutLinkGap) {
                    if let url = Self.licenseURL {
                        link("MIT License") { sheetText = try? String(contentsOf: url, encoding: .utf8) }
                    }
                    if Self.licenseURL != nil, Self.acknowledgementsURL != nil { FooterSeparator() }
                    if let url = Self.acknowledgementsURL {
                        link("Acknowledgements") { sheetText = try? String(contentsOf: url, encoding: .utf8) }
                    }
                }
                DisclosureGroup("Supported Formats") { formats }
            }
            .font(Theme.aboutSmall)
            .padding(.top, Theme.aboutFooterTop)
        }
        .padding(Theme.aboutPadding)
        .frame(width: Theme.aboutWidth)
        // Esc closes the window, wherever the focus is (a hidden button's shortcut doesn't need focus).
        .background { Button("Close") { dismiss() }.keyboardShortcut(.cancelAction).opacity(0) }
        .background(WindowAccessor { window in
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

    /// The one place the feather colours fill an area: a soft radial glow behind the icon.
    private var glow: some View {
        RadialGradient(stops: [.init(color: Theme.aboutGlowStart, location: 0),
                               .init(color: Theme.aboutGlowMid, location: 0.42),
                               .init(color: .clear, location: 0.70)],
                       center: .center, startRadius: 0, endRadius: Theme.aboutGlowSize / 2)
            .frame(width: Theme.aboutGlowSize, height: Theme.aboutGlowSize)
            .offset(y: Theme.aboutGlowOffset)
            .allowsHitTesting(false)
    }

    /// An accent link.
    private func link(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.link)
            .foregroundStyle(Theme.accent)
    }

    private var formats: some View {
        let read = FormatRegistry.readableNames
        return VStack(alignment: .leading, spacing: 8) {
            Text("Read").font(.headline)
            Text("macOS \(Self.macOSVersion): \(read.macOS.joined(separator: ", "))")
            Text("Featherview: \(read.own.joined(separator: ", "))")
            Text("Write").font(.headline)
            Text(FormatRegistry.writable.map(\.name).joined(separator: ", "))
        }
        .font(.callout)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }
}
