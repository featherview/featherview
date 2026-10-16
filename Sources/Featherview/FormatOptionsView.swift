import FeatherviewCore
import SwiftUI

/// One format's options (spec "Format options"), shared by Save As, the batch window and
/// Settings › Formats. Rows for a `Form`. It never stores `options`: the owner decides when.
struct FormatOptionsView: View {
    let format: OutputFormat
    @Binding var options: FormatOptions

    @State private var profiles: [(name: String, options: FormatOptions)] = []
    @State private var namingProfile = false
    @State private var profileName = ""

    var body: some View {
        if format.optionFields.isEmpty {
            Text("No options for \(format.name)")
                .foregroundStyle(.secondary)
        }
        ForEach(format.optionFields, id: \.self) { field in
            row(field)
        }
        profilesMenu
            .onAppear(perform: reloadProfiles)
            .onChange(of: format) { reloadProfiles() }
            .sheet(isPresented: $namingProfile) { nameSheet }
    }

    @ViewBuilder private func row(_ field: FormatOption) -> some View {
        switch field {
        case .quality:
            LabeledContent("Quality:") {
                Slider(value: Binding { Double(options.quality) } set: { options.quality = Int($0.rounded()) },
                       in: 1...100)
                Text("\(options.quality)")
                    .monospacedDigit()
                    .frame(minWidth: 28, alignment: .trailing)
            }
            .disabled(options.lossless)
        case .lossless:
            Toggle("Lossless", isOn: $options.lossless)
        case .progressive:
            Toggle("Progressive", isOn: $options.progressive)
        case .keepMetadata:
            Toggle("Keep camera data, location and keywords", isOn: $options.keepMetadata)
        case .targetSize:
            LabeledContent {
                TextField("KB", value: Binding { options.targetSizeKB ?? 500 } set: { options.targetSizeKB = min(max(1, $0), 1_000_000) },
                          format: .number)
                    .labelsHidden()
                    .frame(width: 80)
                    .disabled(options.targetSizeKB == nil)
                Text("KB")
            } label: {
                Toggle("Target file size:", isOn: Binding { options.targetSizeKB != nil } set: {
                    options.targetSizeKB = $0 ? 500 : nil
                })
            }
        case .interlaced:
            Toggle("Interlaced", isOn: $options.interlaced)
        case .tiffCompression:
            Picker("Compression:", selection: $options.tiffCompression) {
                Text("None").tag(TIFFCompression.none)
                Text("LZW").tag(TIFFCompression.lzw)
                Text("PackBits").tag(TIFFCompression.packBits)
                Text("JPEG").tag(TIFFCompression.jpeg)
                Text("ZIP").tag(TIFFCompression.zip)
            }
        case .keepAllPages:
            Toggle("Keep all pages", isOn: $options.keepAllPages)
        }
    }

    private var profilesMenu: some View {
        Menu("Profiles") {
            ForEach(profiles, id: \.name) { profile in
                Button(profile.name) { options = profile.options }
            }
            if !profiles.isEmpty { Divider() }
            Button("Save as Profile…") {
                profileName = ""
                namingProfile = true
            }
            Menu("Delete Profile") {
                ForEach(profiles, id: \.name) { profile in
                    Button(profile.name) {
                        FormatSettings.deleteProfile(profile.name, for: format)
                        reloadProfiles()
                    }
                }
            }
            .disabled(profiles.isEmpty)
        }
        .fixedSize()
    }

    private var nameSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Profile name", text: $profileName)
                .frame(width: 240)
                .onSubmit(saveProfile)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { namingProfile = false }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: saveProfile)
                    .keyboardShortcut(.defaultAction)
                    .disabled(profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
    }

    private func saveProfile() {
        FormatSettings.saveProfile(profileName, options, for: format)
        namingProfile = false
        reloadProfiles()
    }

    private func reloadProfiles() { profiles = FormatSettings.profiles(for: format) }
}
