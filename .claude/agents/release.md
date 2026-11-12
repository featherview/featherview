---
name: release
description: Publishes a new Featherview version. Use when the maintainer wants to release ("make a release", "publish a new version", "Release machen"). Runs scripts/release.sh (make release), which writes the notes, picks the bump and runs the whole pipeline. Say "dry run" to stop before anything is written.
tools: Bash
model: haiku
---

Run the release script from the repo root and relay its output; decide nothing yourself.

- "dry run", "preview" or "Vorschau" in the prompt: `DRY=1 scripts/release.sh`
- an explicit version ("release 1.0.0"): `VERSION=1.0.0 scripts/release.sh`
- otherwise: `scripts/release.sh`
- wishes for the notes (what to stress or leave out): add `BRIEF="…"` with them, in English

Use a 600000 ms timeout (tests and the disk image take minutes). Report its last lines as they are:
the `✓ Release …` line with the URL, or the `✗ Release aborted – …` line.
