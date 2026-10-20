import Foundation

/// One release from the appcast.
public struct Release: Equatable, Sendable {
    public let version: String
    public let minimumSystemVersion: String
    /// The release page Download opens.
    public let link: URL
    /// Release notes as plain text.
    public let notes: String
}

/// Spec "Updates": reads the appcast and decides whether to tell about a newer version. Never installs anything.
public enum UpdateCheck {
    public static let feedURL = URL(string: "https://featherview.mynetx.net/appcast.xml")!
    public static let interval: TimeInterval = 24 * 60 * 60

    /// GET of the feed naming nothing but the app and its version.
    public static func request(appVersion: String) -> URLRequest {
        var request = URLRequest(url: feedURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.setValue("Featherview/\(appVersion)", forHTTPHeaderField: "User-Agent")
        return request
    }

    /// No cookies, cache or credentials kept between checks.
    public static func session() -> URLSession { URLSession(configuration: .ephemeral) }

    /// The feed's releases; a malformed feed has none. Items without a version or link are left out.
    public static func releases(from data: Data) -> [Release] {
        let reader = AppcastReader()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = reader
        return parser.parse() ? reader.releases : []
    }

    /// Numeric dotted comparison: 1.10 > 1.9, missing parts count as 0.
    public static func isNewer(_ version: String, than other: String) -> Bool {
        let a = numbers(version), b = numbers(other)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// The newest release newer than `current` that runs on `macOS`; nothing up to `skipped` is offered.
    public static func update(in releases: [Release], current: String, macOS: String, skipped: String?) -> Release? {
        releases
            .filter { isNewer($0.version, than: current) && isNewer($0.version, than: skipped ?? "0")
                && !isNewer($0.minimumSystemVersion, than: macOS) }
            .max { isNewer($1.version, than: $0.version) }
    }

    /// Whether the automatic check runs: enabled, and not checked in the last 24 hours (a last check in the future counts as long ago).
    public static func isDue(enabled: Bool, lastCheck: Date, now: Date) -> Bool {
        enabled && !(0..<interval).contains(now.timeIntervalSince(lastCheck))
    }

    /// Simple HTML as plain text: block ends become line breaks, list items bullets, other tags go.
    public static func plainText(_ html: String) -> String {
        var text = html
            .replacing(/(?i)<br\s*\/?>|<\/(p|li|h\d|div|ul|ol)>/, with: "\n")
            .replacing(/(?i)<li[^>]*>/, with: "• ")
            .replacing(/<[^>]*>/, with: "")
        for (entity, character) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&nbsp;", " "), ("&amp;", "&")] {
            text = text.replacing(entity, with: character)
        }
        return text
            .replacing(/[ \t]*\n[ \t]*/, with: "\n")
            .replacing(/\n{3,}/, with: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func numbers(_ version: String) -> [Int] {
        version.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
    }
}

/// Collects the fields of each `<item>`.
private final class AppcastReader: NSObject, XMLParserDelegate {
    private static let sparkle = "http://www.andymatuschak.org/xml-namespaces/sparkle"
    var releases: [Release] = []
    private var item: [String: String]?
    private var text = ""

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        if name == "item" { item = [:] }
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, foundCDATA block: Data) { text += String(decoding: block, as: UTF8.self) }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        guard item != nil else { return }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch (namespaceURI ?? "", name) {
        case (Self.sparkle, "shortVersionString"), (Self.sparkle, "minimumSystemVersion"), ("", "link"), ("", "description"):
            item?[name] = value
        case ("", "item"):
            if let fields = item, let version = fields["shortVersionString"], !version.isEmpty,
               let link = fields["link"].flatMap(URL.init(string:)), link.scheme == "https" {
                releases.append(Release(version: version, minimumSystemVersion: fields["minimumSystemVersion"] ?? "0",
                                        link: link, notes: UpdateCheck.plainText(fields["description"] ?? "")))
            }
            item = nil
        default: break
        }
        text = ""
    }
}
