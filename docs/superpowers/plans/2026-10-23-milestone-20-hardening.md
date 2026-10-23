# Milestone 20: Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: run Tasks 1–7 with `plan-wave-lite` (in order: Task 2 needs
> Task 1). Task 8 needs the screen and runs in the main session after the maintainer's go. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Trust before features: no file crashes or hangs the app, real camera files survive every write
path, the app runs on Intel Macs too, and a crash reaches the maintainer when the person wants it to.

**Architecture:** A deterministic byte mutator in FeatherviewCore drives a `fuzz` command in
featherview-bench over the own decoders, built with AddressSanitizer by `scripts/fuzz.sh`. The opt-in
`RealPhotoTests` suite (`FEATHERVIEW_SAMPLES/photos/`, private files never committed) grows to Save As
and batch. Release builds become universal. Crash reports are found in the user's own
DiagnosticReports folder and offered, never sent, through the existing bug report form.

**Tech Stack:** Swift 6, Swift Testing, SwiftPM sanitizers (`--sanitize=address|thread`), ImageIO,
Rosetta 2 for x86_64 test runs.

**Spec:** `docs/spec.md` ("Help menu" paragraph with Report a Bug…, "Rotate", "Output" (batch metadata),
"Formats" (HDR output), "Languages"). Task 6 adds the crash-report paragraph to the spec.

## Global Constraints

- Swift 6 strict concurrency; no file reads on the main thread; nothing new before the first image
  (launch budget < 410 ms, AGENTS.md).
- TDD for FeatherviewCore. Test images from `Fixtures`; real files only through `SampleCorpus`
  (`FEATHERVIEW_SAMPLES`), skipped when unset, never committed, never shown in screenshots.
- Never lose user data: tests work on copies; the app writes temp file and swaps in.
- User-facing text translatable, all 30 languages in `Resources/Localizable.xcstrings`, added by hand in
  the file's existing format.
- Nothing is sent anywhere without the person clicking; no telemetry.
- Dependencies: none new.

## Review Focus

1. A mutated file whose header claims 65536 × 65536 pixels: the decoder throws `OwnDecodeError.corrupt`
   (`checkedSize`) before allocating, never an out-of-memory kill — Task 2, `hugeHeaderIsRefused` per format
   that reads a size from its header.
2. A truncated own-format file (every prefix length of a valid seed): throws, never crashes or reads past
   the end — Task 1, `everyPrefixOfASeedThrowsOrDecodes`.
3. A crash report from another app with "Featherview" in its path, or a malformed `.ips`: not offered —
   Task 6, `onlyOwnReportsAreOffered`, `malformedReportIsIgnored`.
4. Save As of an iPhone photo with orientation 6 to PNG: output is upright with tag 1, same displayed size
   — Task 4, `saveAsIsUprightWithMetadata`.
5. Batch over a folder twice into the same output: the second run never overwrites (" 2" names) — Task 4,
   `batchTwiceNeverOverwrites`.

---

### Task 1: Fuzz mutator, seeds and harness

**Files:**
- Create: `Sources/FeatherviewCore/Formats/FuzzMutator.swift`
- Create: `Sources/FeatherviewBench/Fuzz.swift`; Modify: `Sources/FeatherviewBench/main.swift` (usage + dispatch)
- Create: `scripts/fuzz.sh`
- Test: `Tests/FeatherviewCoreTests/Formats/FuzzMutatorTests.swift`, `Tests/FeatherviewCoreTests/Formats/FuzzSeedTests.swift`

**Interfaces:**
- Produces: `public struct FuzzMutator { public init(seed: UInt64); public mutating func mutate(_ data: Data) -> Data }`
  (SplitMix64; each call applies 1–4 of: flip a bit, set a byte to 0x00/0xFF/0x7F/0x80, overwrite 4 bytes
  with a big-endian or little-endian 0xFFFF / 0x10000 / 0x7FFFFFFF, truncate, duplicate a 1–64-byte run,
  delete a run).
- Produces: `featherview-bench fuzz <seed-dir> --out <dir> [--seconds 60] [--seed N]`; writes each input to
  `<out>/current.<ext>` before decoding it, copies hangs (> 5 s, watchdog thread) to `<out>/hang-<n>.<ext>`;
  exit 0 when time is up.
- Produces: seed dir layout `<dir>/<format name lowercased>.<first extension>`, one valid file per
  `OwnDecoders.builtIn` format.

- [ ] **Step 1: Failing tests** — `FuzzMutatorTests`: `sameSeedSameOutput` (two mutators, seed 7, same
  input → equal outputs over 100 calls), `mutatesSomething` (100 calls on a 256-byte input: at least 95
  differ from the input), `emptyInputStaysUsable` (mutate(Data()) doesn't trap).
  `FuzzSeedTests` (`.enabled(if: env FEATHERVIEW_FUZZ_SEEDS set)`): `writesOneSeedPerOwnFormat` writes
  seeds using the builders the decoder tests already have (move a builder from a test file into a shared
  `Tests/FeatherviewCoreTests/Formats/` helper when needed, don't duplicate it); expects a file for every
  `OwnDecoders.builtIn` name and that each decodes with its format's `decode`.
  `everyPrefixOfASeedThrowsOrDecodes` (always on): for each builder output, every prefix
  `data.prefix(n)`, n in 0..<count (step 1 up to 512, then 64): `size`, `pageCount`, `decode(page 0)` throw or
  return, never trap.
- [ ] **Step 2:** `swift test --filter FuzzMutatorTests` → fails (type missing). The prefix test may already
  pass or crash; a crash is a Task 2 finding, note it and fix it in this task if it's in the prefix test.
- [ ] **Step 3:** Implement `FuzzMutator`, `Fuzz.swift` (calls `OwnDecoders.format(for:)`, then `size`,
  `pageCount`, `decode` with `maxPixelSize` nil and 512 for pages 0..<min(pageCount, 3)) and
  `scripts/fuzz.sh <seed-dir> <out-dir> [seconds per format]`: builds the bench with
  `-c release -Xswiftc -sanitize=address -Xcc -fsanitize=address -Xlinker -fsanitize=address`, runs one
  seed at a time; when the process dies (ASan report or signal), moves `current.*` to `crash-<n>.<ext>` with
  the ASan log next to it and restarts until that format's time is used.
- [ ] **Step 4:** `swift test --filter 'FuzzMutatorTests|FuzzSeedTests'` passes;
  `FEATHERVIEW_FUZZ_SEEDS=/tmp/fvseeds swift test --filter FuzzSeedTests` writes all seeds;
  `scripts/fuzz.sh /tmp/fvseeds /tmp/fvfuzz 10` runs every format for 10 s and prints a per-format summary.
- [ ] **Step 5: Commit** `test: fuzz mutator, seeds for every own format, ASan fuzz script`

### Task 2: Fuzz campaign and fixes

**Files:** the decoders in `Sources/FeatherviewCore/Formats/` that fail; their test files.

**Interfaces:** Consumes Task 1's `scripts/fuzz.sh` and seeds.

- [ ] **Step 1:** `scripts/fuzz.sh <seeds> <out> 120` (2 minutes per format), plus the real files in
  `FEATHERVIEW_SAMPLES/{xcf,psb,psp,pdn}` as extra seeds when present.
- [ ] **Step 2:** For each crash, hang or ASan report: shrink the input by hand (truncate, zero runs) while
  it still fails, add it as a byte-array regression test in that decoder's test file (`crashInput<n>Throws`,
  expects `OwnDecodeError` or a decoded image, and finishes in < 1 s), see it fail.
- [ ] **Step 3:** Fix the root cause in the decoder (bounds check, `checkedSize`, loop limit). For every
  decoder that reads a size from a header, add `hugeHeaderIsRefused` (header claims 65536 × 65536 → throws
  `.corrupt` without allocating).
- [ ] **Step 4:** Rerun Step 1 until a full pass finds nothing; `swift test` passes.
- [ ] **Step 5: Commit** one `fix: <format> refuses <input>` per decoder.

### Task 3: Sanitizer runs of the whole suite

**Files:** Create `scripts/sanitize.sh`; Modify `.github/workflows/ci.yml` (a weekly `schedule:` job,
`workflow_dispatch` too); fixes where findings point.

- [ ] **Step 1:** `swift test --sanitize=address` and `swift test --sanitize=thread`; record every report.
- [ ] **Step 2:** For each report: a test that reproduces it under the sanitizer, then the fix (a data race
  is fixed by isolation, not by `@unchecked Sendable` or `nonisolated(unsafe)`).
- [ ] **Step 3:** `scripts/sanitize.sh` runs both; the weekly CI job runs it on `macos-26`.
- [ ] **Step 4:** Both runs clean; plain `swift test` passes.
- [ ] **Step 5: Commit** `test: address and thread sanitizer runs, weekly in CI` plus `fix:` commits.

### Task 4: Real files through Save As and batch

**Files:** Modify `Tests/FeatherviewCoreTests/Imaging/RealPhotoTests.swift`; fixes where it fails.

**Interfaces:** Consumes `ImageSaver.save(_ source: URL, page: Int, to: URL, as: OutputFormat, options:
FormatOptions)`, `BatchConverter.run(_:control:…)`, `SampleCorpus`.

- [ ] **Step 1: Tests** (copies only, per photo, `arguments: photos`):
  `saveAsIsUprightWithMetadata` for every `OutputFormat` that has an encoder in the test process
  (JPEG, PNG, HEIC, TIFF, WebP, AVIF; JPEG XL only if `ImageEncoder.jxlEncoder` is set): output decodes,
  pixel size equals the source's `ImageDecoder.displaySize`, orientation 1, `DateTimeOriginal` and GPS kept
  where the format keeps metadata (spec "Output"; JPEG "keep EXIF" default on), ICC profile name kept;
  for a source with a gain map, HEIC and AVIF output keep one (spec "Formats", HDR).
  `batchConvertsTheCorpus`: `BatchConverter` over all photos to JPEG → one output per input, no failures.
  `batchTwiceNeverOverwrites`: same job twice into one folder → twice the files, second set with " 2".
- [ ] **Step 2:** `FEATHERVIEW_SAMPLES=~/FeatherviewSamples swift test --filter RealPhotoTests`; each failure
  is a bug: reproduce it with a `Fixtures` image in the owning suite (failing test first), then fix.
- [ ] **Step 3:** All pass with the samples; without them the suite is skipped.
- [ ] **Step 4: Commit** `test: real camera files through Save As and batch` plus `fix:` commits.

### Task 5: Universal release (Apple Silicon and Intel)

**Files:** Modify `scripts/bundle.sh`, `README.md` (Install: "Apple Silicon or Intel"), the release agent's
DMG step only if it builds separately (`.claude/agents/release.md`).

- [ ] **Step 1:** `scripts/bundle.sh release` builds with `--arch arm64 --arch x86_64` (debug stays native),
  for the app and both extensions; the script fails unless `lipo -archs` lists both for every Mach-O in the
  bundle.
- [ ] **Step 2:** `arch -x86_64 swift test` (Rosetta) passes; failures that are x86-only (SIMD paths in
  vendored C, float rounding) get fixed or, for a tolerance, a commented test change.
- [ ] **Step 3:** `arch -x86_64 build/Featherview.app/Contents/MacOS/Featherview <a jpg>` opens and logs the
  first-image line; `swift run -c release featherview-bench decode` under `arch -x86_64` runs.
- [ ] **Step 4:** README Install says Apple Silicon or Intel, macOS 14+, budgets measured on Apple Silicon.
- [ ] **Step 5: Commit** `feat: universal release build for Intel Macs`

### Task 6: Offer to report a crash

**Spec (add to the Help paragraph, then build it):** After Featherview crashed, the next launch offers, once
per crash and at the earliest 10 seconds after launch (like the update check): "Featherview quit
unexpectedly last time." with "Report…" and "Not Now". Report… opens the same bug report form as Help ›
Report a Bug…, with the crash summary (exception type and the crashed thread's first 15 frames) in a "Crash
report" field. Nothing is sent by the app. Only Featherview's own reports count (its process, not the
extensions'); only reports newer than the last one offered.

**Files:**
- Create: `Sources/FeatherviewCore/App/CrashReports.swift`
- Modify: `Sources/FeatherviewCore/App/AboutInfo.swift` (`BugReportField.crash`, `bugReportURL(…, crash: String? = nil)`),
  `.github/ISSUE_TEMPLATE/bug_report.yml` (textarea id `crash`, label "Crash report"),
  `AppSettings` (last offered report date), the app's launch path next to the update check, `docs/spec.md`,
  `Resources/Localizable.xcstrings`
- Test: `Tests/FeatherviewCoreTests/App/CrashReportsTests.swift`, `AboutInfoTests.swift`

**Interfaces:**
- Produces: `public enum CrashReports { public static func newest(in folder: URL, newerThan: Date?) -> URL?;
  public static func summary(of report: Data) -> String? }` (`.ips`: first line JSON header with
  `app_name`/`name`, then JSON body with `exception.type`, `faultingThread`, `threads[].frames[]`
  (`imageIndex`, `symbol`), `usedImages[].name`). Default folder `~/Library/Logs/DiagnosticReports`.

- [ ] **Step 1: Failing tests** with `.ips` text built in the test: `onlyOwnReportsAreOffered` (another app's
  report, an extension's report (`FeatherviewThumbnail`) → nil), `newestAfterDateWins`,
  `malformedReportIsIgnored` (truncated JSON → `summary` nil, `newest` skips it),
  `summaryHasExceptionAndFrames` (exception type line + at most 15 `image  symbol` lines),
  `crashFieldIsInTheURL` and `longCrashIsCutToFitTheURL` (URL ≤ 8000 characters, cut at a line end).
- [ ] **Step 2:** Run → fail. **Step 3:** Implement; app side reads off the main thread, shows the alert
  through the existing alert style, stores the report's date when shown (either button).
- [ ] **Step 4:** Tests pass; `swift build`; strings in all 30 languages.
- [ ] **Step 5: Commit** `feat: offer to report a crash on the next launch`

### Task 7: Memory soak

**Files:** Modify `Sources/FeatherviewBench/main.swift` (`browse … --loops N`).

- [ ] **Step 1:** `--loops N` steps through the folder N times; prints peak footprint per loop and exits 1
  if the last loop's peak is more than 10 % above every earlier loop's but the first (a leak). Loop 1 is
  warm-up (empty cache and decoder pools), so the check needs 3 loops or more.
- [ ] **Step 2:** Run on `swift run -c release featherview-bench corpus /tmp/fv` → `browse /tmp/fv/browse
  --loops 5 --interval-ms 30`, and on `~/FeatherviewSamples/photos` when present; a leak is a bug, found with
  Instruments' Leaks / `leaks --atExit`, fixed with a test where Core owns it.
- [ ] **Step 3: Commit** `test: browse --loops finds leaks while browsing`

### Task 8 (main session, maintainer's go): screen checks and screenshots

- [ ] The open screen checks of milestones 11–18 (each plan's last task), the crash alert (Task 6: crash a
  debug build with `kill -SEGV`, relaunch), Intel build under Rosetta on screen.
- [ ] Two real screenshots for README and website (viewer, batch window), from generated or the
  maintainer's chosen non-personal images; committed to `docs/screenshots/`.
- [ ] Roadmap row 20 done.

## Outside this plan (maintainer)

Android photos into `~/FeatherviewSamples/photos/android/`; native-speaker review of translations; Discussions
category "Beta feedback" and pinning the welcome post (no API); the repo's social preview image (no API);
notarization once funded.
