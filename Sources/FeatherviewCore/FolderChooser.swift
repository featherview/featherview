import Foundation

/// The keyboard-driven folder chooser shown past either end of a folder (spec "Moving past the end
/// of a folder"). Pure state: the view draws `entries`, keys call the mutating methods.
public struct FolderChooser: Equatable, Sendable {
    public enum Entry: Equatable, Sendable {
        /// "This folder again": the folder being listed.
        case again(URL)
        case parent(URL)
        case subfolder(URL)

        public var url: URL {
            switch self {
            case .again(let url), .parent(let url), .subfolder(let url): url
            }
        }
    }

    /// The folder whose parent and subfolders are listed.
    public private(set) var folder: URL
    public private(set) var entries: [Entry] = []
    public private(set) var selection = 0
    private let includeHidden: Bool

    /// Lists `folder`. Selects its first subfolder (going deeper is the usual next step), else the
    /// parent, else "this folder again".
    public init(folder: URL, includeHidden: Bool = false) {
        self.folder = folder
        self.includeHidden = includeHidden
        list(folder, selecting: nil)
    }

    public var selected: Entry { entries[selection] }

    /// ↑ / ↓: moves the selection, stopping at the first and last entry.
    public mutating func moveSelection(by delta: Int) {
        selection = min(max(selection + delta, 0), entries.count - 1)
    }

    /// → / Space: lists the selected folder. On the parent this is `up()`; on "again" nothing happens.
    public mutating func enter() {
        switch selected {
        case .again: break
        case .parent: up()
        case .subfolder(let url): list(url, selecting: nil)
        }
    }

    /// ←: lists the parent folder with the folder we came from selected. Nothing at the root.
    public mutating func up() {
        guard let parent = FolderTree.parent(of: folder) else { return }
        list(parent, selecting: folder)
    }

    private mutating func list(_ folder: URL, selecting previous: URL?) {
        self.folder = folder
        let subfolders = FolderTree.subfolders(of: folder, includeHidden: includeHidden)
        entries = [.again(folder)]
            + (FolderTree.parent(of: folder).map { [Entry.parent($0)] } ?? [])
            + subfolders.map { .subfolder($0) }
        let previousKey = previous.map(pathKey)
        selection = entries.firstIndex { entry in
            if case .subfolder(let url) = entry { return previousKey == nil || pathKey(url) == previousKey }
            return false
        } ?? (entries.count > 1 && previousKey == nil ? 1 : 0)
    }
}
