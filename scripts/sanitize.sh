#!/bin/bash
# Runs the whole test suite under AddressSanitizer, then under ThreadSanitizer. Each sanitizer builds in its own
# scratch folder, so neither throws away the plain debug build. Exit status: 0 when both runs are clean.
# Usage: scripts/sanitize.sh [extra swift test arguments, e.g. --filter ImageListTests]
set -uo pipefail
cd "$(dirname "$0")/.."

failed=()
for sanitizer in address thread; do
    echo "== $sanitizer sanitizer =="
    # halt_on_error: the first report fails the run instead of scrolling past in the test output.
    ASAN_OPTIONS=halt_on_error=1 TSAN_OPTIONS=halt_on_error=1 \
        swift test --sanitize="$sanitizer" --scratch-path ".build/$sanitizer" "$@" || failed+=("$sanitizer")
done

[ ${#failed[@]} -eq 0 ] || { echo "Sanitizer runs failed: ${failed[*]}" >&2; exit 1; }
echo "Address and thread sanitizer runs clean."
