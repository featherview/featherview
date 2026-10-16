import AppKit
import FeatherviewCore
import SwiftUI

/// Spec "About window": icon, name, version, links, supported formats, licence and bug-report text.
struct AboutView: View {
    @Environment(\.openURL) private var openURL
    @State private var sheetText: String?

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
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("Featherview").font(.title.bold())
            Text(verbatim: "\(Self.version) (\(Self.build))")
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text("A fast, keyboard-driven image viewer with batch conversion")
                .multilineTextAlignment(.center)
            HStack {
                Button("Website") { openURL(URL(string: "https://featherview.github.io")!) }
                Button("Source Code") { openURL(URL(string: "https://github.com/mynetx/featherview")!) }
                Button("Report a Problem") { openURL(URL(string: "https://github.com/mynetx/featherview/issues/new")!) }
            }
            DisclosureGroup("Supported Formats") { formats }
            HStack {
                if let url = Self.licenseURL {
                    Button("MIT License") { sheetText = try? String(contentsOf: url, encoding: .utf8) }
                }
                if let url = Self.acknowledgementsURL {
                    Button("Acknowledgements") { sheetText = try? String(contentsOf: url, encoding: .utf8) }
                }
                Button("Copy") {
                    let text = AboutInfo.reportText(version: Self.version, build: Self.build,
                                                    macOS: ProcessInfo.processInfo.operatingSystemVersionString,
                                                    model: AboutInfo.modelIdentifier())
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
            }
            Text(verbatim: "© 2026 Joachim Rütter").font(.caption).foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 420)
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
