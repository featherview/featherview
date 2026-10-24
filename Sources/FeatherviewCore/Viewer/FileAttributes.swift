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

/// Size and modification date of every regular file in a folder, by name, from `getattrlistbulk`: a few calls for the
/// whole folder, ~10x faster than a stat per file. Symlinks aren't listed (a stat follows them to the image).
enum FolderAttributes {
    struct Entry: Equatable { let size: Int; let modified: Date }

    static func read(_ folder: String) -> [String: Entry]? {
        let fd = open(folder, O_RDONLY | O_DIRECTORY)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS) | attrgroup_t(ATTR_CMN_NAME)
            | attrgroup_t(ATTR_CMN_OBJTYPE) | attrgroup_t(ATTR_CMN_MODTIME)
        request.fileattr = attrgroup_t(ATTR_FILE_DATALENGTH)
        let size = 256 * 1024
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 8)
        defer { buffer.deallocate() }
        var entries: [String: Entry] = [:]
        while true {
            let count = getattrlistbulk(fd, &request, buffer, size, 0)
            if count < 0 { return nil }
            if count == 0 { return entries }
            var entry = buffer
            for _ in 0..<count {
                let length = Int(entry.loadUnaligned(as: UInt32.self))
                defer { entry += length }
                // Attributes follow in bit order, each 4-byte aligned; absent ones take no space.
                var field = entry + 4
                let returned = field.loadUnaligned(as: attribute_set_t.self)
                field += MemoryLayout<attribute_set_t>.size
                guard returned.commonattr & attrgroup_t(ATTR_CMN_NAME) != 0 else { continue }
                let nameOffset = Int(field.loadUnaligned(as: Int32.self))
                let nameLength = Int(field.loadUnaligned(fromByteOffset: 4, as: UInt32.self))
                let name = String(decoding: UnsafeRawBufferPointer(start: field + nameOffset, count: max(nameLength - 1, 0)),
                                  as: UTF8.self)
                field += MemoryLayout<attrreference_t>.size
                guard returned.commonattr & attrgroup_t(ATTR_CMN_OBJTYPE) != 0,
                      field.loadUnaligned(as: UInt32.self) == UInt32(VREG.rawValue) else { continue }
                field += MemoryLayout<fsobj_type_t>.size
                guard returned.commonattr & attrgroup_t(ATTR_CMN_MODTIME) != 0,
                      returned.fileattr & attrgroup_t(ATTR_FILE_DATALENGTH) != 0 else { continue }
                let time = field.loadUnaligned(as: timespec.self)
                field += MemoryLayout<timespec>.size
                let bytes = field.loadUnaligned(as: off_t.self)
                entries[name] = Entry(size: Int(bytes),
                                      modified: Date(timeIntervalSince1970: TimeInterval(time.tv_sec) + TimeInterval(time.tv_nsec) / 1e9))
            }
        }
    }
}
