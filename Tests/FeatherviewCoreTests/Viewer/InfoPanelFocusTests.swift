import Foundation
import ImageIO
import Testing
@testable import FeatherviewCore

@Suite struct InfoPanelFocusTests {
    private func info(camera: String?) -> ImageInfo {
        let exif: [CFString: Any] = camera.map { [kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFModel: $0]] } ?? [:]
        return ImageInfo.read(properties: exif, metadata: nil, url: URL(fileURLWithPath: "/tmp/a.jpg"), fileSize: 10)
    }

    @Test func groupsLeaveOutEmptyOnes() {
        #expect(InfoPanelFocus.groups(info(camera: "X-T5"), last: []) == [.camera, .file])
        #expect(InfoPanelFocus.groups(info(camera: nil), last: [.camera, .file]) == [.file])
    }

    /// Review Focus 5: while the next file's info is read, its headers stay (the last file's), so a focused header
    /// keeps the focus and → goes on browsing.
    @Test func headersStayWhileTheNextFileIsRead() {
        let shown = InfoPanelFocus.groups(nil, last: [.camera, .file])
        #expect(shown == [.camera, .file])
        let order = InfoPanelFocus.order(picture: true, groups: shown, open: [], hasContent: true)
        #expect(order.contains(.header(.camera)))
    }

    @Test func tabOrder() {
        let order = InfoPanelFocus.order(picture: true, groups: [.camera, .location, .file], open: [.location, .file], hasContent: true)
        #expect(order == [.mode, .shadowsClip, .highlightsClip, .header(.camera), .header(.location), .button(.location),
                          .header(.file), .button(.file), .showAll])
        #expect(InfoPanelFocus.order(picture: false, groups: [], open: [], hasContent: false) == [.showAll])
    }

    /// A control the next file hasn't hands the focus to the stop after it, never back to the mode control, whose
    /// ← / → would switch the histogram instead of browsing.
    @Test func lostControlFocusesTheNextStop() {
        let order = InfoPanelFocus.order(picture: true, groups: [.image, .file], open: [], hasContent: true)
        #expect(InfoPanelFocus.repair(lost: .header(.camera), order: order) == .header(.image))
        #expect(InfoPanelFocus.repair(lost: .button(.location), order: order) == .header(.file))
        #expect(InfoPanelFocus.repair(lost: .header(.file), order: [.mode, .shadowsClip, .highlightsClip, .showAll]) == .showAll)
        #expect(InfoPanelFocus.repair(lost: .shadowsClip, order: [.header(.file), .showAll]) == .header(.file))
    }

    @Test func focusStillThereIsLeftAlone() {
        let order = InfoPanelFocus.order(picture: true, groups: [.file], open: [], hasContent: true)
        #expect(InfoPanelFocus.repair(lost: .header(.file), order: order) == nil)
    }

    /// Review: Open in Maps or Show in Finder leaves the view while the next file is read (its content waits for
    /// the info), so it is no stop then, and the focus on it moves on to the next header instead of to nothing.
    @Test func buttonsAreNoStopsWhileTheNextFileIsRead() {
        let order = InfoPanelFocus.order(picture: true, groups: [.location, .file], open: [.location, .file], hasContent: false)
        #expect(order == [.mode, .shadowsClip, .highlightsClip, .header(.location), .header(.file), .showAll])
        #expect(InfoPanelFocus.repair(lost: .button(.location), order: order) == .header(.file))
        #expect(InfoPanelFocus.repair(lost: .button(.file), order: order) == .showAll)
    }
}
