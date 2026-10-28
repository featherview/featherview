import AppKit
import FeatherviewCore
import SwiftUI

/// The info panel (I), design B2-1b-2: header with place, histogram, then the groups Camera, Image, Location,
/// Description and File, and "Show all metadata…" (spec "Info panel"; docs/DESIGN.md "Info panel").
/// Everything is read off the main thread; each result lands only while its file is still the panel's.
struct InfoPanel: View {
    let url: URL?
    /// Changes when the file is rewritten (rotation), so everything is read again.
    let revision: Int
    /// The picture on screen, its file and page, and its fit-size decode, which the histogram is counted from.
    let image: CGImage?
    let onScreen: (url: URL, page: Int)?
    let fitImage: CGImage?
    /// A fit-size decode of the picture on screen while zoomed into one never shown at fit.
    let decodeFit: () async -> CGImage?
    /// The viewer's focus for the panel's controls.
    var focus: FocusState<InfoFocus?>.Binding
    /// The panel's controls in Tab order, for Tab from the picture.
    @Binding var stops: [InfoFocus]
    /// Gives the keyboard back to the picture (Esc, Tab past either end).
    let leave: () -> Void

    private struct ReadKey: Hashable { var url: URL; var revision: Int }
    private struct PlaceKey: Hashable { var read: ReadKey; var latitude: Double; var longitude: Double }
    private struct HistogramKey: Hashable { var read: ReadKey; var page: Int; var fit: ObjectIdentifier?; var headroom: Double? }

    @State private var readInfo: ImageInfo?
    @State private var infoKey: ReadKey?
    /// The place name and the file and coordinate it was looked up for: shown only while they are the panel's.
    @State private var placeName: PlaceName?
    @State private var placeFor: PlaceKey?
    @State private var counted: Histogram?
    @State private var countedFor: HistogramKey?
    private let state = InfoPanelState.shared
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// ⇧Tab arrives as backtab on the Mac.
    static let backtab = KeyEquivalent("\u{19}")

    private var strong: Bool { contrast == .increased || differentiateWithoutColor }
    private var secondary: Color { strong ? Theme.labelPrimary : Theme.labelSecondary }
    private var hairline: CGFloat { strong ? Theme.hairlineContrast : 1 }
    private var readKey: ReadKey? { url.map { ReadKey(url: $0, revision: revision) } }
    /// The file's info, never the last file's while this one's is read.
    private var info: ImageInfo? { infoKey != nil && infoKey == readKey ? readInfo : nil }
    /// Set once the picture on screen and the info are both the file's.
    private var histogramKey: HistogramKey? {
        guard let key = readKey, let info, image != nil, let onScreen, onScreen.url == key.url else { return nil }
        return HistogramKey(read: key, page: onScreen.page, fit: fitImage.map(ObjectIdentifier.init), headroom: info.picture.headroom)
    }
    private var histogram: Histogram? { countedFor != nil && countedFor == histogramKey ? counted : nil }
    private var placeKey: PlaceKey? {
        guard let key = infoKey, let gps = info?.gps else { return nil }
        return PlaceKey(read: key, latitude: gps.latitude, longitude: gps.longitude)
    }
    private var place: PlaceName? { placeFor != nil && placeFor == placeKey ? placeName : nil }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.infoGap) {
                    header
                    if image != nil {
                        HistogramView(histogram: histogram, focus: focus, secondary: secondary, hairline: hairline)
                    }
                    if let info {
                        ForEach(groups(info), id: \.self) { card($0, info) }
                    }
                    Button { AllMetadataWindow.show() } label: {
                        SmallButtonLabel(glyph: "list.bullet.rectangle", title: Text("Show all metadata…", comment: "Info panel button"))
                    }
                    .buttonStyle(.plain)
                    .infoControl(.showAll, focus: focus, radius: Theme.Radius.slotKey) { AllMetadataWindow.show() }
                }
                .padding(Theme.panelPadding)
            }
            .scrollIndicators(.automatic)
            .onChange(of: focus.wrappedValue) { _, focused in
                guard let focused else { return }
                withAnimation(Theme.Motion.moving(Theme.Motion.panel, reduceMotion: reduceMotion)) { proxy.scrollTo(focused) }
            }
        }
        .frame(width: Theme.infoPanelWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .glass(.panel, cornerRadius: Theme.Radius.panel)
        .textSelection(.enabled)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Info", comment: "Info panel, VoiceOver"))
        .onKeyPress(keys: [.tab, Self.backtab]) { press in
            moveFocus(back: press.key == Self.backtab || press.modifiers.contains(.shift))
        }
        .onKeyPress(.escape) {
            guard focus.wrappedValue != nil else { return .ignored }
            leave()
            return .handled
        }
        .onChange(of: focusOrder, initial: true) { stops = $1 }
        // A control that went away with the image (a group the next file hasn't) hands the focus to the first one,
        // never to nothing.
        .onChange(of: focus.wrappedValue) { old, new in
            if new == nil, let old, !focusOrder.contains(old), let first = focusOrder.first { focus.wrappedValue = first }
        }
        .task(id: readKey) {
            guard let key = readKey else { readInfo = nil; infoKey = nil; return }
            let read = await Task.detached(priority: .userInitiated) { ImageInfo.read(key.url) }.value
            // A newer file or revision cancelled this read: its result never lands.
            guard !Task.isCancelled else { return }
            readInfo = read
            infoKey = key
        }
        .task(id: placeKey) {
            guard let key = placeKey else { return }
            let name = await PlaceIndex.shared.name(latitude: key.latitude, longitude: key.longitude)
            guard !Task.isCancelled, key == placeKey else { return }
            placeName = name
            placeFor = key
        }
        .task(id: histogramKey) {
            guard let key = histogramKey else { return }
            var picture = fitImage
            if picture == nil { picture = await decodeFit() }
            guard let picture, let histogram = await Histogram.counted(picture, headroom: key.headroom),
                  !Task.isCancelled else { return }
            counted = histogram
            countedFor = key
        }
    }

    // MARK: Header

    private var header: some View {
        let name = url?.lastPathComponent ?? ""
        return VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: name)
                .font(Theme.panelHeader)
                .foregroundStyle(Theme.labelTitle)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(name)
            if let info {
                Text(verbatim: Self.isolated(info.formatLine)).font(Theme.infoCaption).foregroundStyle(secondary)
            }
            if let place {
                HStack(alignment: .firstTextBaseline, spacing: Theme.infoSmallGap) {
                    Image(systemName: "mappin").foregroundStyle(Theme.accent).accessibilityHidden(true)
                    Text(verbatim: place.short).lineLimit(2)
                }
                .font(Theme.infoCaption)
                .foregroundStyle(Theme.labelPrimary)
                .padding(.top, 3)
            }
        }
        .padding(.horizontal, Theme.infoHeaderPadding)
    }

    // MARK: Groups

    private func groups(_ info: ImageInfo) -> [InfoGroup] {
        let e = info.exposure, p = info.picture, d = info.description
        return InfoGroup.allCases.filter { group in
            switch group {
            case .camera:
                [info.camera, info.lens, info.taken, e.shutter, e.aperture, e.iso, e.focal, e.focal35, e.bias, e.flash,
                 e.whiteBalance, e.metering].contains { $0 != nil }
            case .image: [p.dimensions, p.profile, p.bitDepth, p.hdr, p.software].contains { $0 != nil }
            case .location: info.gps != nil
            case .description:
                [d.title, d.caption, d.creator, d.copyright, d.comment].contains { $0 != nil } || !d.keywords.isEmpty || d.rating != nil
            case .file: true
            }
        }
    }

    private func title(_ group: InfoGroup) -> Text {
        switch group {
        case .camera: Text("Camera", comment: "Info panel group")
        case .image: Text("Image", comment: "Info panel group")
        case .location: Text("Location", comment: "Info panel group")
        case .description: Text("Description", comment: "Info panel group")
        case .file: Text("File", comment: "Info panel group")
        }
    }

    private func glyph(_ group: InfoGroup) -> String {
        switch group {
        case .camera: "camera"
        case .image: "photo"
        case .location: "mappin.and.ellipse"
        case .description: "text.alignleft"
        case .file: "doc"
        }
    }

    /// The one-line summary of a closed group.
    private func summary(_ group: InfoGroup, _ info: ImageInfo) -> String {
        switch group {
        case .camera: info.camera ?? ""
        case .image: info.picture.summary ?? ""
        case .location: info.gps?.altitude.map(InfoText.altitude) ?? ""
        case .description: info.description.rating.map(InfoText.stars) ?? ""
        case .file: info.modified ?? ""
        }
    }

    private func card(_ group: InfoGroup, _ info: ImageInfo) -> some View {
        let open = state.open.contains(group)
        return VStack(alignment: .leading, spacing: 0) {
            groupHeader(group, info, open: open)
            if open { content(group, info) }
        }
        .background(Theme.cardFill, in: .rect(cornerRadius: Theme.Radius.group))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.group).strokeBorder(Theme.cardLine, lineWidth: hairline))
    }

    private func toggle(_ group: InfoGroup) {
        withAnimation(Theme.Motion.moving(Theme.Motion.panel, reduceMotion: reduceMotion)) {
            state.open.formSymmetricDifference([group])
        }
    }

    private func groupHeader(_ group: InfoGroup, _ info: ImageInfo, open: Bool) -> some View {
        let summary = open ? "" : summary(group, info)
        return Button { toggle(group) } label: {
            HStack(spacing: Theme.infoGroupHeaderGap) {
                Image(systemName: glyph(group)).foregroundStyle(Theme.accent)
                title(group).font(Theme.infoGroupTitle).foregroundStyle(Theme.labelTitle).lineLimit(1).layoutPriority(1)
                Text(verbatim: Self.isolated(summary))
                    .font(Theme.infoRowValue)
                    .foregroundStyle(secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Image(systemName: open ? "chevron.down" : "chevron.forward")
                    .font(Theme.infoTileUnit.weight(.semibold))
                    .foregroundStyle(secondary)
            }
            .font(Theme.infoRow)
            .frame(minHeight: Theme.infoGroupHeaderHeight)
            .padding(.horizontal, Theme.rowPadding)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .infoControl(.header(group), focus: focus, radius: Theme.Radius.group) { toggle(group) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title(group))
        .accessibilityValue(open ? String(localized: "expanded", comment: "Info panel group state, VoiceOver")
                            : summary.isEmpty ? String(localized: "collapsed", comment: "Info panel group state, VoiceOver")
                            : String(localized: "collapsed, \(summary)", comment: "Info panel group state and its summary, VoiceOver"))
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder private func content(_ group: InfoGroup, _ info: ImageInfo) -> some View {
        switch group {
        case .camera:
            exposure(info.exposure)
            row("Lens", info.lens)
            row("35 mm equivalent", info.exposure.focal35)
            row("Taken", info.taken)
        case .image:
            let p = info.picture
            row("Dimensions", p.dimensions.map(Self.isolated))
            row("Colour profile", p.profile)
            row("Bit depth", p.bitDepth)
            row("HDR", p.hdr)
            row("Software", p.software)
        case .location:
            if let gps = info.gps {
                if let place {
                    Text(verbatim: place.full)
                        .font(Theme.infoPlace)
                        .foregroundStyle(Theme.labelPrimary)
                        .lineLimit(2)
                        .padding(.horizontal, Theme.rowPadding)
                        .padding(.bottom, 9)
                }
                row("Latitude", Self.isolated(InfoText.latitude(gps.latitude)))
                row("Longitude", Self.isolated(InfoText.longitude(gps.longitude)))
                row("Altitude", gps.altitude.map { Self.isolated(InfoText.altitude($0)) })
                buttonRow(.location, glyph: "map", title: Text("Open in Maps", comment: "Info panel button")) { openInMaps(gps) }
            }
        case .description:
            let d = info.description
            row("Title", d.title, wraps: true)
            row("Caption", d.caption, wraps: true)
            row("Keywords", d.keywords.isEmpty ? nil : d.keywords.joined(separator: ", ") + (d.moreKeywords ? ", …" : ""), wraps: true)
            row("Rating", d.rating.map(InfoText.stars))
            row("Creator", d.creator, wraps: true)
            row("Copyright", d.copyright, wraps: true)
            row("Comment", d.comment, wraps: true)
        case .file:
            row("Folder", info.folder)
            row("Modified", info.modified)
            row("Created", info.created)
            if let url {
                buttonRow(.file, glyph: "folder", title: Text("Show in Finder", comment: "Info panel button")) {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
        }
    }

    private var separator: some View {
        Theme.rowSeparator.frame(height: hairline)
    }

    /// Label secondary, value primary; a missing value leaves the row out. Long text (captions, keywords) wraps.
    @ViewBuilder private func row(_ label: LocalizedStringKey, _ value: String?, wraps: Bool = false) -> some View {
        if let value {
            VStack(spacing: 0) {
                separator
                HStack(alignment: wraps ? .firstTextBaseline : .center, spacing: Theme.panelGap) {
                    Text(label).font(Theme.infoRow).foregroundStyle(secondary).lineLimit(1)
                    Spacer(minLength: 0)
                    Text(verbatim: value)
                        .font(Theme.infoRowValue)
                        .foregroundStyle(Theme.labelPrimary)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(wraps ? nil : 1)
                        .truncationMode(.middle)
                        .help(wraps ? "" : value)
                }
                .padding(.vertical, wraps ? 9 : 0)
                .frame(minHeight: Theme.infoRowHeightCompact)
                .padding(.horizontal, Theme.rowPadding)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func buttonRow(_ group: InfoGroup, glyph: String, title: Text, action: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            separator
            HStack {
                Spacer(minLength: 0)
                Button(action: action) { SmallButtonLabel(glyph: glyph, title: title) }
                    .buttonStyle(.plain)
                    .infoControl(.button(group), focus: focus, radius: Theme.Radius.slotKey, action: action)
            }
            .frame(minHeight: Theme.infoRowHeightCompact)
            .padding(.horizontal, Theme.rowPadding)
        }
    }

    // MARK: Camera's tiles and chips

    @ViewBuilder private func exposure(_ e: ImageInfo.Exposure) -> some View {
        let tiles = [
            e.shutter.map { v in Tile(value: v, glyph: "timer", unit: Text("sec", comment: "Info panel tile unit: seconds"),
                                      spoken: v.contains("/") ? String(localized: "Shutter speed \(v) second", comment: "Info panel, VoiceOver")
                                          : String(localized: "Shutter speed \(v) seconds", comment: "Info panel, VoiceOver")) },
            e.aperture.map { v in Tile(value: v, unit: Text("ƒ stop", comment: "Info panel tile unit: aperture"),
                                       spoken: String(localized: "Aperture f/\(v)", comment: "Info panel, VoiceOver")) },
            e.iso.map { v in Tile(value: v, unit: Text("ISO speed", comment: "Info panel tile unit"),
                                  spoken: String(localized: "ISO \(v)", comment: "Info panel, VoiceOver")) },
            e.focal.map { v in Tile(value: v, glyph: "circle.circle", unit: Text("mm", comment: "Info panel tile unit: millimetres"),
                                    spoken: e.focal35.map { String(localized: "Focal length \(v) millimetres, \($0) equivalent", comment: "Info panel, VoiceOver") }
                                        ?? String(localized: "Focal length \(v) millimetres", comment: "Info panel, VoiceOver"),
                                    tooltip: e.focal35.map { String(localized: "\($0) equivalent", comment: "Info panel focal length tooltip: 53 mm equivalent") }) },
        ].compactMap { $0 }
        let chips = [
            e.bias.map { ("plusminus", $0, String(localized: "Exposure bias \($0)", comment: "Info panel, VoiceOver")) },
            e.flash.map { ("bolt", $0, $0) },
            e.whiteBalance.map { ("sun.max", $0, String(localized: "White balance \($0)", comment: "Info panel, VoiceOver")) },
            e.metering.map { ("camera.metering.matrix", $0, String(localized: "Metering \($0)", comment: "Info panel, VoiceOver")) },
        ].compactMap { $0 }
        if !tiles.isEmpty || !chips.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if !tiles.isEmpty {
                    HStack(spacing: Theme.tileGap) {
                        ForEach(tiles, id: \.spoken) { tile in
                            VStack(spacing: 1) {
                                Text(verbatim: tile.value)
                                    .font(Theme.infoTile)
                                    .foregroundStyle(Theme.labelPrimary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                    .environment(\.layoutDirection, .leftToRight)
                                HStack(spacing: 3) {
                                    if let glyph = tile.glyph { Image(systemName: glyph).foregroundStyle(Theme.accent) }
                                    tile.unit.lineLimit(1)
                                }
                                .font(Theme.infoTileUnit)
                                .foregroundStyle(secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(Theme.tilePadding)
                            .background(Theme.tileFill, in: .rect(cornerRadius: Theme.Radius.tile))
                            .help(tile.tooltip ?? "")
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(tile.spoken)
                        }
                    }
                }
                if !chips.isEmpty {
                    FlowLayout(spacing: Theme.chipGap) {
                        ForEach(chips, id: \.0) { glyph, text, spoken in
                            HStack(spacing: Theme.infoSmallGap) {
                                Image(systemName: glyph).foregroundStyle(Theme.accent)
                                Text(verbatim: text)
                            }
                            .font(Theme.infoChip)
                            .foregroundStyle(Theme.labelPrimary)
                            .padding(Theme.chipPadding)
                            .background(Theme.chipFill, in: .capsule)
                            .overlay(Capsule().strokeBorder(Theme.chipLine, lineWidth: hairline))
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(spoken)
                        }
                    }
                }
            }
            .padding(Theme.exposurePadding)
        }
    }

    /// An exposure tile: the bare number big, a glyph and unit under it, read by VoiceOver as one phrase.
    private struct Tile {
        var value: String
        var glyph: String?
        var unit: Text
        var spoken: String
        var tooltip: String?
    }

    // MARK: Actions and keyboard

    /// Hands the coordinate to Maps; nothing loads before the click.
    private func openInMaps(_ gps: ImageInfo.GPS) {
        let ll = String(format: "%.6f,%.6f", gps.latitude, gps.longitude)
        var components = URLComponents()
        components.scheme = "maps"
        components.host = ""
        components.queryItems = [URLQueryItem(name: "ll", value: ll), URLQueryItem(name: "q", value: place?.short ?? ll)]
        if let link = components.url { NSWorkspace.shared.open(link) }
    }

    /// The panel's controls in Tab order: mode, clip marks, then each group's header and, when open, its button,
    /// then "Show all metadata…".
    private var focusOrder: [InfoFocus] {
        var order: [InfoFocus] = image == nil ? [] : [.mode, .shadowsClip, .highlightsClip]
        for group in info.map(groups) ?? [] {
            order.append(.header(group))
            let hasButton = group == .file ? url != nil : group == .location
            if hasButton, state.open.contains(group) { order.append(.button(group)) }
        }
        order.append(.showAll)
        return order
    }

    private func moveFocus(back: Bool) -> KeyPress.Result {
        let order = focusOrder
        guard let current = focus.wrappedValue, let index = order.firstIndex(of: current) else { return .ignored }
        let next = back ? index - 1 : index + 1
        if order.indices.contains(next) { focus.wrappedValue = order[next] } else { leave() }
        return .handled
    }

    /// Keeps numbers and coordinates left to right inside right-to-left text (first strong isolate).
    static func isolated(_ text: String) -> String { "\u{2068}\(text)\u{2069}" }
}

/// The Small button with a glyph: 22 tall, key-cap fill, 0.12 hairline.
private struct SmallButtonLabel: View {
    let glyph: String
    let title: Text

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: glyph)
            title
        }
        .font(Theme.smallButton)
        .foregroundStyle(Theme.labelPrimary)
        .padding(.horizontal, Theme.smallButtonPadding)
        .frame(height: Theme.smallButtonHeight)
        .background(Theme.keyCapFill, in: .rect(cornerRadius: Theme.Radius.slotKey))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.slotKey).strokeBorder(Theme.badgeLine, lineWidth: 1))
        .contentShape(.rect)
    }
}

extension View {
    /// A keyboard stop in the info panel: focusable whatever System Settings' keyboard navigation says, the accent
    /// ring (2 pt, 1 pt outside the shape) while focused, Space and Return act. Other keys go on to the viewer.
    func infoControl(_ id: InfoFocus, focus: FocusState<InfoFocus?>.Binding, radius: CGFloat,
                     action: @escaping () -> Void) -> some View {
        modifier(InfoControl(id: id, focus: focus, radius: radius, action: action))
    }
}

private struct InfoControl: ViewModifier {
    let id: InfoFocus
    var focus: FocusState<InfoFocus?>.Binding
    let radius: CGFloat
    let action: () -> Void

    func body(content: Content) -> some View {
        let reach = Theme.focusRingOutset + Theme.focusRingWidth
        content
            .focusable()
            .focusEffectDisabled()
            .focused(focus, equals: id)
            .onKeyPress(keys: [.space, .return]) { press in
                guard press.modifiers.intersection([.command, .control, .option, .shift]).isEmpty else { return .ignored }
                action()
                return .handled
            }
            .overlay {
                if focus.wrappedValue == id {
                    RoundedRectangle(cornerRadius: radius + reach)
                        .strokeBorder(Theme.focusRing, lineWidth: Theme.focusRingWidth)
                        .padding(-reach)
                        .allowsHitTesting(false)
                }
            }
            .id(id)
    }
}

/// Lays chips out in rows, wrapping to the next row when one doesn't fit (leading-aligned).
private struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews)
        return CGSize(width: rows.map(\.width).max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews) {
            var x = bounds.minX
            for index in row.items {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row { var items: [Int] = []; var width: CGFloat = 0; var y: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, _ subviews: Subviews) -> [Row] {
        var rows = [Row()]
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if !rows[rows.count - 1].items.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
            }
            let gap = rows[rows.count - 1].items.isEmpty ? 0 : spacing
            rows[rows.count - 1].items.append(index)
            rows[rows.count - 1].width += gap + size.width
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}
