import FeatherviewCore
import Testing

struct DropItemTests {
    private let file = "public.file-url"
    private let promises: Set<String> = ["com.apple.NSFilePromiseItemMetaData", "com.apple.pasteboard.promised-file-url"]

    /// A promise is received only for an item without a file URL; the receivers count every promise item.
    @Test func promisesOnlyForItemsWithoutAFileURL() {
        let items = [
            ["com.apple.pasteboard.promised-file-url"],
            [file, "com.apple.pasteboard.promised-file-url"],
            [file],
            ["public.utf8-plain-text"],
            ["com.apple.NSFilePromiseItemMetaData"],
        ]
        #expect(DropItem.plan(items, fileURLType: file, promiseTypes: promises)
                == [.promise(0), .file, .file, .skipped, .promise(2)])
    }
}
