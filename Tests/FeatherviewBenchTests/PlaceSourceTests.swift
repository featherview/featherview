import Foundation
import Testing
@testable import FeatherviewBench

@Suite struct PlaceSourceTests {
    /// The place sources (about 225 MB) download at most once a week; a younger cached copy is used as it is.
    @Test func cachedCopyLastsAWeek() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(placeCacheIsCurrent(modified: now.addingTimeInterval(-6 * 86_400), now: now))
        #expect(!placeCacheIsCurrent(modified: now.addingTimeInterval(-8 * 86_400), now: now))
        #expect(!placeCacheIsCurrent(modified: nil, now: now))
    }
}
