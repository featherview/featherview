/// How each item of a drop brings its file: Finder's carry a file URL, Photos' a file promise.
public enum DropItem: Equatable, Sendable {
    /// Taken as the file URL it carries.
    case file
    /// Received through the n-th promise on the pasteboard (one per item with a promise type).
    case promise(Int)
    case skipped

    /// An item with a file URL is never received again through a promise it also offers.
    public static func plan(_ itemTypes: [[String]], fileURLType: String, promiseTypes: Set<String>) -> [DropItem] {
        var promises = 0
        return itemTypes.map { types in
            let isPromise = types.contains(where: promiseTypes.contains)
            defer { if isPromise { promises += 1 } }
            if types.contains(fileURLType) { return .file }
            return isPromise ? .promise(promises) : .skipped
        }
    }
}
