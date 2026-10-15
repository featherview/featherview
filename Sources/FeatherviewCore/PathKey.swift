import Foundation

/// Identity of a file for comparisons: resolves symlinks (/var vs /private/var) and ignores case,
/// because APFS volumes are case-insensitive by default.
func pathKey(_ url: URL) -> String {
    url.resolvingSymlinksInPath().path.lowercased()
}
