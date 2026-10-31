# Milestone 22: Photos library Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: run with the `plan-wave` workflow, wave by wave:
> Wave 1 = Tasks 1, 2 and 7 (independent), Wave 2 = Tasks 3 and 4 (both need Task 1's
> `PhotosLocation` and `PhotosText`), Wave 3 = Task 5, Wave 4 = Tasks 6 and 8, Wave 5 = Task 9.
> Task 10 needs the screen and waits for the maintainer's go. Steps use checkbox
> (`- [ ]`) syntax for tracking.

**Goal:** Browse Apple's Photos library like a folder (File › Open from Photos…, ⇧⌘O), take pictures
dragged in from Photos, and batch convert from the library or into it, without changing anything in it.

**Architecture:** A library picture is a URL with its own scheme (`featherview-photos://`), so
`ImageList`, the caches, the grid, prefetch and Compare keep working on URLs unchanged; the album is
the URL's "folder". Every place that reads a file by URL either routes that scheme to a hook the app
sets at launch (as `ImageEncoder.jxlEncoder` today) or is switched off by `ViewerAvailability` for
library pictures. PhotoKit lives in a new target `FeatherviewPhotos` (no UI, linked only by the app and
the bench): fit and grid pictures from `PHImageManager` at the needed size, the current version's file
fetched into a cache folder for everything that needs a real file (zoom, EXIF, F8, Save As, ⌘C, batch).

**Tech Stack:** Swift 6, PhotoKit (`PHPhotoLibrary`, `PHAsset`, `PHAssetCollection`,
`PHCachingImageManager`, `PHAssetResourceManager`, `PHAssetCreationRequest`), AppKit
(`NSFilePromiseReceiver`), SwiftUI sheet, Swift Testing.

**Spec:** `docs/spec.md` "Photos library" (under Viewer) and "Output" › Name card ("Photos library"
destination). Roadmap: `docs/roadmap.md` › Next version › Photos library.

## Global Constraints

- Swift 6 strict concurrency; PhotoKit objects (`PHAsset`, `PHFetchResult`) never cross actors: only
  local identifiers (`String`) and `PhotosLocation` URLs do.
- Nothing calls PhotoKit before the person first chooses Open from Photos…, drops onto the batch
  window's Photos destination, or starts such a batch (spike 2026-10-26: linking Photos.framework adds
  no measurable launch time, median 70.2 vs 71.8 ms over 150 interleaved runs, minimum equal; so the
  framework is linked normally). Launch budget < 410 ms unchanged.
- Budgets (AGENTS.md, new row added in Task 9): album of 10,000 to first picture < 500 ms; prefetched
  next / previous ≈ 20 ms; not prefetched < 150 ms for local originals; grid budgets as for folders.
- Never change the library: no `PHAssetChangeRequest` except `deleteAssets` (Delete, system prompt)
  and `PHAssetCreationRequest` (batch destination, add-only access).
- Cache folder `~/Library/Caches/net.mynetx.featherview/Photos` (fetched files, one subfolder per
  asset) and `…/Dropped/<n>` (drops); both emptied at launch (off the main thread, after the first
  image) and at quit.
- Info.plist gets `NSPhotoLibraryUsageDescription` "Featherview shows and converts pictures from your
  Photos library." and `NSPhotoLibraryAddUsageDescription` "Featherview adds converted pictures to
  your Photos library."; both translated in `Resources/InfoPlist.xcstrings`.
- User-facing text translatable, every new key in all 30 languages of `Resources/Localizable.xcstrings`
  (run `scripts/strings.sh`, then translate). Exact copy is the spec's.
- TDD for FeatherviewCore. Tokens only from `Theme.swift`. Leading/trailing. Comments describe code as it is.

## Review Focus

1. A `featherview-photos:` URL reaching code that touches the disk by path (`FileManager.fileExists`
   in `becameActive`, `FolderWatch`, `FileInfo.isCurrent`, `pathKey`, Recent Files, the batch input
   scan): the picture must never be treated as deleted and dropped from the list, and nothing may
   be written next to it — Task 1 `libraryURLsHaveNoFilePath`; Task 6 audits every
   `FileManager`/`resourceValues`/`fileExists` call in `Sources/Featherview/Viewer` and routes or skips
   library URLs, with a test where Core owns the call.
2. Batch from library pictures with "Next to the originals" (the default): output must never land in
   the cache folder, which is emptied at quit — Task 4 `libraryInputsNeedADestination`.
3. Two pictures in an album with the same original file name (IMG_0001.HEIC from two cameras): each
   keeps its own URL, cached file and grid cell; F8 of both into one folder gives "IMG_0001 2.HEIC" —
   Task 1 `sameNameDifferentAssets`; Task 5 fetches into a per-asset subfolder.
4. Access denied, or limited, or revoked in System Settings while an album is open: the sheet explains
   with the spec's sentences, an open album keeps what is already shown and the next decode fails as
   one bad file ("Can't open IMG_1234.HEIC"), never a crash or a stuck spinner — Task 5 maps
   `PHPhotosError.accessUserDenied` to `DecodeError.unreadable`; Task 6 sheet states.
5. A picture deleted in Photos while it is listed: like a file trashed in Finder, the next decode
   fails as one bad file and Refresh (F5) removes it — Task 5 `decode` throws for a missing asset;
   Task 6 Refresh re-fetches.

---

### Task 1: `PhotosLocation`, album rules and texts (Core)

**Files:**
- Create: `Sources/FeatherviewCore/Viewer/PhotosLocation.swift`
- Test: `Tests/FeatherviewCoreTests/Viewer/PhotosLocationTests.swift`

**Interfaces:**
- Produces:
  - `public enum PhotosLocation` with `static let scheme = "featherview-photos"`,
    `static func url(album: String, asset: String) -> URL`, `static func albumURL(_ album: String) -> URL`,
    `static func album(of url: URL) -> String?`, `static func asset(of url: URL) -> String?`,
    `static func isLibrary(_ url: URL) -> Bool` (scheme only, never the disk).
    `album` is a `PHAssetCollection.localIdentifier` or `"library"`; identifiers contain `/`
    (`"6A1F…-UUID/L0/001"`), which is percent-encoded inside one path component.
  - `public enum PhotosAlbumKind: Sendable { case library, favorites, recents, mediaType, userAlbum }`
    with `var opensAtEnd: Bool` (library, recents, mediaType: true).
  - `public struct PhotosAlbumRow: Equatable, Sendable, Identifiable { id: String; name: String;
    folders: [String]; kind: PhotosAlbumKind; count: Int? }`
  - `public enum PhotosSheet { static func sections(_ rows: [PhotosAlbumRow]) -> [PhotosSheet.Section] }`,
    `struct Section: Equatable, Sendable { title: String?; rows: [PhotosAlbumRow] }`: first section
    (no title) Library, Favorites, Recents in that order; "Media Types"; "My Albums" (input order kept);
    empty sections left out. `static func subtitle(_ row: PhotosAlbumRow) -> String?`: folders joined
    with " › ", nil without folders.
  - `public enum PhotosText` with the spec's sentences: `denied`, `deniedHelp`, `downloading`,
    `cantDownload(name:)`, `needsDestination`, `cantImport(format:)`, `cantAdd(name:)` (all
    `String(localized:)`).

- [ ] **Step 1: Write the failing tests**

```swift
@Test func roundTripsIdentifiersWithSlashes() {
    let url = PhotosLocation.url(album: "AB12/L0/040", asset: "6A1F-99/L0/001")
    #expect(PhotosLocation.album(of: url) == "AB12/L0/040")
    #expect(PhotosLocation.asset(of: url) == "6A1F-99/L0/001")
    #expect(url.deletingLastPathComponent() == PhotosLocation.albumURL("AB12/L0/040"))
}
@Test func libraryURLsHaveNoFilePath() {
    let url = PhotosLocation.url(album: "library", asset: "X/L0/001")
    #expect(PhotosLocation.isLibrary(url) && !url.isFileURL)
    #expect(!PhotosLocation.isLibrary(URL(fileURLWithPath: "/tmp/featherview-photos/a.jpg")))
    #expect(PhotosLocation.asset(of: URL(fileURLWithPath: "/tmp/a.jpg")) == nil)
}
@Test func imageListKeepsTheCurrentLibraryPicture() {
    let urls = (1...3).map { PhotosLocation.url(album: "library", asset: "A\($0)/L0/001") }
    #expect(ImageList(urls: urls, current: urls[2]).index == 2)
}
@Test func sameNameDifferentAssets() {
    let a = PhotosLocation.url(album: "library", asset: "A/L0/001")
    let b = PhotosLocation.url(album: "library", asset: "B/L0/001")
    #expect(a != b && Set([a, b]).count == 2)
}
@Test func sectionsInSheetOrder() { /* rows given as userAlbum, recents, mediaType, library, favorites:
    sections == [nil: library, favorites, recents], ["Media Types": mediaType], ["My Albums": userAlbum];
    no media types → two sections */ }
@Test func opensAtEnd() { #expect(PhotosAlbumKind.library.opensAtEnd && PhotosAlbumKind.recents.opensAtEnd
    && PhotosAlbumKind.mediaType.opensAtEnd && !PhotosAlbumKind.userAlbum.opensAtEnd && !PhotosAlbumKind.favorites.opensAtEnd) }
@Test func subtitleJoinsFolders() { /* ["Trips", "2025"] → "Trips › 2025"; [] → nil */ }
```

- [ ] **Step 2:** `swift test --filter PhotosLocationTests` → fails (types missing).
- [ ] **Step 3:** Implement. Build URLs with `URLComponents` (`percentEncodedPath`, `/` in an
  identifier as `%2F`); parse from `percentEncodedPath` split on `/`, never from `lastPathComponent`
  (it decodes `%2F`). Host `library`.
- [ ] **Step 4:** `swift test --filter PhotosLocationTests` → passes.
- [ ] **Step 5:** Commit `feat: Photos library locations and album rules in Core`.

### Task 2: Read-only availability for library pictures (Core)

**Files:**
- Modify: `Sources/FeatherviewCore/Viewer/ViewerAvailability.swift`
- Test: `Tests/FeatherviewCoreTests/Viewer/ViewerAvailabilityTests.swift`

**Interfaces:**
- Produces: `ViewerState.isLibrary: Bool` (init parameter, default false); new
  `ViewerAvailability.canEditFile` (rotate, flip, Rename, Move to Folder F7: `canChangeFile && !isLibrary`)
  and `ViewerAvailability.canSort` (`!isLibrary`). With `isLibrary`: `canSetDesktop`, `canAdjustDate`,
  `canShowInFinder`, `canOpenWith`, `canFollow` false; `canChangeFile` (Delete, F8, Save As, Compare)
  and `canRefresh` unchanged; `pastEnd` `.folderChooser` acts as `.stop`.

- [ ] **Step 1: Failing tests** `libraryIsReadOnly` (state with `hasCurrent`, `hasFolder`, `isLibrary`:
  the five flags above false, `canEditFile` and `canSort` false, `canChangeFile`, `canSaveAs`,
  `canCompare`, `canRefresh`, `canCopy`, `canBatch` true), `libraryChooserStopsAtTheEnds`
  (`pastEnd: .folderChooser`, index 4 of 5: `canGoForward` false; `.loop`: true),
  `filesStillEditable` (same state without `isLibrary`: `canEditFile` true, `canSort` true).
- [ ] **Step 2:** `swift test --filter ViewerAvailabilityTests` → fails.
- [ ] **Step 3:** Implement in `ViewerAvailability.init(_:)`.
- [ ] **Step 4:** Tests pass (all of `ViewerAvailabilityTests`).
- [ ] **Step 5:** Commit `feat: library pictures are read-only in the viewer's availability`.

### Task 3: Library hook in the decoder and status line (Core)

**Files:**
- Modify: `Sources/FeatherviewCore/Imaging/ImageDecoder.swift`, `Sources/FeatherviewCore/Imaging/ImageCache.swift`,
  `Sources/FeatherviewCore/Viewer/FileInfo.swift`, `Sources/FeatherviewCore/Viewer/StatusLine.swift`
- Test: `Tests/FeatherviewCoreTests/Imaging/LibraryDecodeTests.swift` (`@Suite(.serialized)`; sets and
  clears the hook), `Tests/FeatherviewCoreTests/Viewer/StatusLineTests.swift`

**Interfaces:**
- Consumes: Task 1 (`PhotosLocation.isLibrary`).
- Produces:
  - `public protocol LibraryImages: Sendable` with
    `func image(_ url: URL, target: DecodeTarget, colorSpace: CGColorSpace?) throws -> CGImage` (blocking,
    runs on `DecodeQueue` threads like ImageIO), `func info(_ url: URL) -> FileInfo` (pixel size,
    `modified` = creation date, `bytes` nil, `values` empty), `func file(_ url: URL) throws -> URL`
    (the current version fetched into the cache folder; blocking).
  - `ImageDecoder.library: (any LibraryImages)?` — `nonisolated(unsafe) public static var`, set once at
    launch, like `ImageEncoder.jxlEncoder`.
  - Library URLs: `ImageCache.image(for:target:)` calls `library.image` for `.fit` and `.thumbnail`, and
    `ImageDecoder.decode(library.file(url), …)` for `.full` and `.step`; `ImageDecoder.pageCount` → 1;
    `ImageDecoder.displaySize` → `library.info(url).pixelSize`; `FileInfo.read(url:page:)` → `library.info`;
    `FileInfo.isCurrent` → true. Without a hook every library call throws `DecodeError.unreadable(url)`.
  - `StatusLine.make(…, note: String? = nil)`: the note is the last field (iCloud sentences).

- [ ] **Step 1: Failing tests** with a fake `LibraryImages` that records calls and returns a 4×3
  `CGImage`: `fitAndThumbnailAskTheLibrary` (cache `.fit` and `.thumbnail(128)` → `image` called with
  those targets), `zoomDecodesTheFetchedFile` (fake `file` returns a `Fixtures` JPEG; `.full` result has
  the fixture's size), `noHookIsOneBadFile` (hook nil → `DecodeError.unreadable(url)`),
  `infoComesFromTheLibrary` (`FileInfo.read` → fake's pixel size and date, `isCurrent` true),
  `statusNoteIsLast` (`note: "Downloading from iCloud…"` → `fields.last`).
- [ ] **Step 2:** `swift test --filter LibraryDecodeTests` → fails.
- [ ] **Step 3:** Implement; the routing is one `PhotosLocation.isLibrary(url)` check at the top of each
  entry point, nothing else changes for files.
- [ ] **Step 4:** Both suites pass; `swift test --filter ImageCacheTests` still passes.
- [ ] **Step 5:** Commit `feat: library pictures decode through a hook the app sets`.

### Task 4: Batch destination "Photos library" (Core)

**Files:**
- Modify: `Sources/FeatherviewCore/Batch/BatchSettings.swift` (or where `outputFolder` lives),
  `Sources/FeatherviewCore/Batch/BatchJob.swift`, `Sources/FeatherviewCore/Batch/BatchConverter.swift`,
  `Sources/FeatherviewCore/Imaging/OutputFormat.swift`
- Test: `Tests/FeatherviewCoreTests/Batch/BatchPhotosTests.swift`

**Interfaces:**
- Consumes: Task 1 (`PhotosText.cantAdd(name:)`, `needsDestination`, `cantImport(format:)`).
- Produces:
  - `BatchSettings.toPhotos: Bool` (stored with the other settings and presets; default false).
  - `OutputFormat.photosImports: Bool` — JPEG, HEIC, PNG, TIFF, GIF true; everything else false
    (`shortcut: fixed list, check AVIF/JPEG XL/WebP imports when the minimum macOS rises`).
  - `BatchJob.addToPhotos: (@Sendable (URL) async throws -> Void)?` — called once per finished output
    when `settings.toPhotos`; the output is written to a temp folder (`FileManager.url(for:
    .itemReplacementDirectory, …)`) instead of the output folder, then handed over, then removed
    (also when the add throws). A throw fails that input's row with `PhotosText.cantAdd(name:)`.
  - `BatchSettings.problem(inputs: [URL]) -> String?` — `PhotosText.needsDestination` when any input is
    in the Photos cache folder (`BatchSettings.photosCache: URL`, the spec's path) and `outputFolder`
    is empty and `toPhotos` is false; `PhotosText.cantImport(format:)` when `toPhotos` and
    `!format.photosImports`; else nil. Start uses it (Task 8).

- [ ] **Step 1: Failing tests** `libraryInputsNeedADestination` (input under `photosCache`, empty
  folder → `needsDestination`; with a folder or `toPhotos` → nil; a normal file → nil),
  `photosNeedsAnImportableFormat` (QOI + `toPhotos` → `cantImport`), `outputsGoToPhotosAndNotToDisk`
  (two `Fixtures` inputs, `toPhotos`, a recording `addToPhotos`: called twice with existing PNG files
  named by the rename pattern; afterwards neither file exists and the output folder is unchanged),
  `refusedAddFailsTheRow` (`addToPhotos` throws for the second: row 2 `.failed` with
  `"Can't add b.png to Photos."`, row 1 `.converted`, no temp file left).
- [ ] **Step 2:** `swift test --filter BatchPhotosTests` → fails.
- [ ] **Step 3:** Implement; "Recreate subfolders", "Replace existing files" and "Keep file dates" do not
  apply with `toPhotos` (no folder); "Move originals to Trash" never applies to library inputs.
- [ ] **Step 4:** `swift test --filter Batch` passes (all batch suites).
- [ ] **Step 5:** Commit `feat: batch can add its outputs to the Photos library`.

### Task 5: `FeatherviewPhotos` target and bench

**Files:**
- Modify: `Package.swift` (target `FeatherviewPhotos`, dependencies `FeatherviewCore`, linker setting
  `.linkedFramework("Photos")`; the app and `featherview-bench` depend on it, the extensions don't)
- Create: `Sources/FeatherviewPhotos/PhotosLibrary.swift`, `Sources/FeatherviewPhotos/PhotosAlbums.swift`
- Modify: `Sources/FeatherviewBench/` (new subcommand `photos`), `Resources/Info.plist`, `Resources/InfoPlist.xcstrings`

**Interfaces:**
- Consumes: Task 1 (`PhotosLocation`, `PhotosAlbumRow`), Task 3 (`LibraryImages`).
- Produces:
  - `public final class PhotosLibrary: LibraryImages, @unchecked Sendable` (state behind
    `OSAllocatedUnfairLock`), `public static let shared`.
  - `func authorize() async -> PHAuthorizationStatus` (`.readWrite`; prompts only when not determined),
    `func authorizeAdding() async -> Bool` (`.addOnly`).
  - `func albums() async -> [PhotosAlbumRow]` — Library (all images, `creationDate` ascending),
    Favorites, Recents, media types (smart album subtypes with images, skipping Videos, Hidden,
    Recently Deleted, Slo-mo, Time-lapse, Cinematic), user albums depth-first with their folder path;
    `count` nil here.
  - `func count(_ album: String) async -> Int` (images only, for the sheet's rows).
  - `func list(_ album: String) async throws -> (urls: [URL], kind: PhotosAlbumKind)` — images only
    (`mediaType == .image`), the album's order; identifiers read with `fetchResult.enumerateObjects`
    once, nothing else per asset.
  - `func name(_ url: URL) -> String` — `PHAssetResource.assetResources(for:)` original file name,
    memoised per URL (called only for the title and visible grid cells).
  - `image(_:target:colorSpace:)`: `PHCachingImageManager.requestImage`, `isSynchronous = true`,
    `deliveryMode = .highQualityFormat`, `resizeMode = .exact`, `isNetworkAccessAllowed = false`,
    `targetSize` from `ImageDecoder.fitDecodeSize`/the thumbnail side; result drawn into `colorSpace`
    (`ImageDecoder.inColorSpace`). A picture only in iCloud returns the degraded preview and records the
    URL in `func isInCloud(_ url: URL) -> Bool`.
  - `func download(_ url: URL) async throws` — the same request with network access, which makes the
    next `image` call local.
  - `file(_:)`: `PHAssetResourceManager.writeData` of the current version (`.fullSizePhoto` if the asset
    is edited, else `.photo`) into `BatchSettings.photosCache/<asset-hash>/<original name>`; reused while it exists.
  - `func delete(_ urls: [URL]) async throws` (`PHAssetChangeRequest.deleteAssets`, one system prompt),
    `func add(_ file: URL) async throws` (`PHAssetCreationRequest`, `.photo` resource from the file,
    `shouldMoveFile = false`), `static func emptyCaches()` (Photos and Dropped folders).
  - Errors: denied, missing asset, failed request → `DecodeError.unreadable(url)`.
  - Bench: `featherview-bench photos [--album <id>]` prints the time to `list` the library and the
    first `.fit` decode, and p50/p95 of 50 `.fit` decodes walking the list (needs Photos access for
    the terminal; the maintainer runs it with `!`).

- [ ] **Step 1:** `swift build` with the new empty target; `otool -L` shows Photos only in the app and bench.
- [ ] **Step 2:** Implement; Info.plist strings and their 30 translations.
- [ ] **Step 3:** `swift build && swift test` passes; `scripts/bundle.sh debug` → `plutil -p
  build/Featherview.app/Contents/Info.plist | grep PhotoLibrary` shows both keys.
- [ ] **Step 4:** Commit `feat: PhotoKit access in its own target, and featherview-bench photos`.

### Task 6: Open from Photos… and browsing an album (app)

**Files:**
- Create: `Sources/Featherview/Viewer/PhotosSheet.swift`, `Sources/Featherview/Viewer/ViewerModel+Photos.swift`
- Modify: `Sources/Featherview/FeatherviewApp.swift` (`ImageDecoder.library = PhotosLibrary.shared`;
  `PhotosLibrary.emptyCaches()` off the main thread after the first image and at quit),
  `Sources/Featherview/Viewer/ViewerView.swift` (File menu item, sheet, availability in menus and
  toolbar), `Sources/Featherview/Viewer/ViewerModel.swift`, `Sources/Featherview/Viewer/ThumbnailGrid.swift`

**Interfaces:**
- Consumes: Tasks 1, 2, 3, 5.
- Produces: `ViewerModel.openPhotos(album: String)`, `ViewerModel.isLibrary: Bool` (the list's current or
  first URL is a library URL), `ViewerModel.displayName(_ url: URL) -> String` (`PhotosLibrary.name` for
  library URLs, album name for `PhotosLocation.albumURL`, else `lastPathComponent`).

- [ ] **Step 1:** File › "Open from Photos…" ⇧⌘O after Open Recent (`MenuKey`/`ViewerKey` like ⌥⌘O).
  The sheet: `PhotosSheet.sections`, row counts via `PhotosLibrary.count` in a task per visible row,
  ↑/↓, type-select, Return/double click, Esc, last album in `UserDefaults` (`photosLastAlbum`). Denied
  → `PhotosText.denied` / `deniedHelp` and a button opening
  `x-apple.systempreferences:com.apple.preference.security?Privacy_Photos`.
- [ ] **Step 2:** `openPhotos(album:)` mirrors `open(_:)` for a folder: ends slideshow, leaves grid and
  compare, `isOpening`, lists via `PhotosLibrary.list` off the main thread, starts at the last picture
  when `kind.opensAtEnd`, else the first, then `show()`. Not noted in Recent Files. Refresh (F5) on a
  library list calls it again keeping the current picture (`ImageList.reorder`).
- [ ] **Step 3:** Names: every `lastPathComponent` shown to the person in `ViewerModel` (`titleName`,
  messages), `ThumbnailGrid` cell names and tooltips, and `GridText` callers goes through `displayName`.
  Grid cells ask for names only when configured (visible), never for the whole list.
- [ ] **Step 4:** Audit (Review Focus 1): every `FileManager`, `fileExists`, `resourceValues`,
  `FolderWatch`, `RecentFiles.note` and sort call reachable from a library list is skipped for library
  URLs; `ViewerState.isLibrary` fed from `isLibrary`; menus and toolbar use `canEditFile` for rotate,
  flip, Rename, F7, and `canSort` for Sort By.
- [ ] **Step 5:** `swift build && swift test`; `scripts/bundle.sh debug` builds. No screen use here
  (Task 10 checks it).
- [ ] **Step 6:** Strings (`scripts/strings.sh`, 30 languages). Commit `feat: File › Open from Photos… browses an album like a folder`.

### Task 7: Drops from Photos (app)

**Files:**
- Modify: `Sources/Featherview/Viewer/ViewerView.swift`, `Sources/Featherview/Batch/BatchImagesColumn.swift`
- Create: `Sources/Featherview/Viewer/PromiseDrop.swift`

**Interfaces:**
- Produces: `enum PromiseDrop { static func receive(_ providers: [NSItemProvider]) async -> [URL] }` — for
  each provider that has no file URL but a file promise (`NSFilePromiseReceiver` from the drag's
  pasteboard), receives into a new `Caches/net.mynetx.featherview/Dropped/<n>` folder (`n` counting up
  from 1 per launch) and returns the received files; file URLs pass through unchanged.

- [ ] **Step 1:** The viewer's drop accepts `NSFilePromiseReceiver.readableDraggedTypes` besides
  `URL`; promised files → `model.open(<first received file>)`, which browses the Dropped folder (the
  dropped selection). `GridCollectionView.isDraggingOut` still refuses own drags.
- [ ] **Step 2:** The batch list's drop does the same and passes the received files to
  `BatchModel.add(dropped:)`.
- [ ] **Step 3:** `swift build`; `scripts/bundle.sh debug` builds; drag from Photos is checked in Task 10.
- [ ] **Step 4:** Commit `feat: pictures dragged from Photos open in the viewer and join the batch`.

### Task 8: Batch window: Photos inputs and the Photos destination (app)

**Files:**
- Modify: `Sources/Featherview/Batch/BatchModel.swift`, `Sources/Featherview/Batch/BatchCards.swift`
  (Name card "Save to"), `Sources/Featherview/Viewer/ViewerModel.swift` (`batchSelection`)

**Interfaces:**
- Consumes: Task 4 (`toPhotos`, `photosImports`, `addToPhotos`, `problem(inputs:)`), Task 5
  (`file`, `authorizeAdding`, `add`).
- Produces: `BatchModel.add(library urls: [URL])` — fetches each with `PhotosLibrary.file` off the main
  thread (progress in the list as for a big dropped folder) and adds the fetched files.

- [ ] **Step 1:** `batchSelection()` and Batch Convert… from a library list call `add(library:)`
  (the grid's selection, else the current picture).
- [ ] **Step 2:** "Save to" gets a third choice "Photos library" (disabled with `cantImport` under it
  for other formats); "Next to the originals" disabled while a fetched library file is in the list.
  Start shows `problem(inputs:)` instead of starting; with `toPhotos` it calls `authorizeAdding()` first
  (denied → the batch doesn't start, the card says `PhotosText.denied`) and sets
  `job.addToPhotos = PhotosLibrary.shared.add`.
- [ ] **Step 3:** `swift build && swift test`; strings in 30 languages.
- [ ] **Step 4:** Commit `feat: batch convert from the Photos library and into it`.

### Task 9: Operations on library pictures, iCloud, docs (app)

**Files:**
- Modify: `Sources/Featherview/Viewer/ViewerModel.swift`, `Sources/Featherview/Viewer/ViewerModel+Clipboard.swift`,
  `Sources/Featherview/Viewer/SavePanel.swift`, `Sources/Featherview/Viewer/StatusBar.swift`;
  `AGENTS.md` (budget row "Opening a Photos album of 10,000" and the bench command), `docs/roadmap.md`
  (milestone row 22, Photos item removed from Next version), `ROADMAP.md` (Photos under "Done, in the
  next release"), `README.md` (one line under features).

- [ ] **Step 1:** F8, Save As, ⌘C, Compare's second pane and the info panel's EXIF call
  `PhotosLibrary.file(url)` off the main thread first and then do what they do for files; a fetch
  that fails shows "Can't open IMG_1234.HEIC" (name from `displayName`). F8 never offers Move.
- [ ] **Step 2:** Delete on library pictures calls `PhotosLibrary.delete` (no own confirmation, no
  Trash); after it returns the pictures leave the list as after Trash; Cancel in the system prompt
  changes nothing and shows nothing.
- [ ] **Step 3:** iCloud: after a shown picture `isInCloud`, the status line gets
  `note: PhotosText.downloading` and `download(url)` runs; when it ends the cache entry is removed and
  the picture shown again (only if still current); a failed download sets
  `note: PhotosText.cantDownload(name:)`.
- [ ] **Step 4:** Docs as listed; `swift build && swift test`; strings in 30 languages.
- [ ] **Step 5:** Commit `feat: copy, save, delete and iCloud for library pictures; docs`.

### Task 10: Screen check (waits for the maintainer's go)

With the release build (`scripts/bundle.sh release`), caffeinate running, frontmost app checked before
each key (memory: screen bursts):

- First ⇧⌘O: the Photos prompt appears then and not at launch; Deny → sheet text and the Settings
  button; allow → sheet lists Library, Favorites, Recents, media types, albums with counts.
- Library opens at the newest picture; ←/→, Home/End, T, W, Compare, I (EXIF), zoom 1 (sharp, from the
  original); the title shows `IMG_….HEIC — n / N`; rotate, F2, F7, Sort By, Show in Finder are off.
- Budgets with the log stream / `featherview-bench photos` (maintainer runs it with `!`): first picture of
  the library, prefetched and not prefetched steps, `GridShow` in the library.
- F8 two same-named pictures into one folder; ⌘C into Preview's New from Clipboard; Save As; Delete
  one picture (system prompt, then Recently Deleted in Photos; Cancel leaves it).
- An iCloud-only picture ("Optimize Mac Storage"): preview, "Downloading from iCloud…", sharpens; again
  with Wi-Fi off.
- Drag three pictures from Photos onto the window and onto the batch list; onto the Dock icon.
- Batch from a grid selection to a folder, then to Photos library (add-only prompt; pictures appear in
  Photos; nothing left in the cache folder); QOI disables Photos library.
- Quit: cache folders empty. Rebuild (new ad-hoc signature) and open Photos again: note whether macOS asks again.
- Launch budget unchanged (< 410 ms, after ⌘Q).
