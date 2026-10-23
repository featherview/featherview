import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct UpdateCheckTests {
    private static let appcast = """
    <?xml version="1.0" encoding="utf-8"?>
    <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
      <channel>
        <title>Featherview</title>
        <item>
          <title>Featherview 1.10.0</title>
          <sparkle:shortVersionString>1.10.0</sparkle:shortVersionString>
          <sparkle:version>12</sparkle:version>
          <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
          <link>https://featherview.mynetx.net/releases/1.10.0</link>
          <description><![CDATA[<h2>New</h2><ul><li>Faster &amp; smaller</li><li>WebP fix</li></ul>]]></description>
          <pubDate>Mon, 19 Oct 2026 10:00:00 +0000</pubDate>
          <enclosure url="https://github.com/featherview/featherview/releases/download/v1.10.0/Featherview-1.10.0.dmg"
                     length="5148568" type="application/x-apple-diskimage"/>
        </item>
        <item>
          <title>Featherview 1.9.0</title>
          <sparkle:shortVersionString>1.9.0</sparkle:shortVersionString>
          <sparkle:version>11</sparkle:version>
          <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
          <link>https://featherview.mynetx.net/releases/1.9.0</link>
          <description>Plain notes.</description>
          <pubDate>Mon, 12 Oct 2026 10:00:00 +0000</pubDate>
          <enclosure url="http://example.com/Featherview-1.9.0.dmg" type="application/x-apple-diskimage"/>
        </item>
      </channel>
    </rss>
    """

    private var releases: [Release] { UpdateCheck.releases(from: Data(Self.appcast.utf8)) }

    @Test func parsesEveryItem() {
        // 1.9.0's enclosure is plain http: no download, Download falls back to the release page.
        #expect(releases == [
            Release(version: "1.10.0", minimumSystemVersion: "15.0",
                    link: URL(string: "https://featherview.mynetx.net/releases/1.10.0")!,
                    notes: "New\n• Faster & smaller\n• WebP fix",
                    download: URL(string: "https://github.com/featherview/featherview/releases/download/v1.10.0/Featherview-1.10.0.dmg")!),
            Release(version: "1.9.0", minimumSystemVersion: "14.0",
                    link: URL(string: "https://featherview.mynetx.net/releases/1.9.0")!, notes: "Plain notes."),
        ])
    }

    @Test func malformedOrEmptyFeedHasNoReleases() {
        #expect(UpdateCheck.releases(from: Data()).isEmpty)
        #expect(UpdateCheck.releases(from: Data("<rss><channel><item><title>x".utf8)).isEmpty)
        #expect(UpdateCheck.releases(from: Data("not xml at all".utf8)).isEmpty)
        // An item without a version or link can't be offered.
        #expect(UpdateCheck.releases(from: Data("<rss><channel><item><link>https://a.b</link></item></channel></rss>".utf8)).isEmpty)
    }

    @Test func versionsCompareNumerically() {
        #expect(UpdateCheck.isNewer("1.10", than: "1.9"))
        #expect(UpdateCheck.isNewer("1.2.1", than: "1.2"))
        #expect(!UpdateCheck.isNewer("1.2.0", than: "1.2"))
        #expect(!UpdateCheck.isNewer("1.2", than: "1.2.0"))
        #expect(!UpdateCheck.isNewer("0.9", than: "1.0"))
        #expect(UpdateCheck.isNewer("2", than: "1.99.99"))
    }

    @Test func offersTheNewestReleaseThatRunsHere() {
        #expect(UpdateCheck.update(in: releases, current: "1.0.0", macOS: "15.1", skipped: nil)?.version == "1.10.0")
        // 1.10.0 needs macOS 15.
        #expect(UpdateCheck.update(in: releases, current: "1.0.0", macOS: "14.6", skipped: nil)?.version == "1.9.0")
        #expect(UpdateCheck.update(in: releases, current: "1.10.0", macOS: "15.1", skipped: nil) == nil)
        #expect(UpdateCheck.update(in: [], current: "1.0.0", macOS: "15.1", skipped: nil) == nil)
    }

    @Test func skippedVersionStaysQuietUntilANewerOne() {
        #expect(UpdateCheck.update(in: releases, current: "1.0.0", macOS: "15.1", skipped: "1.10.0") == nil)
        #expect(UpdateCheck.update(in: releases, current: "1.0.0", macOS: "15.1", skipped: "1.9.0")?.version == "1.10.0")
    }

    @Test func automaticCheckOncePerDayWhenEnabled() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(UpdateCheck.isDue(enabled: true, lastCheck: .distantPast, now: now))
        #expect(UpdateCheck.isDue(enabled: true, lastCheck: now.addingTimeInterval(-24 * 3600), now: now))
        #expect(!UpdateCheck.isDue(enabled: true, lastCheck: now.addingTimeInterval(-23 * 3600), now: now))
        #expect(!UpdateCheck.isDue(enabled: false, lastCheck: .distantPast, now: now))
        // A clock set back never blocks checks for good.
        #expect(UpdateCheck.isDue(enabled: true, lastCheck: now.addingTimeInterval(3600), now: now))
    }

    @Test func requestNamesOnlyTheApp() {
        let request = UpdateCheck.request(appVersion: "1.2.0")
        #expect(request.url == URL(string: "https://featherview.mynetx.net/appcast.xml"))
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "Featherview/1.2.0")
        #expect(request.timeoutInterval == 15)
        #expect(request.httpShouldHandleCookies == false)
    }

    @Test func notesBecomePlainText() {
        #expect(UpdateCheck.plainText("<p>One<br>Two</p><p>&quot;Three&quot; &lt;4&gt;&nbsp;5</p>") == "One\nTwo\n\"Three\" <4> 5")
        #expect(UpdateCheck.plainText("  Just text  ") == "Just text")
    }
}
