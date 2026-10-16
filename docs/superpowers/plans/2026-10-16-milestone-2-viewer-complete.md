# Featherview v1 — Milestone 2 Implementation Plan (viewer complete)

> **Milestone 2 of 6** in `docs/roadmap.md`. Builds on milestone 1 (`2026-10-15-featherview-v1.md`,
> done). Formats, Save As, the About window and the Formats settings tab are milestone 3; the full
> batch window is milestone 4. Don't add them here.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. In this repo, run it wave by wave with the `plan-wave` workflow.

**Goal:** Finish the viewer: folder chooser past either end, panning by drag and arrow keys,
multi-page TIFF, F7 / F8 move and copy with 14 slots and sidecar files, ⌘C, a context menu, the
toolbar, one window per file from Finder, and the Settings window.

**Architecture:** New logic goes into `FeatherviewCore` with Swift Testing tests (settings keys and
defaults, folder tree and chooser state, sidecars, never-overwrite move/copy, destination slots,
TIFF pages). The app stays thin: `ViewerModel` calls the core, `ViewerView` maps keys, new small
views draw the chooser, the destination panel, the toolbar and the Settings window. The image is
drawn by an AppKit `NSScrollView` (`ImageCanvas`), because SwiftUI's `ScrollView` can't pan by
dragging or report whether an arrow key can pan.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI + AppKit, ImageIO, Swift Testing, SwiftPM.
No third-party dependencies.

**Spec:** `docs/spec.md` sections "Viewer" (all), "Settings" (all but Formats), "Windows". Rules,
budgets and commands: `AGENTS.md`. Read both first. Observed behaviour behind the decisions:
`docs/parity.md` ("Mouse, pages and toolbar").

## Global Constraints

- macOS 14.0 minimum. APIs newer than 14 need `if #available` and a 14 fallback.
- Bundle ID and log subsystem `net.mynetx.featherview`. Settings live in `UserDefaults.standard`
  under the keys in `AppSettings` (Task 1); never rename a key once shipped.
- No third-party dependencies. No `.xcodeproj`.
- Clean room (`AGENTS.md`): our own UI text, SF Symbols only, no layouts copied from the reference viewer.
- Never lose data: move/copy never overwrite (" 2", " 3", …), delete means Trash, a failed move leaves the original.
- Decode off the main thread; folder listing and image counts off the main thread; the UI never blocks.
- User-facing text is a SwiftUI literal or `String(localized:)`, never concatenated pieces (`AGENTS.md`).
  Existing interpolated strings like `"Can't open \(name)"` stay as they are until milestone 6.
- Layout uses leading/trailing, never left/right. Arrow-key panning stays physical (← pans left).
- Single keys are handled in `ViewerView.handle`, never as menu shortcuts (so text fields in other
  windows never trigger them). ⌥1–⌥3 and ⌘C are menu shortcuts that act only on a focused viewer.
- Performance budgets in `AGENTS.md` stay met; Task 11 measures them again.
- Commits: conventional commits, no AI attribution lines.

## Review Focus

1. **A move or copy onto names that exist** — same name, a name differing only in case, or only a
   sidecar's name taken. Nothing may be overwritten and an image must keep its sidecars' base name.
   Pinned by `FileMoverTests.neverOverwritesAndKeepsSidecarsPaired` and `nameClashIgnoresCase` (Task 3).
2. **A destination that can't be written** (read-only folder, ejected drive, deleted slot folder) —
   the original stays where it was and the viewer says "Couldn't move <name> to <folder>". Pinned by
   `FileMoverTests.unwritableDestinationThrowsAndKeepsTheOriginal` (Task 3); message: Task 9 step.
3. **The folder chooser at odd places** — the file-system root (no parent), a folder without
   subfolders, a folder of only non-images, symlinked folders, packages like `.app`. No crash, no
   empty list, no blocked UI. Pinned by `FolderChooserTests.rootHasNoParentEntry`,
   `withoutSubfoldersStartsOnTheParent`, `FolderTreeTests.subfoldersInFinderOrderSkippingHiddenAndPackages`,
   `imageCounts` (Task 2); counting off the main thread: Task 8; big folders: Task 11 QA.
4. **Files with several images that are not pages** — animated GIF, HEIC bursts — must not get page
   keys or a page title; a page past the end throws instead of returning page 0. Pinned by
   `PageTests.multiPageTIFFHasPagesOthersHaveOne`, `decodesEachPage` (Task 5).
5. **Copy and Paste in text fields** after the viewer takes over ⌘C — the batch window's and the
   Settings window's text fields must still copy, cut and paste; single keys must not fire there.
   Pinned by Task 11 QA steps 7 and 8 (no unit test can drive the responder chain).

## Verification status (as of 2026-10-16)

- Every `FeatherviewCore` file and test in Tasks 1–5 was written, compiled under Swift 6 strict
  concurrency with Xcode 27.1 and **passed** (`swift test`: 101 tests, 22 suites, the whole
  milestone-1 suite included) in a scratch worktree. Copy them as given.
- The app code in Tasks 1 and 6–10 **compiled warning-free together** in the same worktree. It has
  **not been run**: the Mac's display was locked at the time. Expect behaviour fixes in Task 11, in
  particular: the context menu over the AppKit canvas, drag panning direction, toolbar
  customization being remembered, and the window-frame setting. Fix what Task 11 finds; don't
  redesign.

## Execution order (for plan-wave)

| Wave | Tasks (parallel within a wave) | Needs |
|---|---|---|
| A | 1, 2, 3, 4, 5 | milestone 1 merged |
| B | 6 | wave A (uses `AppSettings`, `DestinationSlots`) |
| C | 7 | 6 |
| D | 8 | 7 (and 2, 5) |
| E | 9 | 8 (and 3, 4) |
| F | 10 | 9 |
| G | 11 | 10 (manual, with the maintainer) |

Wave A tasks touch disjoint files (Task 1 also adds two lines to `ViewerView.swift`; no other wave-A
task touches it). Tasks 6–10 all edit `ViewerModel.swift` and `ViewerView.swift`, so they run one
after another. Commit per task.

Code shown as **Add** goes into the named type at a sensible place; **Replace** shows the exact old
text first. Line numbers aren't given because earlier tasks move them.

---
### Task 1: Settings keys and defaults, overlay text, the P key

**Files:**
- Create: `Sources/FeatherviewCore/AppSettings.swift`
- Create: `Sources/FeatherviewCore/OverlayTemplate.swift`
- Modify: `Sources/FeatherviewCore/ViewerKey.swift`
- Modify: `Sources/Featherview/ViewerView.swift` (the `ViewerKey` switch)
- Test: `Tests/FeatherviewCoreTests/AppSettingsTests.swift`, `Tests/FeatherviewCoreTests/ViewerKeyTests.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces: `struct Setting<Value>` with `key`, `defaultValue`, `value(in: UserDefaults = .standard) -> Value`;
  `enum PastEndBehavior: String { folderChooser, loop, stop }`; `enum AppSettings` with static settings
  `pastEnd` (String raw value), `showHiddenFiles`, `showNextAfterRemoval`, `moveSidecars`,
  `backgroundColor` (`"#RRGGBB"`), `checkerboard`, `rememberWindowFrame`, `zoomStepPercent` (Int),
  `showOverlay`, `overlayTemplate`, `hidePointer`, `askBeforeMoveCopy`, `openWith: [Setting<String>]`
  (3 app paths), plus `pastEndBehavior` and `registerDefaults(in:)`; `enum HexColor` with
  `parse(_:) -> (red, green, blue)?` and `format(red:green:blue:) -> String`;
  `OverlayTemplate.render(_ template: String, values: [String: String]) -> String`;
  `ViewerKey.settings` for "p".

The name is `AppSettings`, not `Settings`: SwiftUI's `Settings` scene would clash in the app target.

- [ ] **Step 1: Write the failing tests**

`Tests/FeatherviewCoreTests/AppSettingsTests.swift`:

```swift
import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct AppSettingsTests {
    /// A private defaults domain per test, so tests never touch the user's settings or each other.
    private func freshDefaults() -> UserDefaults {
        let name = "featherview-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func defaultsMatchTheSpec() {
        let defaults = freshDefaults()
        AppSettings.registerDefaults(in: defaults)
        #expect(AppSettings.pastEnd.value(in: defaults) == "folderChooser")
        #expect(defaults.bool(forKey: AppSettings.showHiddenFiles.key) == false)
        #expect(defaults.bool(forKey: AppSettings.showNextAfterRemoval.key) == true)
        #expect(defaults.bool(forKey: AppSettings.moveSidecars.key) == true)
        #expect(defaults.string(forKey: AppSettings.backgroundColor.key) == "#000000")
        #expect(defaults.bool(forKey: AppSettings.checkerboard.key) == true)
        #expect(defaults.bool(forKey: AppSettings.rememberWindowFrame.key) == true)
        #expect(defaults.integer(forKey: AppSettings.zoomStepPercent.key) == 10)
        #expect(defaults.bool(forKey: AppSettings.showOverlay.key) == false)
        #expect(defaults.bool(forKey: AppSettings.hidePointer.key) == true)
        #expect(defaults.bool(forKey: AppSettings.askBeforeMoveCopy.key) == false)
        #expect(AppSettings.openWith.map { $0.value(in: defaults) } == ["", "", ""])
    }

    @Test func storedValueWinsAndWrongTypeFallsBack() {
        let defaults = freshDefaults()
        defaults.set(25, forKey: AppSettings.zoomStepPercent.key)
        defaults.set("yes", forKey: AppSettings.checkerboard.key)
        #expect(AppSettings.zoomStepPercent.value(in: defaults) == 25)
        #expect(AppSettings.checkerboard.value(in: defaults) == true)
    }

    @Test func unknownPastEndFallsBackToChooser() {
        #expect(PastEndBehavior(rawValue: "sideways") == nil)
        #expect(PastEndBehavior.allCases == [.folderChooser, .loop, .stop])
    }

    @Test func hexColorsRoundTrip() throws {
        let color = try #require(HexColor.parse("#FF8000"))
        #expect(color.red == 1)
        #expect(abs(color.green - 128.0 / 255) < 0.0001)
        #expect(color.blue == 0)
        #expect(HexColor.format(red: color.red, green: color.green, blue: color.blue) == "#FF8000")
    }

    @Test(arguments: ["", "000000", "#00000", "#GG0000", "#0000000"])
    func malformedHexIsRejected(_ hex: String) {
        #expect(HexColor.parse(hex) == nil)
    }
}

@Suite struct OverlayTemplateTests {
    @Test func replacesEveryPlaceholder() {
        let text = OverlayTemplate.render(
            "{name} in {folder}: {index}/{count}, {size}, {date}",
            values: ["name": "a.jpg", "folder": "Trip", "index": "3", "count": "9",
                     "size": "4032 × 3024", "date": "16.10.2026"])
        #expect(text == "a.jpg in Trip: 3/9, 4032 × 3024, 16.10.2026")
    }

    @Test func missingValuesBecomeEmptyAndUnknownPlaceholdersStay() {
        #expect(OverlayTemplate.render("{name} {date} {iso}", values: ["name": "a.jpg"]) == "a.jpg  {iso}")
    }
}
```

In `Tests/FeatherviewCoreTests/ViewerKeyTests.swift`, extend the arguments of
`commandsHaveSingleKeysLikeTheReferenceViewer`:

```swift
    @Test(arguments: [("o", ViewerKey.open), ("b", .batch), ("m", .minimize), ("p", .settings)])
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --filter 'AppSettingsTests|OverlayTemplateTests|ViewerKeyTests'`
Expected: compile errors (`AppSettings`, `OverlayTemplate`, `.settings` not found).

- [ ] **Step 3: Implement**

`Sources/FeatherviewCore/AppSettings.swift`:

```swift
import Foundation

/// One setting: its UserDefaults key and the default the spec gives it.
public struct Setting<Value: Sendable>: Sendable {
    public let key: String
    public let defaultValue: Value

    /// The stored value, or the default when nothing (or something of another type) is stored.
    public func value(in defaults: UserDefaults = .standard) -> Value {
        defaults.object(forKey: key) as? Value ?? defaultValue
    }
}

/// What → does past the last image (and ← before the first).
public enum PastEndBehavior: String, CaseIterable, Sendable {
    case folderChooser, loop, stop
}

/// Every setting from spec "Settings" with its default. The app binds them with
/// `@AppStorage(AppSettings.x.key)`; models read them with `AppSettings.x.value()`.
public enum AppSettings {
    // Browsing
    public static let pastEnd = Setting(key: "pastEnd", defaultValue: PastEndBehavior.folderChooser.rawValue)
    public static let showHiddenFiles = Setting(key: "showHiddenFiles", defaultValue: false)
    public static let showNextAfterRemoval = Setting(key: "showNextAfterRemoval", defaultValue: true)
    public static let moveSidecars = Setting(key: "moveSidecars", defaultValue: true)
    // Viewer
    public static let backgroundColor = Setting(key: "backgroundColor", defaultValue: "#000000")
    public static let checkerboard = Setting(key: "checkerboard", defaultValue: true)
    public static let rememberWindowFrame = Setting(key: "rememberWindowFrame", defaultValue: true)
    public static let zoomStepPercent = Setting(key: "zoomStepPercent", defaultValue: 10)
    // Full screen
    public static let showOverlay = Setting(key: "showOverlay", defaultValue: false)
    public static let overlayTemplate = Setting(key: "overlayTemplate", defaultValue: "{name} — {index} / {count}")
    public static let hidePointer = Setting(key: "hidePointer", defaultValue: true)
    // Move / copy
    public static let askBeforeMoveCopy = Setting(key: "askBeforeMoveCopy", defaultValue: false)
    // Open with: app paths for ⌥1, ⌥2, ⌥3 ("" = none)
    public static let openWith = (1...3).map { Setting(key: "openWith\($0)", defaultValue: "") }

    public static var pastEndBehavior: PastEndBehavior {
        PastEndBehavior(rawValue: pastEnd.value()) ?? .folderChooser
    }

    /// Registers every default, so `UserDefaults.bool(forKey:)` and friends agree with the spec.
    public static func registerDefaults(in defaults: UserDefaults = .standard) {
        var values: [String: Any] = [
            pastEnd.key: pastEnd.defaultValue,
            showHiddenFiles.key: showHiddenFiles.defaultValue,
            showNextAfterRemoval.key: showNextAfterRemoval.defaultValue,
            moveSidecars.key: moveSidecars.defaultValue,
            backgroundColor.key: backgroundColor.defaultValue,
            checkerboard.key: checkerboard.defaultValue,
            rememberWindowFrame.key: rememberWindowFrame.defaultValue,
            zoomStepPercent.key: zoomStepPercent.defaultValue,
            showOverlay.key: showOverlay.defaultValue,
            overlayTemplate.key: overlayTemplate.defaultValue,
            hidePointer.key: hidePointer.defaultValue,
            askBeforeMoveCopy.key: askBeforeMoveCopy.defaultValue,
        ]
        for setting in openWith { values[setting.key] = setting.defaultValue }
        defaults.register(defaults: values)
    }
}

/// `#RRGGBB` colours, the form the background colour setting is stored in.
public enum HexColor {
    /// Components 0...1, or nil if `hex` isn't `#RRGGBB`.
    public static func parse(_ hex: String) -> (red: Double, green: Double, blue: Double)? {
        guard hex.count == 7, hex.first == "#", let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        return (Double(value >> 16 & 0xFF) / 255, Double(value >> 8 & 0xFF) / 255, Double(value & 0xFF) / 255)
    }

    public static func format(red: Double, green: Double, blue: Double) -> String {
        func byte(_ c: Double) -> Int { Int((min(max(c, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }
}
```

`Sources/FeatherviewCore/OverlayTemplate.swift`:

```swift
/// The full-screen overlay text: a template with `{name}`, `{folder}`, `{index}`, `{count}`,
/// `{size}`, `{date}`. Unknown placeholders stay as typed, so a typo is visible, not silently dropped.
public enum OverlayTemplate {
    public static let placeholders = ["name", "folder", "index", "count", "size", "date"]

    public static func render(_ template: String, values: [String: String]) -> String {
        var result = template
        for key in placeholders {
            result = result.replacingOccurrences(of: "{\(key)}", with: values[key] ?? "")
        }
        return result
    }
}
```

`Sources/FeatherviewCore/ViewerKey.swift`: add `settings` to the commands case and map "p":

```swift
    case open, batch, minimize, settings
```

```swift
        case "m": return .minimize
        case "p": return .settings
```

`Sources/Featherview/ViewerView.swift`: the switch over `ViewerKey` must stay exhaustive. Add to
`ViewerView`:

```swift
    @Environment(\.openSettings) private var openSettings
```

and to the `switch action` in `handle(_:)`:

```swift
        case .settings: openSettings()
```

(Until Task 6 adds the Settings scene, P does nothing visible. That's expected.)

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter 'AppSettingsTests|OverlayTemplateTests|ViewerKeyTests' && swift build`
Expected: all pass; the app builds.

- [ ] **Step 5: Commit**

```bash
git add Sources/FeatherviewCore/AppSettings.swift Sources/FeatherviewCore/OverlayTemplate.swift \
  Sources/FeatherviewCore/ViewerKey.swift Sources/Featherview/ViewerView.swift \
  Tests/FeatherviewCoreTests/AppSettingsTests.swift Tests/FeatherviewCoreTests/ViewerKeyTests.swift
git commit -m "feat: settings keys with the spec's defaults, overlay text template, P for Settings"
```

---

### Task 2: Hidden files, folder tree and the folder chooser state

**Files:**
- Modify: `Sources/FeatherviewCore/FolderScanner.swift`
- Create: `Sources/FeatherviewCore/FolderTree.swift`
- Create: `Sources/FeatherviewCore/FolderChooser.swift`
- Test: `Tests/FeatherviewCoreTests/FolderScannerTests.swift` (append), `Tests/FeatherviewCoreTests/FolderTreeTests.swift`

**Interfaces:**
- Consumes: `pathKey(_:)` (internal), `FolderScanner.images(around:)`.
- Produces: `FolderScanner.images(around: URL, includeHidden: Bool = false) throws -> [URL]`;
  `FolderTree.subfolders(of: URL, includeHidden: Bool = false) -> [URL]`,
  `FolderTree.imageCount(in: URL, includeHidden: Bool = false) -> Int`,
  `FolderTree.parent(of: URL) -> URL?`;
  `struct FolderChooser` with `init(folder: URL, includeHidden: Bool = false)`, `folder`, `entries: [Entry]`,
  `selection: Int`, `selected: Entry`, `moveSelection(by:)`, `enter()`, `up()`;
  `enum FolderChooser.Entry { again(URL), parent(URL), subfolder(URL) }` with `url`.

Decided here (spec is silent): the chooser opens with its first subfolder selected (going deeper is
the usual next step), else the parent, else "this folder again"; after ← the folder we came from
is selected.

- [ ] **Step 1: Write the failing tests**

Append to `Tests/FeatherviewCoreTests/FolderScannerTests.swift`:

```swift
@Suite struct HiddenFilesTests {
    @Test func hiddenFilesAreListedWhenAsked() throws {
        let dir = try Fixtures.makeTempDir()
        try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 4, height: 4)
        try Fixtures.writeImage(to: dir.appendingPathComponent(".b.jpg"), width: 4, height: 4)
        #expect(try FolderScanner.images(around: dir).map(\.lastPathComponent) == ["a.jpg"])
        #expect(try FolderScanner.images(around: dir, includeHidden: true).map(\.lastPathComponent) == [".b.jpg", "a.jpg"])
    }
}
```

`Tests/FeatherviewCoreTests/FolderTreeTests.swift`:

```swift
import Foundation
import Testing
@testable import FeatherviewCore

/// root/ a/ (2 images)  b_empty/ (a text file)  c/ sub/  d2/  d10/  .hidden/  App.app/  link -> c  root1.jpg
private func makeTree() throws -> URL {
    let root = try Fixtures.makeTempDir()
    let manager = FileManager.default
    for folder in ["a", "b_empty", "c/sub", "d2", "d10", ".hidden", "App.app"] {
        try manager.createDirectory(at: root.appendingPathComponent(folder), withIntermediateDirectories: true)
    }
    try Fixtures.writeImage(to: root.appendingPathComponent("a/a1.jpg"), width: 4, height: 4)
    try Fixtures.writeImage(to: root.appendingPathComponent("a/a2.png"), width: 4, height: 4, type: .png)
    try Data("x".utf8).write(to: root.appendingPathComponent("b_empty/x.txt"))
    try Fixtures.writeImage(to: root.appendingPathComponent("root1.jpg"), width: 4, height: 4)
    try manager.createSymbolicLink(at: root.appendingPathComponent("link"),
                                   withDestinationURL: root.appendingPathComponent("c"))
    return root
}

@Suite struct FolderTreeTests {
    @Test func subfoldersInFinderOrderSkippingHiddenAndPackages() throws {
        let root = try makeTree()
        #expect(FolderTree.subfolders(of: root).map(\.lastPathComponent) == ["a", "b_empty", "c", "d2", "d10", "link"])
        #expect(FolderTree.subfolders(of: root, includeHidden: true).map(\.lastPathComponent).first == ".hidden")
    }

    @Test func imageCounts() throws {
        let root = try makeTree()
        #expect(FolderTree.imageCount(in: root.appendingPathComponent("a")) == 2)
        #expect(FolderTree.imageCount(in: root.appendingPathComponent("b_empty")) == 0)
        #expect(FolderTree.imageCount(in: root) == 1)
        #expect(FolderTree.imageCount(in: root.appendingPathComponent("missing")) == 0)
    }

    @Test func parentStopsAtRoot() throws {
        let root = try makeTree()
        #expect(FolderTree.parent(of: root.appendingPathComponent("a")).map(pathKey) == pathKey(root))
        #expect(FolderTree.parent(of: URL(fileURLWithPath: "/")) == nil)
    }
}

@Suite struct FolderChooserTests {
    @Test func startsOnTheFirstSubfolder() throws {
        let root = try makeTree()
        let chooser = FolderChooser(folder: root)
        #expect(chooser.entries.count == 8)  // again, parent, 6 subfolders
        #expect(chooser.entries[0] == .again(chooser.folder))
        guard case .parent = chooser.entries[1] else { Issue.record("no parent entry"); return }
        #expect(chooser.selected.url.lastPathComponent == "a")
    }

    @Test func withoutSubfoldersStartsOnTheParent() throws {
        let root = try makeTree()
        let chooser = FolderChooser(folder: root.appendingPathComponent("a"))
        #expect(chooser.entries.count == 2)
        #expect(pathKey(chooser.selected.url) == pathKey(root))
    }

    @Test func enterAndUpReturnToTheFolderWeCameFrom() throws {
        let root = try makeTree()
        var chooser = FolderChooser(folder: root)
        chooser.moveSelection(by: 2)  // a → c
        #expect(chooser.selected.url.lastPathComponent == "c")
        chooser.enter()
        #expect(chooser.folder.lastPathComponent == "c")
        #expect(chooser.selected.url.lastPathComponent == "sub")
        chooser.up()
        #expect(pathKey(chooser.folder) == pathKey(root))
        #expect(chooser.selected.url.lastPathComponent == "c")
    }

    @Test func enteringTheParentGoesUpAndAgainDoesNothing() throws {
        let root = try makeTree()
        var chooser = FolderChooser(folder: root.appendingPathComponent("d2"))
        chooser.moveSelection(by: -5)  // clamps at "again"
        chooser.enter()
        #expect(chooser.folder.lastPathComponent == "d2")
        chooser.moveSelection(by: 1)
        chooser.enter()
        #expect(pathKey(chooser.folder) == pathKey(root))
        #expect(chooser.selected.url.lastPathComponent == "d2")
        chooser.moveSelection(by: 99)
        #expect(chooser.selected.url.lastPathComponent == "link")
    }

    @Test func rootHasNoParentEntry() {
        var chooser = FolderChooser(folder: URL(fileURLWithPath: "/"))
        #expect(!chooser.entries.contains { if case .parent = $0 { true } else { false } })
        chooser.up()
        #expect(chooser.folder.path == "/")
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --filter 'HiddenFilesTests|FolderTreeTests|FolderChooserTests'`
Expected: compile errors (`includeHidden`, `FolderTree`, `FolderChooser` not found).

- [ ] **Step 3: Implement**

In `Sources/FeatherviewCore/FolderScanner.swift`, give `images(around:)` the parameter and pass it to the listing:

```swift
    /// Decodable images next to `url` (or inside it, if it is a folder), in Finder order.
    /// Hidden files are skipped unless `includeHidden` (Settings › Browsing).
    public static func images(around url: URL, includeHidden: Bool = false) throws -> [URL] {
```

```swift
                options: includeHidden ? [] : [.skipsHiddenFiles])
```

`Sources/FeatherviewCore/FolderTree.swift`:

```swift
import Foundation

/// Folders around the current one, for the folder chooser. Like `FolderScanner`, it never opens a file.
public enum FolderTree {
    /// Subfolders of `folder` in Finder order. Symlinked folders are followed; packages (`.app`,
    /// `.photoslibrary`) are skipped, as Finder shows them as files. Unreadable folders have none.
    public static func subfolders(of folder: URL, includeHidden: Bool = false) -> [URL] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: folder.resolvingSymlinksInPath(), includingPropertiesForKeys: keys,
            options: includeHidden ? [] : [.skipsHiddenFiles])
        else { return [] }
        return items
            .filter { item in
                // resourceValues on a symlink describes the link; resolve it to see a folder behind it.
                let values = try? item.resolvingSymlinksInPath().resourceValues(forKeys: Set(keys))
                return values?.isDirectory == true && values?.isPackage != true
            }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// Images directly inside `folder` (by extension, as the viewer would list them); 0 if unreadable.
    public static func imageCount(in folder: URL, includeHidden: Bool = false) -> Int {
        // FolderScanner treats a non-folder as a file and would count its parent's images.
        guard (try? folder.resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        else { return 0 }
        return (try? FolderScanner.images(around: folder, includeHidden: includeHidden).count) ?? 0
    }

    /// The parent folder, or nil at the root of the file system.
    public static func parent(of folder: URL) -> URL? {
        let resolved = folder.resolvingSymlinksInPath().standardizedFileURL
        let parent = resolved.deletingLastPathComponent().standardizedFileURL
        return parent.path == resolved.path ? nil : parent
    }
}
```

`Sources/FeatherviewCore/FolderChooser.swift`:

```swift
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter 'FolderScannerTests|HiddenFilesTests|FolderTreeTests|FolderChooserTests|ImageListTests'`
Expected: all pass (the milestone-1 scanner and list tests too: the default skips hidden files as before).

- [ ] **Step 5: Commit**

```bash
git add Sources/FeatherviewCore/FolderScanner.swift Sources/FeatherviewCore/FolderTree.swift \
  Sources/FeatherviewCore/FolderChooser.swift Tests/FeatherviewCoreTests/FolderScannerTests.swift \
  Tests/FeatherviewCoreTests/FolderTreeTests.swift
git commit -m "feat: folder tree and folder chooser state, optional hidden files"
```

---

### Task 3: Sidecar files and never-overwrite move / copy

**Files:**
- Create: `Sources/FeatherviewCore/Sidecars.swift`
- Create: `Sources/FeatherviewCore/FileMover.swift`
- Test: `Tests/FeatherviewCoreTests/FileMoverTests.swift` (suites `SidecarsTests`, `FileMoverTests`)

**Interfaces:**
- Consumes: `pathKey(_:)`, `Fixtures`.
- Produces: `Sidecars.extensions`, `Sidecars.files(for image: URL) -> [URL]`;
  `enum FileOperation { move, copy }`;
  `FileMover.transfer(_ file: URL, to folder: URL, operation: FileOperation, sidecars: [URL] = []) throws -> URL`
  (`@discardableResult`).

- [ ] **Step 1: Write the failing tests**

`Tests/FeatherviewCoreTests/FileMoverTests.swift`:

```swift
import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct SidecarsTests {
    @Test func findsSidecarsOfAnyCase() throws {
        let dir = try Fixtures.makeTempDir()
        let image = try Fixtures.writeImage(to: dir.appendingPathComponent("IMG_1.JPG"), width: 4, height: 4)
        for name in ["IMG_1.xmp", "img_1.AAE", "IMG_1.thm", "IMG_10.xmp", "IMG_1.txt", "IMG_1.jpg.xmp"] {
            try Data("x".utf8).write(to: dir.appendingPathComponent(name))
        }
        #expect(Sidecars.files(for: image).map(\.lastPathComponent) == ["IMG_1.thm", "IMG_1.xmp", "img_1.AAE"])
    }
}

@Suite struct FileMoverTests {
    @Test func movesIntoANewFolderWithSidecars() throws {
        let dir = try Fixtures.makeTempDir()
        let image = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 4, height: 4)
        let xmp = dir.appendingPathComponent("a.xmp")
        try Data("x".utf8).write(to: xmp)
        let dest = dir.appendingPathComponent("new/deeper")

        let moved = try FileMover.transfer(image, to: dest, operation: .move, sidecars: [xmp])
        #expect(moved.lastPathComponent == "a.jpg")
        #expect(FileManager.default.fileExists(atPath: dest.appendingPathComponent("a.xmp").path))
        #expect(!FileManager.default.fileExists(atPath: image.path))
        #expect(!FileManager.default.fileExists(atPath: xmp.path))
    }

    @Test func neverOverwritesAndKeepsSidecarsPaired() throws {
        let dir = try Fixtures.makeTempDir()
        let dest = dir.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let existing = try Fixtures.writeImage(to: dest.appendingPathComponent("a.jpg"), width: 9, height: 9)
        let before = try Data(contentsOf: existing)
        try Data("old".utf8).write(to: dest.appendingPathComponent("a 2.xmp"))  // " 2" is taken for the sidecar
        let image = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 4, height: 4)
        let xmp = dir.appendingPathComponent("a.xmp")
        try Data("new".utf8).write(to: xmp)

        let copied = try FileMover.transfer(image, to: dest, operation: .copy, sidecars: [xmp])
        #expect(copied.lastPathComponent == "a 3.jpg")
        #expect(try String(contentsOf: dest.appendingPathComponent("a 3.xmp"), encoding: .utf8) == "new")
        #expect(try String(contentsOf: dest.appendingPathComponent("a 2.xmp"), encoding: .utf8) == "old")
        #expect(try Data(contentsOf: existing) == before)
        #expect(FileManager.default.fileExists(atPath: image.path))  // a copy keeps the original
    }

    @Test func nameClashIgnoresCase() throws {
        let dir = try Fixtures.makeTempDir()
        let dest = dir.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        try Fixtures.writeImage(to: dest.appendingPathComponent("A.JPG"), width: 4, height: 4)
        let image = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 4, height: 4)
        #expect(try FileMover.transfer(image, to: dest, operation: .move).lastPathComponent == "a 2.jpg")
    }

    @Test func movingIntoItsOwnFolderChangesNothing() throws {
        let dir = try Fixtures.makeTempDir()
        let image = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 4, height: 4)
        #expect(try FileMover.transfer(image, to: dir, operation: .move) == image)
        #expect(try FolderScanner.images(around: dir).count == 1)
    }

    @Test func unwritableDestinationThrowsAndKeepsTheOriginal() throws {
        let dir = try Fixtures.makeTempDir()
        let image = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 4, height: 4)
        let locked = dir.appendingPathComponent("locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }

        #expect(throws: (any Error).self) { try FileMover.transfer(image, to: locked, operation: .move) }
        #expect(FileManager.default.fileExists(atPath: image.path))
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --filter 'SidecarsTests|FileMoverTests'`
Expected: compile errors (`Sidecars`, `FileMover` not found).

- [ ] **Step 3: Implement**

`Sources/FeatherviewCore/Sidecars.swift`:

```swift
import Foundation

/// Files that belong to an image and travel with it: `IMG_1.xmp`, `IMG_1.AAE`, `IMG_1.thm` for `IMG_1.JPG`.
public enum Sidecars {
    public static let extensions: Set<String> = ["xmp", "aae", "thm"]

    /// Sidecars next to `image`: same base name (any case), a sidecar extension (any case).
    /// Lists the folder once, so names keep their real case on case-insensitive volumes.
    public static func files(for image: URL) -> [URL] {
        let stem = image.deletingPathExtension().lastPathComponent.lowercased()
        let folder = image.deletingLastPathComponent()
        let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return items.filter { item in
            item.deletingPathExtension().lastPathComponent.lowercased() == stem
                && extensions.contains(item.pathExtension.lowercased())
        }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
```

`Sources/FeatherviewCore/FileMover.swift`:

```swift
import Foundation

public enum FileOperation: Sendable {
    case move, copy
}

public enum FileMover {
    /// Moves or copies `file` into `folder` (created if missing), with its `sidecars` under the same
    /// new base name. Never overwrites: if the name, or any sidecar's, is taken, " 2", " 3", … is
    /// appended. Moving into the folder the file is already in changes nothing.
    /// Returns where `file` ended up. Sidecars are best effort: one failing never undoes the image.
    @discardableResult
    public static func transfer(_ file: URL, to folder: URL, operation: FileOperation,
                                sidecars: [URL] = []) throws -> URL {
        let manager = FileManager.default
        if operation == .move, pathKey(folder) == pathKey(file.deletingLastPathComponent()) { return file }
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        let stem = freeStem(for: file, sidecars: sidecars, in: folder)
        let target = folder.appendingPathComponent(name(stem, file.pathExtension))
        // move/copyItem fail if the target exists, so a file created meanwhile is never overwritten.
        switch operation {
        case .move: try manager.moveItem(at: file, to: target)
        case .copy: try manager.copyItem(at: file, to: target)
        }
        for sidecar in sidecars {
            let sidecarTarget = folder.appendingPathComponent(name(stem, sidecar.pathExtension))
            // shortcut: a sidecar that fails to move stays behind silently; surface it if users report lost edits.
            switch operation {
            case .move: try? manager.moveItem(at: sidecar, to: sidecarTarget)
            case .copy: try? manager.copyItem(at: sidecar, to: sidecarTarget)
            }
        }
        return target
    }

    /// The first of "IMG_1", "IMG_1 2", "IMG_1 3", … free for the image and every sidecar.
    static func freeStem(for file: URL, sidecars: [URL], in folder: URL) -> String {
        let base = file.deletingPathExtension().lastPathComponent
        let extensions = [file.pathExtension] + sidecars.map(\.pathExtension)
        var number = 1
        while true {
            let stem = number == 1 ? base : "\(base) \(number)"
            let taken = extensions.contains { ext in
                FileManager.default.fileExists(atPath: folder.appendingPathComponent(name(stem, ext)).path)
            }
            if !taken { return stem }
            number += 1
        }
    }

    private static func name(_ stem: String, _ ext: String) -> String {
        ext.isEmpty ? stem : "\(stem).\(ext)"
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter 'SidecarsTests|FileMoverTests'`
Expected: all pass. `unwritableDestinationThrowsAndKeepsTheOriginal` fails when run as root; run as the user.

- [ ] **Step 5: Commit**

```bash
git add Sources/FeatherviewCore/Sidecars.swift Sources/FeatherviewCore/FileMover.swift \
  Tests/FeatherviewCoreTests/FileMoverTests.swift
git commit -m "feat: move and copy with sidecar files, never overwriting"
```

---

### Task 4: The 14 destination slots

**Files:**
- Create: `Sources/FeatherviewCore/DestinationSlots.swift`
- Test: `Tests/FeatherviewCoreTests/DestinationSlotsTests.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces: `struct DestinationSlots` with `static count = 14`, `static keys: [Character]` (1–9, 0, B–E),
  `static slot(forKey: Character) -> Int?`, `folders: [URL?]`, `lastUsed: Int`, `subscript(slot) -> URL?`
  (get/set), `init(folders:lastUsed:)`, `init(defaults: UserDefaults)`, `save(to: UserDefaults)`.

- [ ] **Step 1: Write the failing tests**

`Tests/FeatherviewCoreTests/DestinationSlotsTests.swift`:

```swift
import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct DestinationSlotsTests {
    @Test(arguments: [("1", 0), ("9", 8), ("0", 9), ("b", 10), ("E", 13), ("f", nil), ("a", nil)] as [(Character, Int?)])
    func keysPickSlots(_ key: Character, _ slot: Int?) {
        #expect(DestinationSlots.slot(forKey: key) == slot)
    }

    @Test func persistsAndPadsToFourteen() {
        let name = "featherview-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(DestinationSlots(defaults: defaults).folders == Array(repeating: nil, count: 14))

        var slots = DestinationSlots()
        slots[2] = URL(fileURLWithPath: "/Users/x/Pictures/Keep", isDirectory: true)
        slots.lastUsed = 2
        slots.save(to: defaults)
        let loaded = DestinationSlots(defaults: defaults)
        #expect(loaded == slots)
        #expect(loaded[2]?.path == "/Users/x/Pictures/Keep")
        #expect(DestinationSlots(lastUsed: 99).lastUsed == 13)
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --filter DestinationSlotsTests`
Expected: compile error (`DestinationSlots` not found).

- [ ] **Step 3: Implement**

`Sources/FeatherviewCore/DestinationSlots.swift`:

```swift
import Foundation

/// The 14 remembered folders for F7 (move) and F8 (copy), picked by a single key.
public struct DestinationSlots: Equatable, Sendable {
    public static let count = 14
    /// The key for each slot: 1–9, 0 for the 10th, then B, C, D, E.
    public static let keys: [Character] = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "B", "C", "D", "E"]
    static let defaultsKey = "destinationSlots"
    static let lastUsedKey = "destinationSlotLastUsed"

    public private(set) var folders: [URL?]
    /// The highlighted slot when the panel opens; Return uses it.
    public var lastUsed: Int

    public init(folders: [URL?] = [], lastUsed: Int = 0) {
        self.folders = Array((folders + Array(repeating: nil, count: Self.count)).prefix(Self.count))
        self.lastUsed = min(max(lastUsed, 0), Self.count - 1)
    }

    /// The slot a typed character picks (case-insensitive), or nil.
    public static func slot(forKey character: Character) -> Int? {
        keys.firstIndex { $0.lowercased() == character.lowercased() }
    }

    public subscript(slot: Int) -> URL? {
        get { folders[slot] }
        set { folders[slot] = newValue }
    }

    /// Reads the slots saved by `save(to:)`; missing or damaged data gives empty slots.
    public init(defaults: UserDefaults) {
        let paths = defaults.stringArray(forKey: Self.defaultsKey) ?? []
        self.init(folders: paths.map { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) },
                  lastUsed: defaults.integer(forKey: Self.lastUsedKey))
    }

    public func save(to defaults: UserDefaults) {
        defaults.set(folders.map { $0?.path ?? "" }, forKey: Self.defaultsKey)
        defaults.set(lastUsed, forKey: Self.lastUsedKey)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter DestinationSlotsTests`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/FeatherviewCore/DestinationSlots.swift Tests/FeatherviewCoreTests/DestinationSlotsTests.swift
git commit -m "feat: 14 remembered destination folders picked by a single key"
```

---

### Task 5: Pages of multi-page TIFFs

**Files:**
- Modify: `Sources/FeatherviewCore/ImageDecoder.swift`
- Modify: `Tests/FeatherviewCoreTests/Fixtures.swift`
- Test: `Tests/FeatherviewCoreTests/ImageDecoderTests.swift` (append)

**Interfaces:**
- Consumes: `ImageDecoder` (milestone 1).
- Produces: `ImageDecoder.pageCount(of: URL) -> Int` (TIFF only, else 1);
  `ImageDecoder.displaySize(of: URL, page: Int = 0) -> CGSize?`;
  `ImageDecoder.decode(_:maxPixelSize:halvingSteps:page:)` with `page: Int = 0`;
  `Fixtures.writeMultiPageTIFF(to:pages:width:height:) throws -> URL` (page n is `width + n` wide).

- [ ] **Step 1: Write the failing tests**

Add to `Fixtures` in `Tests/FeatherviewCoreTests/Fixtures.swift`:

```swift
    /// A TIFF with one solid page per colour (red, green, blue, …), each `width`×`height`.
    @discardableResult
    static func writeMultiPageTIFF(to url: URL, pages: Int, width: Int = 8, height: Int = 4) throws -> URL {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.tiff.identifier as CFString, pages, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        for page in 0..<pages {
            let context = CGContext(
                data: nil, width: width + page, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width + page, height: height))
            CGImageDestinationAddImage(dest, context.makeImage()!, nil)
        }
        guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
        return url
    }
```

Append to `Tests/FeatherviewCoreTests/ImageDecoderTests.swift`:

```swift
@Suite struct PageTests {
    @Test func multiPageTIFFHasPagesOthersHaveOne() throws {
        let dir = try Fixtures.makeTempDir()
        let tiff = try Fixtures.writeMultiPageTIFF(to: dir.appendingPathComponent("m.tif"), pages: 3)
        let jpeg = try Fixtures.writeImage(to: dir.appendingPathComponent("a.jpg"), width: 4, height: 4)
        #expect(ImageDecoder.pageCount(of: tiff) == 3)
        #expect(ImageDecoder.pageCount(of: jpeg) == 1)
        #expect(ImageDecoder.pageCount(of: dir.appendingPathComponent("missing.tif")) == 1)
    }

    @Test func decodesEachPage() throws {
        let dir = try Fixtures.makeTempDir()
        let tiff = try Fixtures.writeMultiPageTIFF(to: dir.appendingPathComponent("m.tif"), pages: 3)
        #expect(try ImageDecoder.decode(tiff, page: 2).width == 10)  // page n is 8 + n wide
        #expect(ImageDecoder.displaySize(of: tiff, page: 1)?.width == 9)
        #expect(throws: DecodeError.unreadable(tiff)) { try ImageDecoder.decode(tiff, page: 3) }
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --filter PageTests`
Expected: compile errors (`pageCount`, `page:` not found).

- [ ] **Step 3: Implement**

In `Sources/FeatherviewCore/ImageDecoder.swift`: `import UniformTypeIdentifiers`; add `pageCount`; give
`displaySize` and `decode` a `page` parameter and use it instead of index `0`:

```swift
    /// Pages of a multi-page TIFF; 1 for every other file, so GIF frames and HEIC image sequences
    /// are not browsed as pages (spec: GIF shows its first frame).
    public static func pageCount(of url: URL) -> Int {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let type = CGImageSourceGetType(source),
              UTType(type as String)?.conforms(to: .tiff) == true else { return 1 }
        return max(CGImageSourceGetCount(source), 1)
    }

    /// Pixel size as displayed, with EXIF orientation applied. nil if the file isn't a readable image.
    public static func displaySize(of url: URL, page: Int = 0) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, page, nil) as? [CFString: Any],
```

```swift
    /// `page` is a page of a multi-page TIFF (see `pageCount`).
    public static func decode(_ url: URL, maxPixelSize: Int? = nil, halvingSteps: Bool = false, page: Int = 0) throws -> CGImage {
        guard let size = displaySize(of: url, page: page),
```

```swift
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, page, options as CFDictionary)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter 'ImageDecoderTests|PageTests|ImageCacheTests'`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/FeatherviewCore/ImageDecoder.swift Tests/FeatherviewCoreTests/Fixtures.swift \
  Tests/FeatherviewCoreTests/ImageDecoderTests.swift
git commit -m "feat: page count and page decoding for multi-page TIFFs"
```

---
### Task 6: One window per file, menus for the focused window, the Settings window

**Files:**
- Modify: `Sources/Featherview/FeatherviewApp.swift` (whole file below)
- Modify: `Sources/Featherview/ViewerModel.swift`
- Modify: `Sources/Featherview/ViewerView.swift`
- Modify: `Sources/Featherview/BatchView.swift`
- Create: `Sources/Featherview/SettingsView.swift`
- Create: `Sources/FeatherviewCore/ViewerWindows.swift`, `Tests/FeatherviewCoreTests/ViewerWindowsTests.swift`
- Create: `Sources/FeatherviewCore/LastUsed.swift`, `Tests/FeatherviewCoreTests/LastUsedTests.swift`

**Interfaces:**
- Consumes: `AppSettings` (Task 1), `DestinationSlots` (Task 4), `PastEndBehavior`, `HexColor`.
- Produces (later tasks use these):
  - `ViewerWindows` (Core: `revealMain()`, `openExtra(_:)`, `install(revealMain:openExtra:)`; requests
    made before any window installs the openers wait and are sent on install; `viewerOpened()` /
    `viewerClosed()` count viewer windows on screen, `mainTakesFile(mainIsEmpty:)` says whether a file
    from Finder goes to the main viewer), `ExtraWindow` (Core: the extra window's value, a URL plus a
    fresh id per open), `LastUsed<Item>` (Core, `@Observable`: `current` is the item last `use(_:)`d,
    or `fallback` once that one is `close(_:)`d; strong until closed), `ViewerModel.windows: ViewerWindows`
    (static), `ViewerModel.main: ViewerModel` (static, the main viewer; `AppDelegate.viewer` is it),
    `ViewerModel.lastActive: LastUsed<ViewerModel>` (static `let`, falls back to `main`; read
    `lastActive.current`), `ViewerModel.window: NSWindow?` (weak),
    `ViewerModel.isFullScreen: Bool` (stored, set by the view, seeded from the window's style mask), `ViewerModel.emptyFolder: URL?`
    (declared here as `private(set) var emptyFolder: URL?`, set in Task 8).
  - `FocusedValues.viewer: ViewerModel?`; `ViewerCommands` with no stored model (uses `@FocusedValue`).
  - `WindowAccessor(onWindow: (NSWindow) -> Void)`.
  - Scenes: `Window` id `"viewer"`, `WindowGroup` id `"viewer-extra"` for `ExtraWindow`, `Window` id `"batch"`, `Settings`.

Behaviour: the main viewer window takes the file at launch, or when no viewer window is open (it
reopens); any later file from Finder (or several at once) opens its own viewer window with its own folder list (spec "Windows"). ⌘O, O and drag and
drop keep opening in the window they're used in: only the main viewer's `revealWindow` is set (by
the AppDelegate), so an extra window never raises or reopens the main one. Every window (main,
extra, Batch) installs the window openers when it appears, because state restoration may bring
back only one of them. Opening the same file twice gives two windows (each `ExtraWindow` has its
own id; SwiftUI only raises a window whose value is open). Menu commands act on the focused viewer
window; ⌘O with none focused uses the viewer used last, the main one at first and again once that
one's window closes.
"Use Viewer's Folder" in the batch window takes the viewer used last.

- [ ] **Step 0: `ViewerWindows` and `ExtraWindow` in FeatherviewCore, test first**

Tests: requests before install are sent once on install (a reveal once, extras in order); requests
after install go straight through; two `ExtraWindow`s for one URL differ, and one survives a JSON
round trip; `mainTakesFile` is true while the main viewer is empty or no viewer window is open.
Then `Sources/FeatherviewCore/ViewerWindows.swift` (see the file).
`LastUsed` tests: starts with the fallback; closing the one used last falls back; closing another
keeps it; views reading `current` are told when it changes. Then `Sources/FeatherviewCore/LastUsed.swift`.

- [ ] **Step 1: Replace `Sources/Featherview/FeatherviewApp.swift`**

```swift
import FeatherviewCore
import SwiftUI

@main
struct FeatherviewApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var batch = BatchModel()

    var body: some Scene {
        Window("Featherview", id: "viewer") {
            ViewerView(model: appDelegate.viewer)
                .modifier(OpensViewerWindows())
        }
        .commands { ViewerCommands() }

        // Files opened from Finder while the main viewer shows an image, each with its own folder list.
        WindowGroup("Featherview", id: "viewer-extra", for: ExtraWindow.self) { $window in
            ExtraViewer(url: window?.url)
                .modifier(OpensViewerWindows())
        }

        Window("Batch Convert", id: "batch") {
            BatchView(model: batch)
                .onAppear { appDelegate.isBusy = { batch.isRunning } }
                .modifier(OpensViewerWindows())
        }

        Settings {
            SettingsView()
        }
    }
}

/// Any window can open viewer windows: state restoration may bring back only the Batch window
/// or an extra viewer, and files from Finder still need the main window.
struct OpensViewerWindows: ViewModifier {
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.onAppear {
            ViewerModel.windows.install(revealMain: { [openWindow] in openWindow(id: "viewer") },
                                        openExtra: { [openWindow] in openWindow(id: "viewer-extra", value: $0) })
        }
    }
}

/// A viewer window of its own, opened for one file; restored windows reopen their file.
struct ExtraViewer: View {
    let url: URL?
    @State private var model = ViewerModel()

    var body: some View {
        ViewerView(model: model)
            .onAppear { if let url, model.list.current == nil { model.open(url) } }
            .onDisappear { ViewerModel.lastActive.close(model) }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let viewer = ViewerModel.main
    /// True while a batch runs: quitting then would stop it part-way. Set by the Batch window.
    var isBusy: () -> Bool = { false }

    func applicationWillFinishLaunching(_ notification: Notification) {
        AppSettings.registerDefaults()
        // AppKit hands Finder's files to application(_:open:) only after SwiftUI built the window
        // (~50 ms later); taking the open event here lets the image decode meanwhile.
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(openDocuments(_:withReply:)),
            forEventClass: AEEventClass(kCoreEventClass), andEventID: AEEventID(kAEOpenDocuments))
    }

    @objc private func openDocuments(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        guard let list = event.paramDescriptor(forKeyword: keyDirectObject) else { return }
        let urls = (1...max(list.numberOfItems, 1)).compactMap {
            list.atIndex($0)?.coerce(toDescriptorType: typeFileURL)?.fileURLValue
        }
        for (index, url) in urls.enumerated() {
            // The main window takes the first file while it has none (launch) or no viewer window is open;
            // every other file gets a window.
            let mainIsEmpty = viewer.list.current == nil && !viewer.isOpening && viewer.emptyFolder == nil
            if index == 0, ViewerModel.windows.mainTakesFile(mainIsEmpty: mainIsEmpty) {
                viewer.open(url)
            } else {
                ViewerModel.windows.openExtra(url)
            }
        }
    }

    // shortcut: once the batch ends with no window open the app stays running, until the user quits; fine for v1.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { !isBusy() }
}
```

- [ ] **Step 2: ViewerModel: window plumbing**

Change `revealWindow`'s comment and add after it:

```swift
    /// Brings this model's window back if it was closed. Only the main viewer sets it (AppDelegate):
    /// an extra window opening a file must not raise or reopen the main one.
    var revealWindow: () -> Void = {}

    /// Opens viewer windows for files from Finder; every window's view installs the openers.
    static let windows = ViewerWindows()
    /// The main viewer, owned here, not by a view, so a file from Finder starts decoding before any window exists.
    static let main: ViewerModel = {
        let viewer = ViewerModel()
        viewer.revealWindow = { ViewerModel.windows.revealMain() }
        return viewer
    }()
    /// The viewer the user last worked in, for ⌘O and "Use Viewer's Folder" from the batch window;
    /// the main one until another is used, and again once that one's window closes.
    static let lastActive = LastUsed(fallback: main)

    /// A folder opened directly that has no images: the view says so, ← / → still leave it.
    private(set) var emptyFolder: URL?
```

Replace `toggleFullScreen()` and the computed `isFullScreen` (they used `NSApp.keyWindow`, which is
wrong with several windows):

```swift
    /// The window showing this model; set by the view.
    weak var window: NSWindow?
    /// Kept up to date by the view from the window's full-screen notifications.
    var isFullScreen = false

    func toggleFullScreen() {
        window?.toggleFullScreen(nil)
    }
```

- [ ] **Step 3: ViewerView: focused value, window, full-screen state**

In `ViewerView`, add:

```swift
    @Environment(\.controlActiveState) private var activeState
    @AppStorage(AppSettings.rememberWindowFrame.key) private var rememberFrame = AppSettings.rememberWindowFrame.defaultValue
```

Add these modifiers to the body chain (after `.inspector { … }`):

```swift
        .focusedSceneValue(\.viewer, model)
        .onChange(of: activeState, initial: true) { if activeState == .key { ViewerModel.lastActive.use(model) } }
        .background(WindowAccessor { window in
            model.window = window
            // A restored or reopened window may already be in full screen; no didEnter notification follows.
            model.isFullScreen = window.styleMask.contains(.fullScreen)
            if !rememberFrame { window.setContentSize(NSSize(width: 960, height: 640)); window.center() }
        })
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { note in
            if note.object as? NSWindow === model.window { model.isFullScreen = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { note in
            if note.object as? NSWindow === model.window { model.isFullScreen = false }
        }
```

In `.onAppear`, remove `model.revealWindow = …` (`ViewerModel.main` sets it for the main viewer only;
`OpensViewerWindows` installs the window openers) and add `ViewerModel.windows.viewerOpened()`; add
`.onDisappear { ViewerModel.windows.viewerClosed() }` after it.

In `handle(_:)`, minimise this window, not whichever is key: `case .minimize: model.window?.miniaturize(nil)`.

Add below `ViewerView`:

```swift
/// Reports the hosting window once it exists.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { if let window = view.window { onWindow(window) } }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

extension FocusedValues {
    /// The viewer of the focused window; menu commands act on it.
    @Entry var viewer: ViewerModel?
}
```

Replace `ViewerCommands` so it acts on the focused viewer (the same items as before; Tasks 8–10 add more):

```swift
struct ViewerCommands: Commands {
    @FocusedValue(\.viewer) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open…  (O)") { (model ?? ViewerModel.lastActive.current).showOpenPanel() }
                .keyboardShortcut("o")
        }
        CommandMenu("Image") {
            Button("Next  (→ or Space)") { model?.next() }
            Button("Previous  (← or ⌫)") { model?.previous() }
            Divider()
            Button("Rotate Right  (R)") { model?.rotate(.clockwise) }
            Button("Rotate Left  (L)") { model?.rotate(.counterClockwise) }
            Divider()
            // ⌘⌫ is handled by the viewer, not as a menu shortcut (see ViewerView.handle).
            Button("Move to Trash  (⌘⌫ or ⌦)") { model?.moveCurrentToTrash() }
            Button("Show Info  (I)") { model?.showInfo.toggle() }
            Divider()
            Button("Batch Convert…  (B)") { openWindow(id: "batch") }
                .keyboardShortcut("b")
        }
        CommandGroup(after: .toolbar) {
            Button("Zoom to Fit  (0)") { model?.setZoom(.fit) }
            Button("Actual Size  (1)") { model?.setZoom(.factor(1)) }
            Button("Zoom In  (+)") { model?.zoomIn() }
            Button("Zoom Out  (−)") { model?.zoomOut() }
        }
    }
}
```

- [ ] **Step 4: BatchView uses the last active viewer**

In `Sources/Featherview/BatchView.swift`: remove `let viewer: ViewerModel`, the
`@Environment(\.openWindow)` line and the `.onAppear { viewer.revealWindow = … }` modifier with
its comment (`OpensViewerWindows` on the Batch window covers that case now). Replace the button:

```swift
                    Button("Use Viewer's Folder") { model.inputs = ViewerModel.lastActive.current.list.urls }
                        .disabled(ViewerModel.lastActive.current.list.isEmpty)
```

- [ ] **Step 5: The Settings window**

`Sources/Featherview/SettingsView.swift` (every setting from spec "Settings" except Formats; the
tabs' controls take effect in Tasks 7–10, which read the same keys):

```swift
import FeatherviewCore
import SwiftUI

/// Settings (⌘, or P): every setting from spec "Settings" except Formats (milestone 3).
struct SettingsView: View {
    var body: some View {
        TabView {
            BrowsingSettings().tabItem { Label("Browsing", systemImage: "photo.on.rectangle") }
            ViewerSettings().tabItem { Label("Viewer", systemImage: "eye") }
            FullScreenSettings().tabItem { Label("Full Screen", systemImage: "arrow.up.left.and.arrow.down.right") }
            MoveCopySettings().tabItem { Label("Move / Copy", systemImage: "folder") }
            OpenWithSettings().tabItem { Label("Open With", systemImage: "arrow.up.forward.app") }
        }
        .frame(width: 520)
        .scenePadding()
    }
}

private struct BrowsingSettings: View {
    @AppStorage(AppSettings.pastEnd.key) private var pastEnd = AppSettings.pastEnd.defaultValue
    @AppStorage(AppSettings.showHiddenFiles.key) private var showHidden = AppSettings.showHiddenFiles.defaultValue
    @AppStorage(AppSettings.showNextAfterRemoval.key) private var showNext = AppSettings.showNextAfterRemoval.defaultValue
    @AppStorage(AppSettings.moveSidecars.key) private var sidecars = AppSettings.moveSidecars.defaultValue

    var body: some View {
        Form {
            Picker("Past the end of a folder:", selection: $pastEnd) {
                Text("Show the folder chooser").tag(PastEndBehavior.folderChooser.rawValue)
                Text("Start this folder again").tag(PastEndBehavior.loop.rawValue)
                Text("Stop").tag(PastEndBehavior.stop.rawValue)
            }
            Toggle("Show hidden files", isOn: $showHidden)
            Toggle("Show the next image after moving or trashing one", isOn: $showNext)
            Toggle("Move, copy and trash sidecar files (.xmp, .aae, .thm) with their image", isOn: $sidecars)
        }
    }
}

private struct ViewerSettings: View {
    @AppStorage(AppSettings.backgroundColor.key) private var backgroundHex = AppSettings.backgroundColor.defaultValue
    @AppStorage(AppSettings.checkerboard.key) private var checkerboard = AppSettings.checkerboard.defaultValue
    @AppStorage(AppSettings.rememberWindowFrame.key) private var rememberFrame = AppSettings.rememberWindowFrame.defaultValue
    @AppStorage(AppSettings.zoomStepPercent.key) private var zoomStep = AppSettings.zoomStepPercent.defaultValue

    /// The stored `#RRGGBB` as a colour for the picker; picks are stored back in sRGB.
    private var background: Binding<Color> {
        Binding {
            let c = HexColor.parse(backgroundHex) ?? (0, 0, 0)
            return Color(.sRGB, red: c.red, green: c.green, blue: c.blue)
        } set: { color in
            guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return }
            backgroundHex = HexColor.format(red: srgb.redComponent, green: srgb.greenComponent, blue: srgb.blueComponent)
        }
    }

    var body: some View {
        Form {
            ColorPicker("Background:", selection: background, supportsOpacity: false)
            Toggle("Checkerboard behind transparent images", isOn: $checkerboard)
            Toggle("Remember the window's size and position", isOn: $rememberFrame)
            Stepper(value: $zoomStep, in: 1...100) {
                Text("Zoom step: \(zoomStep) %")
            }
        }
    }
}

private struct FullScreenSettings: View {
    @AppStorage(AppSettings.showOverlay.key) private var showOverlay = AppSettings.showOverlay.defaultValue
    @AppStorage(AppSettings.overlayTemplate.key) private var template = AppSettings.overlayTemplate.defaultValue
    @AppStorage(AppSettings.hidePointer.key) private var hidePointer = AppSettings.hidePointer.defaultValue

    var body: some View {
        Form {
            Toggle("Show text over the image", isOn: $showOverlay)
            TextField("Text:", text: $template)
                .disabled(!showOverlay)
            Text("{name} {folder} {index} {count} {size} {date}")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Hide the pointer", isOn: $hidePointer)
        }
    }
}

private struct MoveCopySettings: View {
    @AppStorage(AppSettings.askBeforeMoveCopy.key) private var ask = AppSettings.askBeforeMoveCopy.defaultValue
    @State private var slots = DestinationSlots(defaults: .standard)

    var body: some View {
        Form {
            Toggle("Ask before each move or copy", isOn: $ask)
            Section("Folders for F7 (move) and F8 (copy)") {
                ForEach(0..<DestinationSlots.count, id: \.self) { slot in
                    LabeledContent(String(DestinationSlots.keys[slot])) {
                        Text(slots[slot]?.path ?? "Empty")
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(slots[slot] == nil ? .secondary : .primary)
                        Button("Choose…") { choose(slot) }
                        Button("Clear") { slots[slot] = nil; slots.save(to: .standard) }
                            .disabled(slots[slot] == nil)
                    }
                }
            }
        }
        // The viewer's panel may have changed the slots since this tab was built.
        .onAppear { slots = DestinationSlots(defaults: .standard) }
    }

    private func choose(_ slot: Int) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        slots[slot] = url
        slots.save(to: .standard)
    }
}

private struct OpenWithSettings: View {
    @AppStorage(AppSettings.openWith[0].key) private var app1 = ""
    @AppStorage(AppSettings.openWith[1].key) private var app2 = ""
    @AppStorage(AppSettings.openWith[2].key) private var app3 = ""

    var body: some View {
        Form {
            row("⌥1", $app1)
            row("⌥2", $app2)
            row("⌥3", $app3)
        }
    }

    private func row(_ key: String, _ path: Binding<String>) -> some View {
        LabeledContent(key) {
            Text(path.wrappedValue.isEmpty ? "None" : FileManager.default.displayName(atPath: path.wrappedValue))
                .foregroundStyle(path.wrappedValue.isEmpty ? .secondary : .primary)
            Button("Choose…") {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.application]
                panel.directoryURL = URL(fileURLWithPath: "/Applications")
                if panel.runModal() == .OK, let url = panel.url { path.wrappedValue = url.path }
            }
            Button("Clear") { path.wrappedValue = "" }
                .disabled(path.wrappedValue.isEmpty)
        }
    }
}
```

- [ ] **Step 6: Build and check**

Run: `swift build && swift test && scripts/bundle.sh debug`
Expected: builds, all tests pass. Then by hand: `open -a build/Featherview.app <a.jpg>` shows it in
the main window; `open -a build/Featherview.app <b.jpg in another folder>` opens a second window
with its own title and position; ⌘, and P open Settings; ⌘B and "Use Viewer's Folder" take the
images of the window used last.

- [ ] **Step 7: Commit**

```bash
git add Sources/Featherview
git commit -m "feat: a viewer window per file from Finder, menus for the focused window, Settings window"
```

---

### Task 7: The image canvas: drag and arrow keys pan, Return and double-click, viewer settings

**Files:**
- Create: `Sources/Featherview/ImageCanvas.swift`
- Modify: `Sources/Featherview/ViewerView.swift`
- Modify: `Sources/Featherview/ViewerModel.swift`

**Interfaces:**
- Consumes: `AppSettings` (Task 1), `HexColor`, `OverlayTemplate`, `ViewerModel.isFullScreen`/`window` (Task 6).
- Produces: `ImageCanvas(image:size:background:checkerboard:panController:onDoubleClick:)`;
  `PanController.pan(dx: CGFloat, dy: CGFloat) -> Bool` (false when the image fits along that axis).

Behaviour (spec "Mouse and trackpad", keys table, "Settings › Viewer / Full screen"): dragging pans
a zoomed image, the image following the pointer; two-finger scroll pans; arrows pan when the image
is larger than the window along that axis, otherwise ← ↑ go back and → ↓ go forward; Return and
double-click toggle full screen; background colour, checkerboard behind transparent images, zoom
step, remember window frame (Task 6), overlay text and hidden pointer in full screen; the toolbar
hides in full screen (Task 10 adds the toolbar).

- [ ] **Step 1: Create `Sources/Featherview/ImageCanvas.swift`**

```swift
import AppKit
import SwiftUI

/// Lets the viewer pan the canvas with the arrow keys; the canvas registers its scroll view here.
@MainActor
final class PanController {
    fileprivate weak var scrollView: NSScrollView?

    /// Pans one step if the image is larger than the view along that axis; false if it isn't
    /// (the arrow then changes images). `dx`/`dy` are -1, 0 or 1; physical directions, never mirrored.
    func pan(dx: CGFloat, dy: CGFloat) -> Bool {
        guard let scrollView, let document = scrollView.documentView else { return false }
        let visible = scrollView.contentView.bounds
        let canPan = dx != 0 ? document.frame.width > visible.width + 0.5 : document.frame.height > visible.height + 0.5
        guard canPan else { return false }
        let step: CGFloat = 80
        moveVisibleOrigin(scrollView, to: CGPoint(x: visible.origin.x + dx * step, y: visible.origin.y + dy * step))
        return true
    }
}

@MainActor
private func moveVisibleOrigin(_ scrollView: NSScrollView, to point: CGPoint) {
    let clip = scrollView.contentView
    clip.scroll(to: clip.constrainBoundsRect(NSRect(origin: point, size: clip.bounds.size)).origin)
    scrollView.reflectScrolledClipView(clip)
}

/// The image in an AppKit scroll view: two-finger scroll and dragging pan a zoomed image, a small
/// image sits centred, double-click toggles full screen. SwiftUI's ScrollView can't pan by dragging.
struct ImageCanvas: NSViewRepresentable {
    let image: CGImage
    /// Size in points the image is drawn at.
    let size: CGSize
    let background: NSColor
    let checkerboard: Bool
    let panController: PanController
    let onDoubleClick: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.contentView = CenteringClipView()
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = ImageLayerView()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        panController.scrollView = scrollView
        scrollView.backgroundColor = background
        guard let view = scrollView.documentView as? ImageLayerView else { return }
        view.onDoubleClick = onDoubleClick
        let oldSize = view.frame.size
        let visible = scrollView.contentView.bounds
        // Keep the point at the centre of the view where it was, so zooming doesn't jump to a corner.
        let centre = CGPoint(x: oldSize.width > 0 ? visible.midX / oldSize.width : 0.5,
                             y: oldSize.height > 0 ? visible.midY / oldSize.height : 0.5)
        view.show(image, checkerboard: checkerboard && image.hasAlpha, smooth: size.width < CGFloat(image.width) * 2)
        if oldSize != size {
            view.frame.size = size
            moveVisibleOrigin(scrollView, to: CGPoint(x: centre.x * size.width - visible.width / 2,
                                           y: centre.y * size.height - visible.height / 2))
        }
    }
}

private extension CGImage {
    var hasAlpha: Bool {
        ![.none, .noneSkipFirst, .noneSkipLast].contains(alphaInfo)
    }
}

/// Keeps a document smaller than the view in the middle instead of the bottom-left corner.
private final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let document = documentView else { return rect }
        if document.frame.width < rect.width { rect.origin.x = (document.frame.width - rect.width) / 2 }
        if document.frame.height < rect.height { rect.origin.y = (document.frame.height - rect.height) / 2 }
        return rect
    }
}

/// Draws the image with Core Animation and pans its scroll view while dragged.
private final class ImageLayerView: NSView {
    var onDoubleClick: () -> Void = {}
    private let imageLayer = CALayer()
    private var dragStart: (mouse: NSPoint, origin: NSPoint)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        imageLayer.contentsGravity = .resize
        imageLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        layer?.addSublayer(imageLayer)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    func show(_ image: CGImage, checkerboard: Bool, smooth: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)  // no fade between images
        if (imageLayer.contents as AnyObject?) !== image { imageLayer.contents = image }
        imageLayer.frame = bounds
        // Below 2× smooth; from 2× on, show the pixels.
        imageLayer.magnificationFilter = smooth ? .linear : .nearest
        imageLayer.minificationFilter = .trilinear
        layer?.backgroundColor = checkerboard ? Self.checkerColor : nil
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.frame = bounds
        CATransaction.commit()
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { return onDoubleClick() }
        guard let clip = enclosingScrollView?.contentView else { return }
        dragStart = (event.locationInWindow, clip.bounds.origin)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStart, let scrollView = enclosingScrollView else { return }
        // The image follows the pointer: moving the pointer right shows more of the left side.
        let dx = event.locationInWindow.x - dragStart.mouse.x
        let dy = event.locationInWindow.y - dragStart.mouse.y
        moveVisibleOrigin(scrollView, to: CGPoint(x: dragStart.origin.x - dx, y: dragStart.origin.y + dy))
    }

    override func mouseUp(with event: NSEvent) { dragStart = nil }

    /// Grey and white 8-point squares behind transparent images.
    private static let checkerColor: CGColor = {
        let tile = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            NSColor(white: 0.8, alpha: 1).setFill()
            rect.fill()
            NSColor.white.setFill()
            NSRect(x: 0, y: 0, width: 8, height: 8).fill()
            NSRect(x: 8, y: 8, width: 8, height: 8).fill()
            return true
        }
        return NSColor(patternImage: tile).cgColor
    }()
}
```

- [ ] **Step 2: ViewerView draws the canvas**

Add to `ViewerView`:

```swift
    @State private var panController = PanController()
    @AppStorage(AppSettings.backgroundColor.key) private var backgroundHex = AppSettings.backgroundColor.defaultValue
    @AppStorage(AppSettings.checkerboard.key) private var checkerboard = AppSettings.checkerboard.defaultValue
    @AppStorage(AppSettings.showOverlay.key) private var showOverlay = AppSettings.showOverlay.defaultValue
    @AppStorage(AppSettings.overlayTemplate.key) private var overlayTemplate = AppSettings.overlayTemplate.defaultValue
    @AppStorage(AppSettings.hidePointer.key) private var hidePointer = AppSettings.hidePointer.defaultValue

    private var background: Color { Color(nsColor: backgroundNSColor) }
    private var backgroundNSColor: NSColor {
        guard let c = HexColor.parse(backgroundHex) else { return .black }
        return NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: 1)
    }
```

In `body`, replace `Color.black.ignoresSafeArea()` and the `canvas(image)` call:

```swift
            background.ignoresSafeArea()
            if let image = model.image {
                ImageCanvas(image: image, size: drawSize(image), background: backgroundNSColor,
                            checkerboard: checkerboard, panController: panController,
                            onDoubleClick: model.toggleFullScreen)
```

Delete the old `canvas(_:)` function and add:

```swift
    /// Fit shrinks large images to the view and never enlarges small ones; a zoom factor scales the full-size decode.
    private func drawSize(_ image: CGImage) -> CGSize {
        let points = CGSize(width: CGFloat(image.width) / displayScale, height: CGFloat(image.height) / displayScale)
        switch model.zoom {
        case .fit:
            let scale = min(1, model.viewSize.width / max(points.width, 1), model.viewSize.height / max(points.height, 1))
            return CGSize(width: (points.width * scale).rounded(), height: (points.height * scale).rounded())
        case .factor(let factor):
            return CGSize(width: points.width * factor, height: points.height * factor)
        }
    }

    private func overlayValues(_ url: URL) -> [String: String] {
        var values = ["name": url.lastPathComponent,
                      "folder": url.deletingLastPathComponent().lastPathComponent,
                      "index": "\(model.list.index + 1)", "count": "\(model.list.urls.count)"]
        if let image = model.image { values["size"] = "\(image.width) × \(image.height)" }
        if let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
            values["date"] = date.formatted(date: .abbreviated, time: .shortened)
        }
        return values
    }
```

Add to the body chain (after the existing error overlay):

```swift
        .overlay(alignment: .bottomLeading) {
            if model.isFullScreen, showOverlay, let url = model.list.current {
                Text(OverlayTemplate.render(overlayTemplate, values: overlayValues(url)))
                    .font(.callout)
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(.black.opacity(0.5), in: .rect(cornerRadius: 4))
                    .padding()
            }
        }
        .onChange(of: model.image) {
            if model.isFullScreen, hidePointer { NSCursor.setHiddenUntilMouseMoves(true) }
        }
        .toolbar(model.isFullScreen ? .hidden : .automatic, for: .windowToolbar)
```

- [ ] **Step 3: Keys: arrows pan, Return toggles full screen**

In `handle(_:)`, replace the no-modifier `switch press.key` with:

```swift
        if modifiers.isEmpty {
            switch press.key {
            case .rightArrow: if !panController.pan(dx: 1, dy: 0) { model.next() }; return .handled
            case .leftArrow: if !panController.pan(dx: -1, dy: 0) { model.previous() }; return .handled
            case .downArrow: if !panController.pan(dx: 0, dy: 1) { model.next() }; return .handled
            case .upArrow: if !panController.pan(dx: 0, dy: -1) { model.previous() }; return .handled
            case .space, .pageDown: model.next(); return .handled
            case Self.backspace, .pageUp: model.previous(); return .handled
            case .home: model.first(); return .handled
            case .end: model.last(); return .handled
            case .deleteForward: model.moveCurrentToTrash(); return .handled
            case .return: model.toggleFullScreen(); return .handled
            case .escape:
                guard model.isFullScreen else { return .ignored }
                model.toggleFullScreen()
                return .handled
            default: break
            }
        }
```

(and delete the separate `if modifiers.isEmpty, press.key == .deleteForward` block above it).

- [ ] **Step 4: Zoom step from Settings**

In `ViewerModel`, replace `zoomIn()` / `zoomOut()`:

```swift
    /// Settings › Viewer › zoom step, 10 % by default (×1.1).
    private var zoomMultiplier: Double { 1 + Double(max(AppSettings.zoomStepPercent.value(), 1)) / 100 }
    func zoomIn() { stepZoom(by: zoomMultiplier) }
    func zoomOut() { stepZoom(by: 1 / zoomMultiplier) }
```

- [ ] **Step 5: Build and check**

Run: `swift build && swift test && scripts/bundle.sh debug`
Expected: builds, tests pass. By hand on a 4000×3000 JPEG: `1` then drag → the image follows the
pointer; arrows pan, and at `0` (fit) arrows change images; two-finger scroll pans; Return and
double-click toggle full screen; a small image sits centred; a transparent PNG shows a
checkerboard; Settings › Viewer background colour applies at once; full screen with "Show text"
shows the overlay; the pointer hides when the image changes in full screen.

- [ ] **Step 6: Commit**

```bash
git add Sources/Featherview
git commit -m "feat: drag and arrow keys pan, Return toggles full screen, viewer and full-screen settings"
```

---
### Task 8: Past the end of a folder, folders without images, pages, hidden files

**Files:**
- Create: `Sources/Featherview/FolderChooserView.swift`
- Modify: `Sources/Featherview/ViewerModel.swift`
- Modify: `Sources/Featherview/ViewerView.swift`

**Interfaces:**
- Consumes: `FolderChooser`, `FolderTree` (Task 2), `ImageDecoder.pageCount`/`decode(page:)` (Task 5),
  `AppSettings.pastEndBehavior`, `showHiddenFiles` (Task 1), `ViewerModel.emptyFolder` (Task 6).
- Produces: `ViewerModel.chooser: FolderChooser?`, `chooserCounts: [URL: Int]`, `chooserMove(_:)`,
  `chooserEnter()`, `chooserUp()`, `chooserOpen()`, `folder: URL?`, `page: Int`, `pageCount: Int`,
  `nextPage()`, `previousPage()`, `show(page: Int = 0)`.

Behaviour (spec "Moving past the end of a folder", "Settings › Browsing", keys table): past the
last image (→) or before the first (←) the chooser appears (or the folder starts again, or nothing
happens, per Settings); ↑ ↓ select, → / Space enter, ← up, Return opens, Esc cancels; image counts
appear as they're counted. A folder without images shows "No images in <folder>" and ← / → still
open the chooser. ⌥→ / ⌥← step pages of a multi-page TIFF; the title shows
`name — page 2 / 3 — 3 / 120`; every file opens on page 1.

- [ ] **Step 1: ViewerModel state**

Add after `emptyFolder`:

```swift
    /// Shown past either end of the folder (spec "Moving past the end of a folder").
    var chooser: FolderChooser?
    /// Image counts of the chooser's folders, filled in off the main thread as they are counted.
    private(set) var chooserCounts: [URL: Int] = [:]
    private var countTask: Task<Void, Never>?
    /// Page of a multi-page TIFF, 0-based; `pageCount` is 1 for every other file.
    private(set) var page = 0
    private(set) var pageCount = 1
```

Replace `title`:

```swift
    var title: String {
        guard let url = list.current else { return emptyFolder?.lastPathComponent ?? "Featherview" }
        // While the folder is listed the position isn't known yet; "1 / 1" would be wrong.
        if isOpening { return url.lastPathComponent }
        if pageCount > 1 { return "\(url.lastPathComponent) — page \(page + 1) / \(pageCount) — \(list.position)" }
        return "\(url.lastPathComponent) — \(list.position)"
    }

    /// The folder being browsed, also when it has no images.
    var folder: URL? { list.current?.deletingLastPathComponent() ?? emptyFolder }
```

- [ ] **Step 2: open() resets the chooser, honours hidden files, notices empty folders**

In `open(_:)`, after `isOpening = true`:

```swift
        chooser = nil
        emptyFolder = nil
        let includeHidden = AppSettings.showHiddenFiles.value()
```

pass it to the scanner, and remember an empty folder:

```swift
                    try FolderScanner.images(around: url, includeHidden: includeHidden)
```

```swift
                if isFolder {
                    emptyFolder = urls.isEmpty ? url : nil
                    show()
```

- [ ] **Step 3: Past the end, the chooser, pages**

Replace `next()` / `previous()` (and the "Milestone 2" comment above them):

```swift
    func next() {
        if list.next() { show() } else { pastEnd(forward: true) }
    }

    func previous() {
        if list.previous() { show() } else { pastEnd(forward: false) }
    }
```

Add:

```swift
    private func pastEnd(forward: Bool) {
        switch AppSettings.pastEndBehavior {
        case .stop: break
        case .loop:
            guard !list.isEmpty else { break }
            if forward { list.first() } else { list.last() }
            show()
        case .folderChooser:
            guard let folder else { break }
            chooser = FolderChooser(folder: folder, includeHidden: AppSettings.showHiddenFiles.value())
            countImages()
        }
    }

    /// Chooser keys: ↑ ↓ select, → / Space enter, ← up, Return opens, Esc cancels.
    func chooserMove(_ delta: Int) { chooser?.moveSelection(by: delta) }
    func chooserEnter() { chooser?.enter(); countImages() }
    func chooserUp() { chooser?.up(); countImages() }
    func chooserOpen() {
        guard let url = chooser?.selected.url else { return }
        chooser = nil
        open(url)
    }

    /// Counts the listed folders' images one by one, off the main thread; a big folder takes a while.
    private func countImages() {
        countTask?.cancel()
        guard let chooser else { return }
        let folders = chooser.entries.map(\.url).filter { chooserCounts[$0] == nil }
        let includeHidden = AppSettings.showHiddenFiles.value()
        countTask = Task {
            for folder in folders {
                let count = await Task.detached(priority: .utility) {
                    FolderTree.imageCount(in: folder, includeHidden: includeHidden)
                }.value
                guard !Task.isCancelled else { return }
                chooserCounts[folder] = count
            }
        }
    }

    /// ⌥→ / ⌥←: pages of a multi-page TIFF; nothing past either end.
    func nextPage() { if page + 1 < pageCount { page += 1; show(page: page) } }
    func previousPage() { if page > 0 { page -= 1; show(page: page) } }
```

In `setZoom(_:)`, keep the page: `if needsReload { show(page: page) }`. In `stepZoom(by:)`, measure
the page shown:

```swift
            let page = page
            let size = await Task.detached { ImageDecoder.displaySize(of: url, page: page) }.value
```

- [ ] **Step 4: show(page:) decodes pages and counts them**

Change the signature and start of `show()`:

```swift
    /// Shows `list.current` (page 0 unless `page` is given), then prefetches its neighbours so
    /// arrow keys feel instant.
    func show(page: Int = 0) {
        loadTask?.cancel()
        if page == 0 { self.page = 0 }
        guard let url = list.current else {
            pageCount = 1
```

Replace the decode in the load task:

```swift
                let decoded: CGImage
                if page > 0 {
                    // shortcut: pages after the first aren't cached or prefetched; cache them if people browse long TIFFs.
                    decoded = try await Task.detached(priority: .userInitiated) {
                        try ImageDecoder.decode(url, maxPixelSize: size, halvingSteps: true, page: page)
                    }.value
                } else {
                    decoded = size == nil
                        ? try await fullSizeCache.image(for: url, maxPixelSize: nil)
                        : try await cache.image(for: url, maxPixelSize: size)
                }
                guard !Task.isCancelled else { return }
                if page == 0 {
                    // Reads only the header; set before the image so the title never shows a stale count.
                    pageCount = await Task.detached { ImageDecoder.pageCount(of: url) }.value
                    guard !Task.isCancelled else { return }
                }
                image = decoded
```

In its `catch`, add `pageCount = 1` after `image = nil`; prefetch only for page 0:
`if let size, page == 0 { await cache.prefetch(neighbors, maxPixelSize: size) }`.

- [ ] **Step 5: The chooser view and its keys**

`Sources/Featherview/FolderChooserView.swift`:

```swift
import FeatherviewCore
import SwiftUI

/// The folder chooser over the viewer; keys are handled by ViewerView. A click selects and opens too.
struct FolderChooserView: View {
    let model: ViewerModel

    var body: some View {
        if let chooser = model.chooser {
            VStack(alignment: .leading, spacing: 0) {
                Text(chooser.folder.lastPathComponent)
                    .font(.headline)
                    .padding(.bottom, 6)
                ForEach(Array(chooser.entries.enumerated()), id: \.offset) { index, entry in
                    HStack {
                        Image(systemName: symbol(entry))
                        Text(label(entry))
                        Spacer()
                        if let count = model.chooserCounts[entry.url] {
                            Text(count, format: .number).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(index == chooser.selection ? Color.accentColor.opacity(0.35) : .clear,
                                in: .rect(cornerRadius: 4))
                    .contentShape(.rect)
                    .onTapGesture {
                        model.chooserMove(index - chooser.selection)
                        model.chooserOpen()
                    }
                }
                Text("→ open folder · ← up · Return show images · Esc cancel")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
            }
            .padding()
            .frame(width: 360)
            .background(.regularMaterial, in: .rect(cornerRadius: 10))
        }
    }

    private func label(_ entry: FolderChooser.Entry) -> String {
        switch entry {
        case .again: "This folder again"
        case .parent(let url): url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
        case .subfolder(let url): url.lastPathComponent
        }
    }

    private func symbol(_ entry: FolderChooser.Entry) -> String {
        switch entry {
        case .again: "arrow.counterclockwise"
        case .parent: "arrow.up"
        case .subfolder: "folder"
        }
    }
}
```

In `ViewerView.body`, after the error-message branch, show the empty-folder message:

```swift
            } else if let folder = model.emptyFolder {
                Text("No images in \(folder.lastPathComponent)").foregroundStyle(.secondary)
```

add the overlay:

```swift
        .overlay {
            if model.chooser != nil { FolderChooserView(model: model) }
        }
```

At the top of `handle(_:)`, right after `let modifiers = …`, route keys to the chooser while it shows,
and add the page keys:

```swift
        if model.chooser != nil { return handleChooser(press, modifiers) }
```

```swift
        if modifiers == .option {
            switch press.key {
            case .rightArrow: model.nextPage(); return .handled
            case .leftArrow: model.previousPage(); return .handled
            default: return .ignored
            }
        }
```

```swift
    /// While the folder chooser shows, keys drive it and nothing else.
    private func handleChooser(_ press: KeyPress, _ modifiers: EventModifiers) -> KeyPress.Result {
        guard modifiers.isEmpty else { return .handled }
        switch press.key {
        case .upArrow: model.chooserMove(-1)
        case .downArrow: model.chooserMove(1)
        case .rightArrow, .space: model.chooserEnter()
        case .leftArrow: model.chooserUp()
        case .return: model.chooserOpen()
        case .escape: model.chooser = nil
        default: break
        }
        return .handled
    }
```

Add to the "Image" menu in `ViewerCommands`, after Previous:

```swift
            Button("Next Page  (⌥→)") { model?.nextPage() }
                .disabled((model?.pageCount ?? 1) < 2)
            Button("Previous Page  (⌥←)") { model?.previousPage() }
                .disabled((model?.pageCount ?? 1) < 2)
```

In `AppDelegate.openDocuments` (Task 6) the main window counts as busy when it shows an empty
folder: the condition already reads `viewer.emptyFolder == nil`.

- [ ] **Step 6: Build and check**

Run: `swift build && swift test && scripts/bundle.sh debug`
Expected: builds, tests pass. By hand, with a tree like `root/{a (2 images), b_empty, c/sub}`:
→ past the last image of `a` shows the chooser on `a` with the parent selected (no subfolders);
← lists `root` with `a` selected; ↓ Return on `b_empty` shows "No images in b_empty"; → there
opens the chooser again; Esc closes it and leaves the image as it was. Counts appear next to
folders. Settings › Browsing "Start this folder again" loops, "Stop" does nothing. A 3-page TIFF
(make one with `Fixtures.writeMultiPageTIFF`'s code or Preview) steps with ⌥→ / ⌥← and the title shows the page;
an animated GIF shows no page. "Show hidden files" lists dot-files after reopening the folder.

- [ ] **Step 7: Commit**

```bash
git add Sources/Featherview
git commit -m "feat: folder chooser past either end, empty folders, multi-page TIFF pages"
```

---

### Task 9: F7 / F8 move and copy, sidecars, what shows after a removal

**Files:**
- Create: `Sources/Featherview/DestinationPanel.swift`
- Modify: `Sources/Featherview/ViewerModel.swift`
- Modify: `Sources/Featherview/ViewerView.swift`

**Interfaces:**
- Consumes: `FileMover`, `FileOperation`, `Sidecars` (Task 3), `DestinationSlots` (Task 4),
  `AppSettings.moveSidecars`, `showNextAfterRemoval`, `askBeforeMoveCopy` (Task 1).
- Produces: `ViewerModel.destinationPanel: FileOperation?`, `slots: DestinationSlots`,
  `showDestinations(_:)`, `transfer(to slot: Int)`, `chooseFolder(for slot: Int) -> Bool` (`@discardableResult`).

Behaviour (spec "Move / copy to folder", "Settings › Browsing / Move / copy"): F7 / F8 open the
panel; a slot key (1–9, 0, B–E) or Return on the highlighted slot moves / copies there; an empty
slot asks for its folder first; ↑ ↓ move the highlight; Esc closes. Missing folders are created,
nothing is overwritten (" 2"), sidecars travel along (setting, on). A copy leaves the viewer as it
is; a move — and Move to Trash — removes the file from the list and shows the next image, or with
"show the next image" off keeps the removed image on screen until the next key. "Ask before each
move or copy" confirms first.

- [ ] **Step 1: ViewerModel state and removal**

Add:

```swift
    /// F7 / F8: which panel is open, if any.
    var destinationPanel: FileOperation?
    var slots = DestinationSlots(defaults: .standard)
    /// With "show the next image" off, the removed image stays on screen until the next key.
    private var holdingRemoved = false
```

`holdingRemoved` must be cleared whenever something else shows: add `holdingRemoved = false` in
`open(_:)` (next to `emptyFolder = nil`) and in `show(page:)` (after `loadTask?.cancel()`). Let
`next()` / `previous()` honour it:

```swift
    func next() {
        if holdingRemoved { holdingRemoved = false; return show() }  // the image after the removed one
        if list.next() { show() } else { pastEnd(forward: true) }
    }

    func previous() {
        holdingRemoved = false
        if list.previous() { show() } else { pastEnd(forward: false) }
    }
```

Add the shared removal step, and use it in `moveCurrentToTrash()`, which now also trashes sidecars:

```swift
    /// After Trash or a move: the image leaves the list. With "show the next image" on (default) the
    /// next one shows; off, the removed image stays until the next key, which then shows the one after it.
    // shortcut: while the removed image is held, the title already names the next file; fine until someone notices.
    private func removeFromList(_ url: URL) async {
        await cache.remove(url)
        await fullSizeCache.remove(url)
        let wasCurrent = list.current == url
        let wasLast = list.index == list.urls.count - 1
        list.remove(url)
        guard wasCurrent else { return }
        if list.isEmpty { emptyFolder = url.deletingLastPathComponent() }
        if AppSettings.showNextAfterRemoval.value() || wasLast || list.isEmpty {
            show()
        } else {
            holdingRemoved = true
        }
    }
```

Replace the `do { … }` body in `moveCurrentToTrash()`:

```swift
            let withSidecars = AppSettings.moveSidecars.value()
            do {
                // Off the main thread: on a network or slow disk, trashing can take seconds.
                try await Task.detached(priority: .userInitiated) {
                    let sidecars = withSidecars ? Sidecars.files(for: url) : []
                    try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                    // shortcut: a sidecar that can't be trashed stays behind silently; report it if users ask.
                    for sidecar in sidecars { try? FileManager.default.trashItem(at: sidecar, resultingItemURL: nil) }
                }.value
                await removeFromList(url)
            } catch {
```

- [ ] **Step 2: ViewerModel move / copy**

```swift
    func showDestinations(_ operation: FileOperation) {
        if list.current != nil { destinationPanel = operation }
    }

    /// F7 / F8 with a slot picked: moves or copies the current file (and sidecars) there.
    /// A copy leaves the viewer as it is; a move removes the file from the list.
    func transfer(to slot: Int) {
        guard let operation = destinationPanel, let url = list.current, let folder = slots[slot] else { return }
        destinationPanel = nil
        slots.lastUsed = slot
        slots.save(to: .standard)
        if AppSettings.askBeforeMoveCopy.value(), !confirm(operation, url, folder) { return }
        let withSidecars = AppSettings.moveSidecars.value()
        let previous = rotateTask
        rotateTask = Task {
            await previous?.value
            guard list.urls.contains(url) else { return }
            do {
                _ = try await Task.detached(priority: .userInitiated) {
                    try FileMover.transfer(url, to: folder, operation: operation,
                                           sidecars: withSidecars ? Sidecars.files(for: url) : [])
                }.value
                if operation == .move { await removeFromList(url) }
            } catch {
                errorMessage = operation == .move
                    ? "Couldn't move \(url.lastPathComponent) to \(folder.lastPathComponent)"
                    : "Couldn't copy \(url.lastPathComponent) to \(folder.lastPathComponent)"
            }
        }
    }

    /// Lets the user pick a slot's folder; returns false if they cancelled.
    @discardableResult
    func chooseFolder(for slot: Int) -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = slots[slot]
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        slots[slot] = url
        slots.save(to: .standard)
        return true
    }

    private func confirm(_ operation: FileOperation, _ url: URL, _ folder: URL) -> Bool {
        let alert = NSAlert()
        alert.messageText = operation == .move
            ? "Move \(url.lastPathComponent) to \(folder.lastPathComponent)?"
            : "Copy \(url.lastPathComponent) to \(folder.lastPathComponent)?"
        alert.addButton(withTitle: operation == .move ? "Move" : "Copy")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
```

The move runs on `rotateTask`'s queue, like Trash, so a rotation still writing the file finishes first.

- [ ] **Step 3: The panel and its keys**

`Sources/Featherview/DestinationPanel.swift`:

```swift
import FeatherviewCore
import SwiftUI

/// F7 / F8: the 14 destination slots over the viewer. Keys are handled by ViewerView.
struct DestinationPanel: View {
    @Bindable var model: ViewerModel
    let operation: FileOperation

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(operation == .move ? "Move to Folder" : "Copy to Folder")
                .font(.headline)
                .padding(.bottom, 6)
            ForEach(0..<DestinationSlots.count, id: \.self) { slot in
                HStack {
                    Text(String(DestinationSlots.keys[slot]))
                        .monospaced()
                        .frame(width: 18)
                    Text(model.slots[slot]?.lastPathComponent ?? "Empty")
                        .foregroundStyle(model.slots[slot] == nil ? .secondary : .primary)
                        .help(model.slots[slot]?.path ?? "")
                    Spacer()
                    Button("Choose…") { model.chooseFolder(for: slot) }
                        .controlSize(.small)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(slot == model.slots.lastUsed ? Color.accentColor.opacity(0.35) : .clear,
                            in: .rect(cornerRadius: 4))
            }
            Text("Press a key to pick a folder · Return uses the highlighted one · Esc cancels")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
        }
        .padding()
        .frame(width: 400)
        .background(.regularMaterial, in: .rect(cornerRadius: 10))
    }
}
```

In `ViewerView`, add to the `.overlay { … }` from Task 8:

```swift
            if let operation = model.destinationPanel { DestinationPanel(model: model, operation: operation) }
```

Add the F-keys and route keys to the panel while it shows (after the chooser line in `handle`):

```swift
    private static let f7 = KeyEquivalent(Character(UnicodeScalar(NSF7FunctionKey)!))
    private static let f8 = KeyEquivalent(Character(UnicodeScalar(NSF8FunctionKey)!))
```

```swift
        if let operation = model.destinationPanel { return handleDestinations(press, modifiers, operation) }
```

in the no-modifier switch:

```swift
            case Self.f7: model.showDestinations(.move); return .handled
            case Self.f8: model.showDestinations(.copy); return .handled
```

and:

```swift
    /// While the F7 / F8 panel shows: a slot key picks a folder, ↑ ↓ and Return use the highlight.
    private func handleDestinations(_ press: KeyPress, _ modifiers: EventModifiers,
                                    _ operation: FileOperation) -> KeyPress.Result {
        guard modifiers.subtracting(.shift).isEmpty else { return .handled }
        switch press.key {
        case .escape: model.destinationPanel = nil
        case .upArrow: model.slots.lastUsed = max(model.slots.lastUsed - 1, 0)
        case .downArrow: model.slots.lastUsed = min(model.slots.lastUsed + 1, DestinationSlots.count - 1)
        case .return: pick(model.slots.lastUsed)
        default:
            if let character = press.characters.first, let slot = DestinationSlots.slot(forKey: character) {
                pick(slot)
            }
        }
        return .handled
    }

    /// An empty slot asks for its folder first.
    private func pick(_ slot: Int) {
        if model.slots[slot] == nil, !model.chooseFolder(for: slot) { return }
        model.transfer(to: slot)
    }
```

Add to the "Image" menu, before Move to Trash:

```swift
            Button("Move to Folder…  (F7)") { model?.showDestinations(.move) }
            Button("Copy to Folder…  (F8)") { model?.showDestinations(.copy) }
```

- [ ] **Step 4: Build and check**

Run: `swift build && swift test && scripts/bundle.sh debug`
Expected: builds, tests pass. By hand: F7, `1` on an empty slot asks for a folder, then the image
moves there and the next one shows; F7 Return moves the next one to the same folder; a second
image with the same name arrives as `name 2.jpg`; `IMG.xmp` travels with `IMG.jpg`; F8 copies and
the viewer stays; a read-only destination says "Couldn't move …" and the file stays; "Ask before"
confirms; "show the next image" off keeps the moved image until →.

- [ ] **Step 5: Commit**

```bash
git add Sources/Featherview
git commit -m "feat: F7 / F8 move and copy to 14 remembered folders, with sidecar files"
```

---

### Task 10: Toolbar, context menu, ⌘C, Show in Finder, Open With

**Files:**
- Create: `Sources/Featherview/ViewerToolbar.swift`
- Modify: `Sources/Featherview/ViewerModel.swift`
- Modify: `Sources/Featherview/ViewerView.swift`

**Interfaces:**
- Consumes: everything above; `AppSettings.openWith` (Task 1).
- Produces: `ViewerModel.copyImage()`, `openWith(_ index: Int)`, `showInFinder()`;
  `ViewerToolbar`, `ImageContextMenu`, `OpenWithMenu`.

Behaviour (spec "Toolbar", "Mouse and trackpad", "Menu commands", "Settings › Open with"): the
toolbar's buttons do what their keys do, tooltips name the key, page buttons only for multi-page
files, customizable and hideable through the View menu, hidden in full screen (Task 7). Right-click
opens Copy, Rotate, Move / Copy to Folder, Move to Trash, Show in Finder, Open With. ⌘C copies the
image at full resolution, upright; in other windows ⌘C / ⌘X / ⌘V / ⌘A keep working in text fields.
⌥1–⌥3 open the file in the apps set in Settings.

- [ ] **Step 1: ViewerModel actions**

```swift
    /// ⌘C: the current image at full resolution, upright, decoded off the main thread.
    func copyImage() {
        guard let url = list.current else { return }
        let page = page
        Task {
            do {
                let image = try await Task.detached(priority: .userInitiated) {
                    try ImageDecoder.decode(url, page: page)
                }.value
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.writeObjects([NSImage(cgImage: image, size: .zero)])
            } catch {
                errorMessage = "Couldn't copy \(url.lastPathComponent)"
            }
        }
    }

    /// ⌥1–⌥3: opens the current file in the app set in Settings › Open With.
    func openWith(_ index: Int) {
        let path = AppSettings.openWith[index].value()
        guard let url = list.current, !path.isEmpty else { return }
        NSWorkspace.shared.open([url], withApplicationAt: URL(fileURLWithPath: path),
                                configuration: NSWorkspace.OpenConfiguration())
    }

    func showInFinder() {
        if let url = list.current { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }
```

- [ ] **Step 2: Toolbar**

`Sources/Featherview/ViewerToolbar.swift`:

```swift
import SwiftUI

/// The standard Mac toolbar (spec "Toolbar"): each button does what its key does; the tooltip names the key.
/// Customizable, so View › Customize Toolbar… and Hide Toolbar work as in any Mac app.
struct ViewerToolbar: CustomizableToolbarContent {
    let model: ViewerModel

    var body: some CustomizableToolbarContent {
        ToolbarItem(id: "previous", placement: .navigation) {
            Button("Previous", systemImage: "chevron.backward") { model.previous() }.help("Previous image (←)")
        }
        ToolbarItem(id: "next", placement: .navigation) {
            Button("Next", systemImage: "chevron.forward") { model.next() }.help("Next image (→)")
        }
        if model.pageCount > 1 {
            ToolbarItem(id: "previousPage") {
                Button("Previous Page", systemImage: "arrow.up.doc") { model.previousPage() }.help("Previous page (⌥←)")
            }
            ToolbarItem(id: "nextPage") {
                Button("Next Page", systemImage: "arrow.down.doc") { model.nextPage() }.help("Next page (⌥→)")
            }
        }
        ToolbarItem(id: "rotateLeft") {
            Button("Rotate Left", systemImage: "rotate.left") { model.rotate(.counterClockwise) }.help("Rotate left (L)")
        }
        ToolbarItem(id: "rotateRight") {
            Button("Rotate Right", systemImage: "rotate.right") { model.rotate(.clockwise) }.help("Rotate right (R)")
        }
        ToolbarItem(id: "zoomOut") {
            Button("Zoom Out", systemImage: "minus.magnifyingglass") { model.zoomOut() }.help("Zoom out (−)")
        }
        ToolbarItem(id: "fit") {
            Button("Zoom to Fit", systemImage: "arrow.up.left.and.down.right.magnifyingglass") { model.setZoom(.fit) }
                .help("Zoom to fit (0)")
        }
        ToolbarItem(id: "zoomIn") {
            Button("Zoom In", systemImage: "plus.magnifyingglass") { model.zoomIn() }.help("Zoom in (+)")
        }
        ToolbarItem(id: "info") {
            Button("Info", systemImage: "info.circle") { model.showInfo.toggle() }.help("Show info (I)")
        }
        ToolbarItem(id: "trash") {
            Button("Move to Trash", systemImage: "trash") { model.moveCurrentToTrash() }.help("Move to Trash (⌘⌫)")
        }
    }
}
```

In `ViewerView.body`, before the `.toolbar(… for: .windowToolbar)` line from Task 7:

```swift
        .toolbar(id: "viewer") { ViewerToolbar(model: model) }
```

- [ ] **Step 3: Context menu and Open With menu**

On the canvas in `ViewerView.body`:

```swift
                ImageCanvas(…)
                    .contextMenu { ImageContextMenu(model: model) }
```

Add below `ViewerView`:

```swift
struct ImageContextMenu: View {
    let model: ViewerModel

    var body: some View {
        Button("Copy") { model.copyImage() }
        Divider()
        Button("Rotate Left") { model.rotate(.counterClockwise) }
        Button("Rotate Right") { model.rotate(.clockwise) }
        Divider()
        Button("Move to Folder…") { model.showDestinations(.move) }
        Button("Copy to Folder…") { model.showDestinations(.copy) }
        Button("Move to Trash") { model.moveCurrentToTrash() }
        Divider()
        Button("Show in Finder") { model.showInFinder() }
        OpenWithMenu(model: model)
    }
}

/// The apps set in Settings › Open With, by name.
struct OpenWithMenu: View {
    let model: ViewerModel?

    var body: some View {
        Menu("Open With") {
            ForEach(0..<3, id: \.self) { index in
                let path = AppSettings.openWith[index].value()
                Button(path.isEmpty ? "App \(index + 1) not set" : FileManager.default.displayName(atPath: path)) {
                    model?.openWith(index)
                }
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .option)
                .disabled(path.isEmpty || model?.list.current == nil)
            }
        }
    }
}
```

If Task 11 finds that a right-click over the canvas doesn't open the menu (AppKit takes the event
before SwiftUI), set the menu in AppKit instead: override `menu(for:)` in `ImageLayerView` and build
an `NSMenu` from the same actions, passed in through `ImageCanvas` like `onDoubleClick`.

- [ ] **Step 4: Menus: Copy, Show in Finder, Open With**

In `ViewerCommands.body`, add the pasteboard group (it replaces the standard one so ⌘C copies the
image in a viewer; elsewhere every item sends the standard action down the responder chain):

```swift
        CommandGroup(replacing: .pasteboard) {
            // Text fields (batch window) keep their own Copy and Paste: this group only acts on a viewer.
            Button("Copy") {
                if let model { model.copyImage() } else { NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil) }
            }
            .keyboardShortcut("c")
            Button("Cut") { NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil) }
                .keyboardShortcut("x")
            Button("Paste") { NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil) }
                .keyboardShortcut("v")
            Button("Select All") { NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil) }
                .keyboardShortcut("a")
        }
```

and to the "Image" menu, after Move to Trash:

```swift
            Button("Show in Finder") { model?.showInFinder() }
            OpenWithMenu(model: model)
```

- [ ] **Step 5: Build and check**

Run: `swift build && swift test && scripts/bundle.sh debug`
Expected: builds, tests pass. By hand: toolbar buttons work, page buttons appear on a 3-page TIFF
only, View › Customize Toolbar… works and a removed button stays removed after relaunch, View ›
Hide Toolbar is remembered; right-click shows the menu and each item works; ⌘C then Preview › File
› New from Clipboard shows the full-size upright image; ⌘C / ⌘V in the batch window's pattern field
copy and paste text; ⌥1 opens the file in the app set in Settings › Open With.

- [ ] **Step 6: Commit**

```bash
git add Sources/Featherview
git commit -m "feat: toolbar, context menu, copy image, Show in Finder, Open With"
```

---

### Task 11: Manual QA against the spec and the performance budgets

**Files:** `docs/roadmap.md`, this plan (status), `docs/spec.md` only if the maintainer changes a
decision.

Run with the maintainer (the `run-featherview` skill covers building, sample folders and timings;
measure with a release build, `scripts/bundle.sh`).

- [ ] **Step 1:** Every "Build and check" list of Tasks 6–10 again on the release build.
- [ ] **Step 2:** Budgets (`AGENTS.md`): cold launch with a 12 MP JPEG < 350 ms; prefetched next
  < 16 ms; not prefetched < 150 ms; 10,000-file folder < 500 ms to first image. Compare with
  milestone 1's numbers (320 ms, 9 ms, 314 ms); a regression is a bug. The AppKit canvas is the
  likeliest cause if swap times grow: check with Instruments (Time Profiler).
- [ ] **Step 3:** Memory while browsing stays bounded (Activity Monitor, 100 images forward and back).
- [ ] **Step 4:** Folder chooser on a folder with 1,000 subfolders and on `/`: appears at once,
  counts fill in, keys stay responsive.
- [ ] **Step 5:** Two windows on the same folder: trash an image in one; in the other, reaching it
  says "Can't open <name>" and browsing continues.
- [ ] **Step 6:** Launch by opening three files from Finder at once: three windows, each on its file.
- [ ] **Step 7:** Batch window: ⌘C, ⌘X, ⌘V, ⌘A in the rename pattern field act on the text; R, L,
  F, space typed there go into the field, not to a viewer.
- [ ] **Step 8:** Settings window: same for the overlay text field; every setting takes effect
  without a relaunch (folder-related ones on the next folder opened).
- [ ] **Step 9:** Right-to-left check is milestone 6; skip.
- [ ] **Step 10:** Mark this plan done and milestone 2 done in `docs/roadmap.md`; commit
  `docs: milestone 2 done after manual QA`.
