import Testing
@testable import FeatherviewBench

@Suite struct BaselineTests {
    func row(_ file: String, _ screen: String = "800x600", median: Double) -> Row {
        Row(file: file, screen: screen, width: 1, height: 1, megabytes: 0, firstMs: median, medianMs: median,
            p95Ms: median, minMs: median)
    }

    @Test func sameSpeedPasses() {
        #expect(baselineFailures([row("a.jpg", median: 10.5)], baseline: [row("a.jpg", median: 10)]).isEmpty)
    }

    @Test func slowerFails() {
        #expect(baselineFailures([row("a.jpg", median: 12)], baseline: [row("a.jpg", median: 10)])
            == ["slower: a.jpg 800x600 median 10.0 → 12.0 ms"])
    }

    @Test func rowMissingFromThisRunFails() {
        let failures = baselineFailures([row("b.jpg", median: 10)],
                                        baseline: [row("a.jpg", median: 10), row("b.jpg", median: 10)])
        #expect(failures == ["missing: a.jpg 800x600 (no longer decodes, or not run on this screen)"])
    }

    @Test func otherScreenFails() {
        let failures = baselineFailures([row("a.jpg", "1024x768", median: 10)], baseline: [row("a.jpg", median: 10)])
        #expect(failures == ["missing: a.jpg 800x600 (no longer decodes, or not run on this screen)"])
    }
}
