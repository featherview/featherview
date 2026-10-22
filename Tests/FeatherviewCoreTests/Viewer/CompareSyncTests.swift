import CoreGraphics
import Testing
@testable import FeatherviewCore

@Suite struct CompareSyncTests {
    @Test func sameSizeScaleIsOne() {
        #expect(CompareSync.scale(first: CGSize(width: 800, height: 600), second: CGSize(width: 800, height: 600)) == 1)
    }

    @Test func resizedCopyMatches() {
        let first = CGSize(width: 4000, height: 3000), second = CGSize(width: 1000, height: 750)
        let factor = CompareSync.matchedFactor(0.25, first: first, second: second)
        #expect(factor == 1.0)
        #expect(Double(first.width) * 0.25 == Double(second.width) * factor)
        #expect(Double(first.height) * 0.25 == Double(second.height) * factor)
    }

    @Test func differentAspectFitsInsideBox() {
        #expect(CompareSync.scale(first: CGSize(width: 4000, height: 3000), second: CGSize(width: 3000, height: 4000)) == 0.75)
    }

    @Test func emptySizeScaleIsOne() {
        #expect(CompareSync.scale(first: .zero, second: CGSize(width: 10, height: 10)) == 1)
        #expect(CompareSync.scale(first: CGSize(width: 10, height: 10), second: CGSize(width: 0, height: 10)) == 1)
    }

    @Test func matchedFactorClamps() {
        #expect(CompareSync.matchedFactor(0.05, first: CGSize(width: 4000, height: 3000), second: CGSize(width: 8000, height: 6000)) == 0.05)
        #expect(CompareSync.matchedFactor(16, first: CGSize(width: 1000, height: 750), second: CGSize(width: 100, height: 75)) == 16)
    }

    @Test func followerCentreSameSizeIsIdentity() {
        let size = CGSize(width: 800, height: 600)
        #expect(CompareSync.followerCentre(CGPoint(x: 300, y: 200), leaderDrawn: size, followerDrawn: size) == CGPoint(x: 300, y: 200))
    }

    @Test func followerCentreOffsetsByHalfTheDifference() {
        let wide = CGSize(width: 800, height: 600), narrow = CGSize(width: 450, height: 600)
        #expect(CompareSync.followerCentre(CGPoint(x: 400, y: 300), leaderDrawn: wide, followerDrawn: narrow) == CGPoint(x: 225, y: 300))
        #expect(CompareSync.followerCentre(CGPoint(x: 225, y: 300), leaderDrawn: narrow, followerDrawn: wide) == CGPoint(x: 400, y: 300))
    }
}
