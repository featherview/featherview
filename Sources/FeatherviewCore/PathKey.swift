import Darwin
import Foundation

/// Identity of a file for comparisons: resolves symlinks (/var vs /private/var) and folds case like APFS
/// (ß = ss) unless the file's volume is case-sensitive (APFS volumes are case-insensitive by default).
func pathKey(_ url: URL) -> String {
    let path = url.resolvingSymlinksInPath().path
    // The nearest existing folder decides, so a missing file gets the same key as when it existed.
    // pathconf is one cheap syscall; resource values cost far more when the path is missing.
    var probe = path
    while true {
        switch pathconf(probe, _PC_CASE_SENSITIVE) {
        case 1: return path
        case 0: return path.folding(options: .caseInsensitive, locale: nil)
        default:
            guard probe != "/", !probe.isEmpty else { return path.folding(options: .caseInsensitive, locale: nil) }
            probe = (probe as NSString).deletingLastPathComponent
        }
    }
}
