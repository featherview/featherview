import Foundation
import Testing
import UniformTypeIdentifiers
@testable import FeatherviewCore

@Suite struct DefaultViewerTests {
    private let ownID = "net.mynetx.featherview"
    private let home = URL(fileURLWithPath: "/Users/someone")
    private let psd = UTType("com.adobe.photoshop-image")!

    @Test func previewTypesAreClaimed() {
        let handlers: [UTType: String] = [.jpeg: "com.apple.Preview", psd: "com.adobe.Photoshop"]
        let types = DefaultViewer.typesToClaim([.jpeg, .png, psd, .jpeg], ownID: ownID) { handlers[$0] }
        #expect(types == [.jpeg, .png])
    }

    @Test func pdfIsNeverClaimed() {
        #expect(DefaultViewer.typesToClaim([.pdf], ownID: ownID) { _ in "com.apple.Preview" } == [])
    }

    @Test func ownTypesAndDynamicTypesAreSkipped() throws {
        let dynamic = try #require(UTType(filenameExtension: "zzqx"))
        #expect(dynamic.identifier.hasPrefix("dyn."))
        #expect(DefaultViewer.typesToClaim([.gif], ownID: ownID) { _ in ownID } == [])
        #expect(DefaultViewer.typesToClaim([dynamic], ownID: ownID) { _ in nil } == [])
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
