/// The info panel's groups, in the order the panel shows them.
public enum InfoGroup: CaseIterable, Hashable, Sendable {
    case camera, image, location, description, file
}

/// The panel's keyboard stops, in Tab order (spec "Keyboard and accessibility").
public enum InfoFocus: Hashable, Sendable {
    case mode, shadowsClip, highlightsClip
    case header(InfoGroup)
    case button(InfoGroup)
    case showAll

    /// Place in the full Tab order, whatever the file has.
    fileprivate var rank: Int {
        switch self {
        case .mode: 0
        case .shadowsClip: 1
        case .highlightsClip: 2
        case .header(let group): 3 + 2 * InfoGroup.allCases.firstIndex(of: group)!
        case .button(let group): 4 + 2 * InfoGroup.allCases.firstIndex(of: group)!
        case .showAll: .max
        }
    }
}

/// Which groups the info panel shows and its controls in Tab order.
public enum InfoPanelFocus {
    /// The file's groups with something in them; while its info is read (`info` nil), the last file's, so their
    /// headers, and a focused one, stay on screen.
    public static func groups(_ info: ImageInfo?, last: [InfoGroup]) -> [InfoGroup] {
        guard let info else { return last }
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

    /// Mode, clip marks (with a picture), then each group's header and, when open, its button (Location's
    /// Open in Maps, File's Show in Finder), then "Show all metadata…".
    public static func order(picture: Bool, groups: [InfoGroup], open: Set<InfoGroup>, hasFile: Bool) -> [InfoFocus] {
        var order: [InfoFocus] = picture ? [.mode, .shadowsClip, .highlightsClip] : []
        for group in groups {
            order.append(.header(group))
            let hasButton = group == .file ? hasFile : group == .location
            if hasButton, open.contains(group) { order.append(.button(group)) }
        }
        order.append(.showAll)
        return order
    }

    /// Where the focus goes when the focused control `lost` left the view: the stop after it, so it stays near where
    /// it was (never back to the mode control, whose ← / → would take the browsing keys); nil while it is still there.
    public static func repair(lost: InfoFocus, order: [InfoFocus]) -> InfoFocus? {
        guard !order.contains(lost) else { return nil }
        return order.first { $0.rank > lost.rank } ?? order.last
    }
}
