# Document icon — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. In this repo, code tasks run with the `plan-wave` workflow; tasks marked "main session" run in the main session.

**Goal:** Files in the formats only Featherview reads (QOI, PCX, XCF, BPG, …) show a document icon
with the feather in Finder, instead of the generic image page, wherever there's no thumbnail.

**Architecture:** No code. macOS draws the icon itself: each of our type declarations in
`Resources/Info.plist` gets a `UTTypeIcons` entry naming a badge (the feather, without the app
icon's tile) and a short text (the extension). The badge is an `.iconset` in the existing asset
catalog, which `scripts/bundle.sh` already compiles into `Assets.car`. A Core test keeps every
declaration and the asset in step.

**Tech Stack:** Info.plist (`UTImportedTypeDeclarations` › `UTTypeIcons`), `actool` (already in
`bundle.sh`), `rsvg-convert` (renders the PNGs once, as for `AppIcon.icns`), Swift Testing.

**Spec:** `docs/spec.md` "App icon" (Task 2 adds "Document icon" there), `docs/roadmap.md` v2
"Document icon". Rules: `AGENTS.md`.

## Spike facts (macOS 27, throwaway apps with own types; don't re-measure)

How a file's icon is chosen, read through `NSWorkspace.icon(forFile:)` (what Finder draws):

1. **The default app's own document icon wins.** Where GIMP is the default app for `.qoi`, the file
   shows GIMP's icon. Featherview can't change that, and shouldn't.
2. **`CFBundleTypeIconFile` in `CFBundleDocumentTypes` did nothing while another app was the
   default** (Owner rank and an exported type didn't change that). It could only count once
   Featherview is the default, which needs a consent prompt per type since macOS 26.4. Not used.
3. **`UTTypeIcons` in the type's declaration works without being the default** (also in an
   *imported* declaration, which ours are): the system draws its own page with the badge in the
   middle and `UTTypeIconText` under it. It's used whenever the default app brings no document icon
   of its own for the type, which today gives the generic page with the extension.
4. **`UTTypeIconBadgeName` resolves only to an `.iconset` in the compiled asset catalog**
   (`Assets.car`). A loose `.icns` in Resources or an `.imageset` is ignored, and so is a misspelt
   name: the system then silently uses the app icon (the feather on its dark tile) as the badge.
   So a wrong name doesn't fail, it just looks different; the test in Task 1 guards it.
5. Without `UTTypeIconText` there's no text; without the badge key the app icon is the badge; an
   empty `UTTypeIcons` dict gives the generic page. Long text is fine: `PROCREATE` fits.
6. At 16 and 32 px the system leaves the text out and keeps the badge. The tile-less feather reads
   at 16 px.
7. An `.iconset` folder in the asset catalog needs no `Contents.json`: the standard file names
   (`icon_16x16.png` … `icon_512x512@2x.png`) are enough for `actool`.

## Decisions

1. **Which formats:** every declaration in `UTImportedTypeDeclarations` (all are
   `net.mynetx.featherview.*`), except `net.mynetx.featherview.jfif`: JFIF is a JPEG that Preview
   and Quick Look read, so it keeps the system's JPEG icon. System-declared types we also open
   (`public.xbitmap-image`, `public.svg-image`, `com.apple.macpaint-image`) aren't ours to give an
   icon. That's 22 types today.
2. **Badge:** the feather alone (`Resources/Feather.svg`, the app icon's mark without its tile), so
   the page reads as a document and not as the app. Asset name `DocumentBadge`.
3. **Text:** the type's first filename extension in capitals (`QOI`, `JXR`, `RAS`, `IFF`, `MAC`,
   `FITS`, `PROCREATE`, …), like the system's generic page. Not translated: extensions are
   the same in every language.
4. No change to `CFBundleDocumentTypes`, no custom page artwork (the system draws the page and
   keeps it in step with the OS look), no icon for system types.

## Global Constraints

- No cat imagery; nothing copied or traced from another product's icons.
- Never hard-code a colour outside `Theme.swift`: the badge PNGs are rendered from
  `Resources/Feather.svg` as they are, no new colours.
- Bundle ID `net.mynetx.featherview` and the type identifiers stay as they are.
- Commit messages: conventional commits, no AI attribution.

## Review Focus

1. A badge name that doesn't match the iconset folder silently shows the app icon (spike fact 4):
   Task 1's test checks the name against the folder.
2. A future own format added to `UTImportedTypeDeclarations` without `UTTypeIcons` falls back to
   the generic page: Task 1's test walks every declaration, not a fixed list.
3. JFIF must keep the JPEG icon: Task 1's test expects no `UTTypeIcons` on it.
4. Icons cached from before the update (Featherview was already registered for these types with
   the generic page): Task 2 renders a type that was registered before (`bpg`) after rebuilding.
5. `actool` in `bundle.sh` must still produce the accent colour along with the badge: Task 2 checks
   `Assets.car` holds both.

---

## Wave plan

| Wave | Tasks | Why |
|---|---|---|
| A | 1 | the badge, the declarations and their test |
| B | 2 (main session) | rendered check of every type, spec and roadmap |

---

### Task 1: Badge asset and `UTTypeIcons` on our types

**Files:**
- Create: `Resources/Assets.xcassets/DocumentBadge.iconset/icon_{16,32,128,256,512}x{…}.png` and
  `@2x` variants (10 PNGs)
- Modify: `Resources/Info.plist` (every dict in `UTImportedTypeDeclarations` except JFIF)
- Modify: `scripts/bundle.sh` (comment only: where `DocumentBadge` comes from, next to the
  `AppIcon.icns` comment)
- Test: `Tests/FeatherviewCoreTests/Imaging/DocumentIconTests.swift`

**Interfaces:**
- Produces: asset name `DocumentBadge`; per declaration
  `UTTypeIcons = { UTTypeIconBadgeName: "DocumentBadge", UTTypeIconText: <first extension, uppercased> }`.

- [ ] **Step 1: Write the failing test**

Read `Resources/Info.plist` the way `QuickLookSupportTests.plist(_:)` does (`Fixtures.repo`).

```swift
@Test func ownTypesHaveTheFeatherDocumentIcon() throws {
    // for each dict in UTImportedTypeDeclarations:
    //   id == "net.mynetx.featherview.jfif" → #expect(dict["UTTypeIcons"] == nil)
    //   else: icons = dict["UTTypeIcons"] as? [String: String]
    //     #expect(icons?["UTTypeIconBadgeName"] == "DocumentBadge", "\(id)")
    //     #expect(icons?["UTTypeIconText"] == firstExtension.uppercased(), "\(id)")
    // #expect(count of declarations with icons == 22)
}

@Test func documentBadgeIsAnIconsetInTheAssetCatalog() throws {
    // Resources/Assets.xcassets/DocumentBadge.iconset contains exactly the 10 names
    // icon_16x16.png, icon_16x16@2x.png, … icon_512x512@2x.png,
    // and each PNG's pixel width (CGImageSource) == its nominal size × scale.
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter DocumentIconTests`
Expected: FAIL (no `UTTypeIcons`, no iconset).

- [ ] **Step 3: Render the badge**

From `Resources/Feather.svg` with `rsvg-convert -w N -h N` for N = 16, 32, 128, 256, 512 and their
doubles, into `Resources/Assets.xcassets/DocumentBadge.iconset/` with the standard names. No
`Contents.json` in the iconset (spike fact 7).

- [ ] **Step 4: Add `UTTypeIcons` to the 22 declarations in `Resources/Info.plist`**

Keep the plist's existing order and tab indentation; `plutil -lint Resources/Info.plist` passes.

- [ ] **Step 5: Run the tests**

Run: `swift test --filter "DocumentIconTests|QuickLookSupportTests|InfoPlistStringsTests"`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Resources/Assets.xcassets/DocumentBadge.iconset Resources/Info.plist scripts/bundle.sh Tests/FeatherviewCoreTests/Imaging/DocumentIconTests.swift
git commit -m "feat: feather document icon for the formats only Featherview reads"
```

---

### Task 2: Rendered check, spec and roadmap (main session, no screen needed)

**Files:**
- Modify: `docs/spec.md` ("App icon": a "Document icon" paragraph)
- Modify: `docs/roadmap.md` (v2 "Document icon": done)

- [ ] **Step 1: Build and register**

Run: `scripts/bundle.sh release && /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f build/Featherview.app`
Expected: `xcrun assetutil --info build/Featherview.app/Contents/Resources/Assets.car` lists
`DocumentBadge` and `AccentColor`.

- [ ] **Step 2: Render every type's icon offscreen**

A throwaway Swift script in the session scratchpad: for each extension of the 22 types plus `jfif`,
`NSWorkspace.shared.icon(for: UTType(filenameExtension:)!)` drawn into a 256 px and a 16 px bitmap,
PNGs side by side. Expected: the feather badge and the extension on the system page for every type
whose default app brings no icon of its own (types where another app like GIMP is the default show
that app's icon — spike fact 1; note which), `bpg` included (it was registered with the generic
page before), and the JPEG icon for `jfif`. If an old generic page sticks, run
`lsregister -f` again and note in the spec whether an update needs anything (it shouldn't: an
updated app is re-registered).

- [ ] **Step 3: Spec**

Under "App icon": files in the formats only Featherview reads show the feather on the system's
document page with the extension under it (the default app's own document icon wins where it
brings one; JFIF keeps the JPEG icon). Reference the 22 types as "the types Featherview declares".

- [ ] **Step 4: Roadmap**

Mark "Document icon" done under v2.

- [ ] **Step 5: Commit**

```bash
git add docs/spec.md docs/roadmap.md
git commit -m "docs: document icon in the spec, done in the roadmap"
```
