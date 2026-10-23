import Foundation

/// A file's size and modification date, through a symlink to the image it points to (`stat` follows links;
/// URL resource values report the link's own). One stat, about a quarter of a resource values read.
extension URL {
    /// The file's size in bytes, nil when it can't be read.
    public var fileSize: Int? { fileStatus.map { Int($0.st_size) } }

    /// The file's content modification date, nil when it can't be read.
    public var modificationDate: Date? {
        fileStatus.map {
            Date(timeIntervalSince1970: TimeInterval($0.st_mtimespec.tv_sec) + TimeInterval($0.st_mtimespec.tv_nsec) / 1e9)
        }
    }

    private var fileStatus: stat? {
        var info = stat()
        return withUnsafeFileSystemRepresentation { $0.map { stat($0, &info) } } == 0 ? info : nil
    }
}
