import Foundation
import Testing
import UniformTypeIdentifiers
@testable import FeatherviewCore

@Suite struct DefaultViewerTests {
    private let ownID = "net.mynetx.featherview"
    private let home = URL(fileURLWithPath: "/Users/someone")
    private let psd = UTType("com.adobe.photoshop-image")!

    private func claimable(_ name: String) -> UTType? {
        DefaultViewer.claimableType(for: URL(fileURLWithPath: "/Users/someone/Pictures/\(name)"))
    }

    @Test func fileTypeIsClaimable() {
        #expect(claimable("IMG_1234.JPG") == .jpeg)
        #expect(claimable("scan.tif") == .tiff)
        #expect(claimable("layers.psd") == psd)
    }

    @Test func pdfIsNeverClaimed() {
        #expect(claimable("manual.pdf") == nil)
    }

    @Test func unknownExtensionsAreNotClaimed() {
        #expect(claimable("notes.zzqx") == nil)
        #expect(claimable("README") == nil)
    }

    @Test func commonTypesAreTheOneClickSet() {
        #expect(DefaultViewer.commonTypes == [.jpeg, .png, .heic, .gif, .tiff, .webP])
    }

    private func offer(_ path: String, offeredBefore: Bool = false, jpegHandler: String? = "com.apple.Preview") -> Bool {
        DefaultViewer.shouldOffer(bundleURL: URL(fileURLWithPath: path), home: home,
                                  offeredBefore: offeredBefore, jpegHandler: jpegHandler)
    }

    @Test func offerOnlyFromApplications() {
        #expect(offer("/Applications/Featherview.app"))
        #expect(offer("/Users/someone/Applications/Featherview.app"))
        #expect(!offer("/Users/someone/Web/featherview/build/Featherview.app"))
        #expect(!offer("/Volumes/Featherview/Featherview.app"))
        #expect(!offer("/Users/someone/Downloads/Featherview.app"))
        #expect(!offer("/private/var/folders/xy/abc/T/AppTranslocation/1234-5678/d/Featherview.app"))
    }

    @Test func offerOnlyOnce() {
        #expect(!offer("/Applications/Featherview.app", offeredBefore: true))
    }

    @Test func noOfferWhenAnotherAppOpensJPEG() {
        #expect(!offer("/Applications/Featherview.app", jpegHandler: "com.adobe.Photoshop"))
        #expect(offer("/Applications/Featherview.app", jpegHandler: nil))
    }
}
