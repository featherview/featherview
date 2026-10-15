---
name: run-featherview
description: Build, launch and check the Featherview app on this Mac. Covers making a sample image folder, opening files with the app, reading its per-image timing log against the performance budgets, and taking screenshots. Use when asked to run, smoke-test, screenshot or measure the app, or to confirm a change works outside the unit tests.
---

# Run Featherview

The app needs full Xcode selected (`xcode-select -p` points into `Xcode.app`). With only the
Command Line Tools the SwiftUI target won't build; say so and stop.

## Build and launch

```sh
pkill -x Featherview                       # an old instance would get the file instead
scripts/bundle.sh debug                    # → build/Featherview.app (use no argument for release)
open -a "$PWD/build/Featherview.app" /tmp/fv-smoke/<file>
```

Measure performance only with a **release** build (`scripts/bundle.sh`).

## Sample images

```sh
mkdir -p /tmp/fv-smoke
sips -s format jpeg /System/Library/Desktop\ Pictures/*.heic --out /tmp/fv-smoke >/dev/null 2>&1
echo x > /tmp/fv-smoke/bad.jpg             # a file that fails to decode
```

Never add these to the repo. For a big folder (10,000 files), copy one image as `img$i.jpg`, as
in Task 11 of the plan.

## Timings

The app logs one line per image shown: `show <name>: <ms> ms`.

```sh
log stream --level debug --predicate 'subsystem == "net.mynetx.featherview"'   # live
log show --last 2m --debug --predicate 'subsystem == "net.mynetx.featherview"' # after the fact
```

Compare the numbers against the budgets table in `AGENTS.md`. Report the numbers you measured,
not a pass or fail without them.

## Seeing the window

`screencapture -x -o -l <windowID> out.png` needs a window ID. Simpler: `screencapture -x out.png`
captures the screen. The terminal needs Screen Recording permission for either; if the capture is
blank, ask the user to grant it. Save screenshots to the session scratchpad, then Read them.

Keys can't be sent to the app from here. List the key presses for the user to try, or drive it
with the browser/VM tools only when the user asks.
