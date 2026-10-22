# Milestone 14: Slideshow — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. In this repo, code tasks run with the `plan-wave` workflow; tasks marked "main session" need the screen and run in the main session after the maintainer's go.

**Goal:** View › Start Slideshow (W) plays the viewer's own list from the current image in the
system's full screen at an interval, with shuffle (each image once per round) and repeat; Space
pauses, arrows step, Esc goes back to the window on the image shown. ⇧A plays the same way in the
window. No setup dialog, no transitions, no exports.

**Architecture:** Core gets one pure value type, `Slideshow`: the play order of the list's URLs
(shuffled with a seeded generator), the position in it, paused / finished, and when the image on
screen is due to give way. Time is injected: every method that needs it takes `now:` (a
`ContinuousClock.Instant`), so tests never sleep. The app keeps one `Slideshow?` in `ViewerModel`
and one task that sleeps until `due`, then shows what `tick` returns through the existing `show()`.
The interval starts when the image is on screen (`shown`), so a late decode never shortens the next
image's time. While a slideshow runs, the model's prefetch takes its neighbours from the play order
instead of the Finder order. Full screen and in-window playing are the same engine; full screen is
only where it shows.

**Tech Stack:** Swift 6, SwiftUI + AppKit (macOS 14+), Foundation's
`ProcessInfo.beginActivity(options: .idleDisplaySleepDisabled)`, Swift Testing. No new dependency.

**Spec:** `docs/roadmap.md` "Slideshow (v2)" (scope and the Mac form, which wins where it differs
from parity), `docs/parity.md` "Slideshow" (the reference's behaviour), `docs/spec.md` "Keys",
"Look" (motion, Reduce Motion), "Preferences" (Full screen: overlay, hide the pointer),
"Moving past the end of a folder", `docs/spec.md` "Animation" and
`docs/superpowers/plans/2026-10-22-milestone-9-animation.md` (an animated image during a slideshow).
The spec has no slideshow section yet; Task 4 writes one from the Decisions below. Rules: `AGENTS.md`.

## Decisions (the roadmap leaves these to the plan; accepted by the maintainer)

1. **Commands.** View menu, after the zoom items: "Start Slideshow  (W)" with ⇧⌘F (Preview's
   shortcut), and "Play in Window  (⇧A)" (the reference's keys: W starts its slideshow, Shift+A its
   automatic viewing). While one runs they read "End Slideshow  (W)" and "Stop Playing  (⇧A)", and
   "Pause Slideshow  (Space)" / "Resume Slideshow  (Space)" appears. Disabled without a current
   image. The context menu gets Pause / Resume and End Slideshow while one runs.
2. **Interval, shuffle, repeat** live in View › "Slideshow Options" (a submenu, so they can be
   changed mid-show from the menu bar, which slides in over full screen): "Show Each Image For" with
   checkmarked 1, 2, 3, 5, 10, 20, 30 and 60 seconds (default **5 s**, as in the reference; titles from
   `Duration.formatted(.units(allowed: [.seconds], width: .wide))`, so no catalog strings),
   then "Shuffle" and "Repeat" as checkmarked toggles (both off, as in the reference). Remembered
   in `AppSettings`. No Preferences entry (one place only).
3. **Order.** From the current image to the end of the list (Finder order), then the end. Shuffle:
   the current image first, then every other image once in random order. With Repeat, each further
   round is the whole list (shuffled anew, never starting with the image the last round ended on).
   Shuffle never changes the viewer's list: after the slideshow, ← / → go to the shown image's
   Finder neighbours, and the title and overlay show its Finder position.
4. **Changing options while playing:** the interval applies to the image on screen at once (due =
   when it showed + the new interval); toggling Shuffle restarts the round from the image on screen
   in the new order; Repeat only changes what happens at the end.
5. **Timing.** An image's interval starts when it is on screen (the model's `shown`). A next image
   not decoded by its due time shows as soon as it is, and its interval counts from then; ticks
   never queue up. Starting from a window, the first interval starts once the window has entered
   full screen (`NSWindow.didEnterFullScreenNotification`), so the first image gets its full time.
   An → / ← step, a rotation, a zoom or a page change shows the image again and restarts its
   interval. Resuming after a pause gives the image a full interval.
6. **Prefetch.** While a slideshow runs, `focusDecodes` asks the slideshow instead of the list: at
   fit the next two in play order and the previous one (nearest next first), zoomed the next one and
   the previous one, crossing into the next round when Repeat is on (the next round is drawn when
   the current one starts). They go through the same `cache.prefetch` + `fillReady` path as today,
   so each change is the prefetched swap (`Navigate` ≈ 20 ms) and the 8-image cache holds them.
   The shortest interval (1 s) is 9× the not-prefetched budget (< 150 ms, ≈ 107 ms measured).
7. **Display sleep:** while the slideshow plays (not paused, not finished) and its window is visible,
   the model holds `ProcessInfo.processInfo.beginActivity(options: .idleDisplaySleepDisabled,
   reason: "Slideshow")` (one `PreventUserIdleDisplaySleep` assertion; no system-sleep assertion)
   and ends it otherwise. Same in full screen and in the window.
8. **Hidden window:** minimized, fully covered or on another Space, the slideshow waits (no ticks,
   no assertion) and goes on with a full interval when visible again. The model gets this from the
   same occlusion / miniaturize hook M9's player uses.
9. **Pointer and controls (full screen only).** A small glass control capsule (previous, play /
   pause, next, end; SF Symbols `chevron.backward`, `play.fill` / `pause.fill`, `chevron.forward`,
   `xmark`) appears at the bottom centre when the pointer moves, as Preview's and Photos' slideshow
   controls do, and fades out after `BarsAutoHide.rest` (2 s) without movement unless the pointer is
   over it; the pointer hides with it when Preferences › Full screen › "Hide the pointer" is on.
   During a slideshow the pointer is not hidden on every image change (today's
   `hidePointerInFullScreen` on `model.image`), only at rest. Playing in the window shows no
   capsule: the toolbar and menus are there.
10. **The end** (Repeat off): after the last image's interval the slideshow is finished: it stays
    on that image (in full screen if it was), releases the assertion, and the play button / Space
    plays again from the start (a new round of the whole list). → does nothing there. Esc, W or
    ⇧⌘F go back to the window on the image shown. ⇧A stops in place.
11. **Esc / W / ⇧⌘F** end the slideshow and leave full screen if the window is in it. **⇧A** ends it
    and leaves the window as it is. **F, Return, double-click and the green button** toggle full
    screen and the slideshow goes on in the other form.
12. **Keys while a slideshow runs** (everything else as in the viewer):
    - → ↓ Page Down and a swipe step to the next image in play order, ← ↑ ⌫ Page Up to the previous
      (panning a zoomed image first, as today); paused stays paused; nothing past either end of the
      order (Repeat on: → past the end starts the next round). The folder chooser never opens and
      "Past the end of a folder" doesn't apply.
    - Space pauses and resumes (Page Down still steps).
    - Home / End do nothing (menu items disabled): there is no first or last in a shuffled round.
    - R / L, ⌦ / ⌘⌫, F7 / F8, S, ⌘C, I, G (M9), ⌥→ / ⌥←, 0 / 1 / + / − work as in the viewer, so a
      slideshow can be used to cull. Trash or a move takes the image out of the play order and the
      next one in play order shows at once ("show the next image" off doesn't hold it here); the last
      one gone ends the slideshow ("No images in <folder>" as today). While a panel or sheet is open
      (F7 / F8 panel, Save As, an alert) a due image waits a full interval more.
    - Opening a file or folder (⌘O, O, drop, Save As opening the saved file), the window closing and,
      once M13 lands, T (the grid) end the slideshow. W / ⇧A in M13's grid leave the grid on the
      focused cell first.
13. **Unreadable files** are skipped at once in the direction of travel, without a message (a
    slideshow is for watching; the reference hides errors by default). When every image of the
    order failed in a row the slideshow finishes on the last one with its "Can't open <name>".
14. **Animated images** (M9) play while they are on screen; the slideshow's interval alone decides
    when the next image comes (a loop isn't waited for). G pauses the animation, not the slideshow.
15. **Motion:** image changes are cuts (spec "Look": browsing is instant), so Reduce Motion changes
    nothing there; the capsule fades by opacity only (`Theme.Motion.barsIn` / `barsOut`), which
    Reduce Motion keeps, as for the hidden bars. Full-screen entry is the system's animation.

## Spike facts (macOS 27, Swift 6 language mode; don't re-measure)

- `ProcessInfo.processInfo.beginActivity(options: .idleDisplaySleepDisabled, reason: "Slideshow")`
  shows in `pmset -g assertions` as exactly one `PreventUserIdleDisplaySleep named: "Slideshow"`
  for the process, gone after `endActivity(_:)`. Adding `.userInitiated` adds a
  `PreventUserIdleSystemSleep` too (not wanted). `IOPMAssertionCreateWithName` gives the same
  display assertion, so IOKit isn't needed. Compiles under Swift 6 strict concurrency (the token is
  `NSObjectProtocol`; keep it on the main actor).
- `pmset -g assertions` is the check without a screen: Task 4 reads it while playing, paused,
  minimized and after the window closed.

## Global Constraints

- macOS 14.0 minimum; Swift 6 strict concurrency; no new dependency.
- Performance budgets in `AGENTS.md` hold: each slideshow change is a prefetched swap (`Navigate`
  p50 ≈ 19 ms, p95 ≤ 25 ms); memory stays within the 8-image cache; cold launch unchanged (no
  slideshow object exists until W / ⇧A).
- Colours, metrics, radii, durations only from `Theme.swift` (new tokens go there);
  leading/trailing, never left/right; the capsule's chevrons mirror in right-to-left languages
  (`chevron.backward` / `.forward` do), and → / ← follow `ViewerKey.arrowGoesForward` as today.
- Every user-facing string translatable, whole sentences; new strings get all 30 languages
  (`scripts/strings.sh`, then the shared steps in
  `docs/superpowers/plans/2026-10-18-milestone-6-languages.md` "Translation tasks (5–10): the
  shared steps"). The activity `reason` is not user-facing and stays English.
- Never lose user data: Trash only, moves never overwrite (unchanged paths).
- Conventional commits, no AI attribution, no dates in docs or comments; `shortcut:` comments as
  `shortcut: <limit>, <when to upgrade>`.

## Review Focus

- The display-sleep assertion must never outlive the slideshow: window closed mid-show (the main
  `ViewerModel` outlives its window), a file opened, the last image trashed, paused, finished,
  minimized. Pinned in Task 2 (one `updateActivity()` called from every state change, `endSlideshow`
  from `onDisappear` and `open`), checked with `pmset -g assertions` in Task 4.
- Shuffle with Repeat over many rounds: every image exactly once per round, no image twice in a row
  across a round boundary, and a 1- or 2-image folder doesn't loop forever. Pinned in Task 1
  (`shuffleRoundHasEachOnce`, `nextRoundNeverRepeatsLast`, `singleImageRepeats`).
- Trash during a shuffled slideshow (current, upcoming, already shown, the last one left): the
  order stays consistent, the next in play order shows, never an index out of range. Pinned in
  Task 1 (`removeCurrentGoesToNext`, `removeLastLeftFinishes`, `removeUpcomingDropsIt`).
- A folder of unreadable files with Repeat on: no busy loop of skips. Pinned in Task 1
  (`allFailedFinishes`).
- A slow decode (50 MP JPEG) at a 1 s interval: the next tick waits for it to show; no two changes
  queue up. Pinned in Task 1 (`tickWaitsForShown`), checked in Task 4.

---

## Wave plan

| Wave | Tasks | Why |
|---|---|---|
| A | 1 | the Core engine, keys and settings |
| B | 2 | the slideshow in the viewer (uses 1; starts once M9 Task 5 is merged: both change `show()`, `shown()` and the window-visibility hook) |
| C | 3 | the full-screen capsule and pointer (uses 2's model API; same view file) |
| D | 4 (main session) | screen check, budgets, docs |

---

### Task 1: `Slideshow` engine, keys and settings (Core)

**Files:**
- Create: `Sources/FeatherviewCore/Viewer/Slideshow.swift`
- Modify: `Sources/FeatherviewCore/Viewer/ImageList.swift` (`select`),
  `Sources/FeatherviewCore/Viewer/ViewerKey.swift` (`slideshow`, `playInWindow`),
  `Sources/FeatherviewCore/App/AppSettings.swift` (three settings, registered)
- Test: `Tests/FeatherviewCoreTests/Viewer/SlideshowTests.swift`, `ImageListTests.swift`,
  `ViewerKeyTests.swift`, `Tests/FeatherviewCoreTests/App/AppSettingsTests.swift`

**Interfaces:**
- Produces:
  - `public struct Slideshow: Equatable, Sendable`
    - `public struct Options: Equatable, Sendable { public var interval: Duration; public var shuffle: Bool; public var repeats: Bool; public init(interval:shuffle:repeats:) }`
    - `public static let intervals: [Int] = [1, 2, 3, 5, 10, 20, 30, 60]` (seconds)
    - `public init(urls: [URL], from current: URL, options: Options, seed: UInt64)` — Decision 3's
      first round; `current` not in `urls` → starts at `urls[0]`. The app passes `.random(in: .min ... .max)`.
    - `public private(set) var options: Options`, `public private(set) var isPaused = false`,
      `public private(set) var isFinished = false`, `public var isPlaying: Bool { !isPaused && !isFinished }`
    - `public var current: URL?` — the image the slideshow wants on screen.
    - `public private(set) var due: ContinuousClock.Instant?` — nil while paused, finished, or
      waiting for `current` to be shown.
    - `public mutating func shown(_ url: URL, at now: ContinuousClock.Instant)` — `url == current`
      and playing: `due = now + interval`; otherwise nothing.
    - `public mutating func tick(at now: ContinuousClock.Instant) -> URL?` — before `due` (or `due`
      nil): nil. At or after: the next URL (becomes `current`, `due` = nil), or nil and
      `isFinished` at the end without Repeat.
    - `public mutating func step(forward: Bool) -> URL?` — the next / previous in play order, `due`
      = nil until shown; nil and unchanged at either end (Repeat: forward past the end starts the next
      round; backward at a round's first image does nothing). Keeps `isPaused`; from finished, back
      is allowed and clears `isFinished` into paused.
    - `public mutating func togglePause(at now: ContinuousClock.Instant) -> URL?` — playing → paused
      (`due` nil); paused → playing with `due = now + interval`, returns nil; finished → a new round of
      the whole list (Decision 3), playing, returns its first URL.
    - `public mutating func hold(at now: ContinuousClock.Instant)` — a panel was open at `due`: `due = now + interval`.
    - `public mutating func failed(_ url: URL) -> URL?` — `url == current`: the next in the last
      direction of travel (as `tick` / `step` would give); after as many failures in a row as the
      order has images, nil and finished. Any `shown` resets the run.
    - `public mutating func remove(_ url: URL) -> URL?` — drops it from this and the next round; if
      it was `current`, returns the next in play order (else the previous; nil and finished when none
      is left). Not current: nil.
    - `public mutating func setOptions(_ options: Options, shownAt: ContinuousClock.Instant?)` —
      Decision 4. `shownAt` is when `current` was shown (nil if not yet).
    - `public func neighbors(ahead: Int) -> [URL]` — the next `ahead` in play order (into the next
      round with Repeat), then the previous one; no duplicates, never `current`.
  - `public mutating func ImageList.select(_ url: URL) -> Bool` — makes `url` current (releases a
    held image); false and unchanged when `url` isn't in the list.
  - `ViewerKey.slideshow` on "w"; `ViewerKey.playInWindow` on Shift + "a" (the only Shift + letter
    that maps; plain "a" stays `.about`).
  - `AppSettings.slideshowSeconds = Setting(key: "slideshowSeconds", defaultValue: 5)`,
    `slideshowShuffle` (false), `slideshowRepeat` (false), registered; and
    `public static var slideshowOptions: Slideshow.Options` built from them (seconds not in
    `Slideshow.intervals` → 5).

The shuffle is a seeded generator owned by the struct (`SplitMix64` in the same file, `private`,
`RandomNumberGenerator`), used with `shuffled(using:)`, so the struct stays `Equatable` and tests
are deterministic.

- [ ] **Step 1: Write the failing tests** in `SlideshowTests` (URLs `/f/1.jpg` … `/f/n.jpg`, no files;
  `let t0 = ContinuousClock.now`; 5 s interval unless named):
  - `orderedPlaysFromCurrentToEnd`: 5 images from 3 → `tick` after each `shown` gives 4, 5, then nil
    with `isFinished`.
  - `tickWaitsForShown`: `shown(3, t0)`, `tick(t0 + .seconds(4))` nil, `tick(t0 + .seconds(5))` 4;
    `tick(t0 + .seconds(60))` nil again until `shown(4, …)`.
  - `shownForAnotherURLIsIgnored`: `shown` of a URL that isn't `current` leaves `due` nil.
  - `shuffleRoundHasEachOnce`: 20 images, shuffle, from 7 → first is 7, the round's 20 URLs are all
    20 once; a different seed gives a different order.
  - `nextRoundNeverRepeatsLast`: 2 and 3 images, shuffle + repeat, 50 rounds × seeds 1…20 → the
    first of each round ≠ the last of the round before; every round has each once.
  - `singleImageRepeats`: 1 image, repeat → `tick` returns it again each interval; repeat off → finished.
  - `repeatOrderedWrapsToFirst`: 3 images from 2, repeat → 3, 1, 2, 3, 1.
  - `stepKeepsPauseAndStopsAtEnds`: paused, `step(forward: true)` → next, still paused, `due` nil;
    at the round's last without repeat → nil; at its first backward → nil.
  - `togglePauseRestartsFullInterval`: `shown(t0)`, pause at t0+4, resume at t0+10 → `due == t0 + 15`.
  - `finishedPlaysAgain`: finished, `togglePause` → first URL of a new whole-list round, playing.
  - `holdPushesDue`: `hold(at: t0 + 5)` → `due == t0 + 10`.
  - `failedSkipsInDirection`: stepping backward onto a failed URL → `failed` gives the one before it.
  - `allFailedFinishes`: 4 images, repeat, every one failed in turn → after the 4th, nil and finished.
  - `removeCurrentGoesToNext`, `removeUpcomingDropsIt` (never returned by later ticks or
    `neighbors`), `removeLastLeftFinishes`.
  - `shuffleToggleRestartsFromCurrent`: ordered at 3 of 10, `setOptions(shuffle: true)` → `current`
    still 3, the next 9 are the other 9 once.
  - `intervalChangeAppliesNow`: shown at t0, interval → 2 s → `due == t0 + 2s`.
  - `neighborsCrossIntoNextRound`: 3 images, repeat, at the last → `neighbors(ahead: 2)` = the next
    round's first two then the previous one; repeat off at the last → just the previous one.
  - `ImageListTests.selectMakesCurrent` (and false for an unknown URL; releases a held image).
  - `ViewerKeyTests`: `wStartsSlideshow`, `shiftAPlaysInWindow`, `plainAIsStillAbout`, `shiftWIsNothing`.
  - `AppSettingsTests`: the three defaults registered; `slideshowOptions` with 7 stored → 5 s.
- [ ] **Step 2: Run** `swift test --filter "SlideshowTests|ImageListTests|ViewerKeyTests|AppSettingsTests"` → FAIL.
- [ ] **Step 3: Implement.** Store the order as `[URL]` for the current round plus the drawn next
  round (when `repeats`), and the position; no indices into the viewer's list.
- [ ] **Step 4: Run** the same filter → PASS; `swift test` → all PASS (ViewerKey's switch in the app
  needs the two new cases: add `case .slideshow, .playInWindow: break` in `ViewerView.handle` so the
  app builds; Task 2 fills them in).
- [ ] **Step 5: Commit** `feat: slideshow order, timing and keys`

---

### Task 2: The slideshow in the viewer

**Files:**
- Modify: `Sources/Featherview/Viewer/ViewerModel.swift`, `Sources/Featherview/Viewer/ViewerView.swift`
  (keys, View menu items and Slideshow Options submenu, context menu, full-screen and visibility
  hooks, `onDisappear`), `Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: Task 1's `Slideshow`, `ImageList.select`, `ViewerKey.slideshow` / `.playInWindow`,
  `AppSettings.slideshowOptions`; M9's visibility hook in `ViewerView` (the one calling
  `model.player.setVisible`).
- Produces (on `ViewerModel`, used by Task 3):
  - `enum SlideshowState: Equatable { case playing, paused, finished }`;
    `private(set) var slideshowState: SlideshowState?` — observed, set only when it changes (nil: none).
  - `func startSlideshow(fullScreen: Bool)`, `func endSlideshow()` (synchronous: cancels the timer,
    ends the activity, `slideshowState = nil`), `func toggleSlideshowPause()`,
    `func slideshowOptionsChanged()` (re-reads `AppSettings.slideshowOptions`),
    `func enteredFullScreen()`, `func setWindowVisible(_ visible: Bool)` (also forwards to M9's player).

Rules:
- The engine lives in `@ObservationIgnored var slideshow: Slideshow?`; one `slideshowTask` sleeps
  `until: due` (`ContinuousClock`), then: a panel, sheet or modal open (`destinationPanel`,
  `window?.attachedSheet`, `NSApp.modalWindow`) → `hold`; else `tick` → `go(to:)`. Re-armed after
  every engine change; nothing armed while not visible (Decision 8).
- `go(to url:)`: `list.select(url)`, then `show()`. `next()` / `previous()` call `step` when a
  slideshow runs (so arrows, swipes, toolbar and menu all follow the play order) and never reach
  `pastEnd`. `first()` / `last()` do nothing then; `availability` keeps back / forward enabled.
- `shown(_:url:page:started:)` calls `slideshow.shown(url, at: .now)` (unless waiting for full
  screen, Decision 5); the decode-failure branch of `show()` calls `failed` and goes on to its
  result without setting `errorMessage` unless the slideshow finished.
- `focusDecodes()` uses `slideshow.neighbors(ahead: zoom == .fit ? 2 : 1)` when a slideshow runs.
- `removeFromList`: with a slideshow, `remove(url)` decides what shows (no hold), then
  `list.remove`, `list.select`; nil → `endSlideshow()` and today's empty-folder path.
- `updateActivity()`: holds the `beginActivity` token exactly while `slideshowState == .playing`
  and the window is visible (Decision 7); called from every place that changes either.
- `open(_:)` and the view's `onDisappear` call `endSlideshow()`. Esc (and W, ⇧⌘F while one runs):
  `endSlideshow()`, then leave full screen if in it. ⇧A while one runs: `endSlideshow()` only.
  Space: `toggleSlideshowPause()` while one runs, else `next()` as today.
- `startSlideshow(fullScreen: true)` from a window: `toggleFullScreen`, and the first interval
  waits for `enteredFullScreen()` (from `didEnterFullScreenNotification` for this window).
- View menu (Decision 1, 2): the Slideshow Options submenu binds `@AppStorage` for the three
  settings and calls `model?.slideshowOptionsChanged()` on change; interval titles via
  `Duration.seconds(n).formatted(.units(allowed: [.seconds], width: .wide))`.

- [ ] **Step 1: Implement** the model and view changes above; `swift build`; `scripts/bundle.sh debug`.
- [ ] **Step 2:** `scripts/strings.sh`; the new menu titles ("Start Slideshow  (W)", "End
  Slideshow  (W)", "Play in Window  (⇧A)", "Stop Playing  (⇧A)", "Pause Slideshow  (Space)",
  "Resume Slideshow  (Space)", "Slideshow Options", "Show Each Image For", "Shuffle", "Repeat",
  context-menu "Pause Slideshow", "Resume Slideshow", "End Slideshow") in all 30 languages;
  `swift test` → all PASS.
- [ ] **Step 3: Commit** `feat: slideshow and playing in the window (W, ⇧A), Space pauses`

---

### Task 3: Full-screen controls and the pointer

**Files:**
- Create: `Sources/Featherview/Viewer/SlideshowControls.swift`
- Modify: `Sources/Featherview/Viewer/ViewerView.swift` (overlay at the bottom while
  `model.isFullScreen && model.slideshowState != nil`; pointer hiding), `Sources/Featherview/Design/Theme.swift`
  (capsule tokens), `docs/DESIGN.md` ("Elements": the slideshow capsule), `Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: Task 2's `slideshowState`, `toggleSlideshowPause()`, `next()`, `previous()`,
  `endSlideshow()` + leaving full screen (the Esc path).
- Produces: `struct SlideshowControls: View` — `init(state: ViewerModel.SlideshowState, previous: () -> Void, togglePause: () -> Void, next: () -> Void, end: () -> Void)`.

Rules (Decision 9):
- Glass capsule (`.glass(.card, cornerRadius:)` as the strip uses), four borderless buttons as the
  toolbar draws them; tooltips "Previous (←)", "Pause (Space)" / "Play (Space)", "Next (→)",
  "End slideshow (Esc)" (in right-to-left languages the arrow keys in the tooltips swap as the
  toolbar's do). New tokens in `Theme`: `slideshowControlsGap`, `slideshowControlsPadding`,
  `slideshowControlsBottom`, `Radius.slideshowControls`.
- Shown on pointer movement (the existing `onContinuousHover`), hidden after `BarsAutoHide.rest`
  without movement while the pointer isn't over it; opacity only, `Theme.Motion.barsIn` / `barsOut`.
  When it hides, `NSCursor.setHiddenUntilMouseMoves(true)` if `hidePointer` is on. While a
  slideshow runs, `hidePointerInFullScreen()` no longer fires on `model.image` changes.
- Paused or finished: the capsule stays up with "Play" (a mouse user must see how to go on).

- [ ] **Step 1: Implement**; `swift build`; `scripts/bundle.sh debug`.
- [ ] **Step 2:** `scripts/strings.sh`; the four tooltips in all 30 languages; `swift test` → all PASS.
- [ ] **Step 3: Commit** `feat: slideshow controls in full screen; the pointer hides at rest`

---

### Task 4: Screen check, budgets, docs (main session, screen)

Needs the maintainer's go (screen bursts). Sample folders: `/tmp/fv/browse` from
`featherview-bench corpus`, plus a mixed folder: a corrupt `.jpg`, a 50 MP JPEG, an animated GIF
(M9's fixture writer), a 3-page TIFF, a portrait JPEG with EXIF orientation 6.

- [ ] **Step 1: Check by hand** (release build), light and dark, then in Arabic (right-to-left): W
  and ⇧⌘F from a window (full screen, first image gets its full 5 s after the transition), ⇧A in the
  window; Space pause / resume, → / ← / swipe in play order, paused stays paused; Shuffle + Repeat at
  2 s over 3 rounds of the browse folder (each once per round, no repeat at the seam); toggle Shuffle
  and change the interval mid-show from the menu bar; the end with Repeat off (stays, Space plays
  again, Esc back to the window on that image, ← / → then Finder neighbours); F in the middle (goes on
  in the window) and back; ⌦, R, F7 mid-show (panel holds the timer); the mixed folder (corrupt file
  skipped silently, GIF animates and the slideshow moves on at the interval, TIFF page 1, 50 MP late
  but next interval full); capsule appears on movement, hides with the pointer after 2 s, stays when
  paused; Reduce Motion on (nothing moves except the system's full-screen switch; the capsule fades);
  minimize mid-show (stops; restored, goes on); ⌘O mid-show ends it.
- [ ] **Step 2: Measure:** `Navigate` for every slideshow change at 1 s, shuffled, over
  `/tmp/fv/browse` (`sudo -n /usr/bin/log show`): all "prefetched: yes", p50 ≈ 19 ms, p95 ≤ 25 ms;
  memory flat over 5 rounds (8-image cache); `pmset -g assertions` while playing / paused / finished
  / minimized / after closing the window mid-show; the display doesn't sleep or start the screen
  saver with both set to 1 minute during a 3-minute show, and does once paused; cold launch
  unchanged (< 410 ms). Fix any miss before going on.
- [ ] **Step 3: Docs:** `docs/spec.md` gets a "Slideshow" section under "Viewer" with Decisions
  1–15 in spec wording, W, ⇧A and "Space during a slideshow" in "Keys", the menu items in "Menu
  commands"; `docs/parity.md` "Slideshow" rows → Featherview column as built, status `v2`; roadmap:
  row `| 14 | Slideshow (v2) | docs/superpowers/plans/2026-10-22-milestone-14-slideshow.md | done |`;
  README features line. `AGENTS.md` "Out of scope" keeps "slideshows with effects".
- [ ] **Step 4: Commit** `docs: slideshow done after manual QA`
