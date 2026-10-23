import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct SignpostsTests {
    @Test func durationInMilliseconds() {
        #expect(Duration.seconds(2).milliseconds == 2000)
        #expect(Duration.microseconds(1500).milliseconds == 1.5)
        #expect(Int(Duration.nanoseconds(107_900_000).milliseconds) == 107)  // whole milliseconds for log lines
    }
}
