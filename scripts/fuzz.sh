#!/bin/bash
# Fuzzes the own decoders under AddressSanitizer: featherview-bench fuzz on one seed at a time, restarted after
# every crash until that format's time is used. Findings land in <out-dir>: crash-<n>.<ext> with the ASan log
# next to it as crash-<n>.<ext>.log, and hang-<n>.<ext> (over 5 s).
# Usage: scripts/fuzz.sh <seed-dir> <out-dir> [seconds per format, default 60]
# Seeds: FEATHERVIEW_FUZZ_SEEDS=<seed-dir> swift test --filter FuzzSeedTests
set -uo pipefail
[ $# -ge 2 ] || { echo "Usage: $0 <seed-dir> <out-dir> [seconds per format]" >&2; exit 2; }
mkdir -p "$2" || exit 1
SEEDS="$(cd "$1" && pwd)" OUT="$(cd "$2" && pwd)" BUDGET="${3:-60}"
[ -n "$SEEDS" ] || exit 2
cd "$(dirname "$0")/.."

# swiftc links the ASan runtime itself; ld doesn't take -fsanitize.
FLAGS=(-c release --scratch-path .build/asan --product featherview-bench -Xswiftc -sanitize=address -Xcc -fsanitize=address)
swift build "${FLAGS[@]}" || exit 1
BENCH="$(swift build "${FLAGS[@]}" --show-bin-path)/featherview-bench"

# The first n with no <prefix>-<n>.<ext> yet, so restarts and reruns never overwrite a finding.
next_name() {
    local n=1
    while [ -e "$OUT/$1-$n.$2" ]; do n=$((n + 1)); done
    echo "$OUT/$1-$n.$2"
}

summary=()
for seed in "$SEEDS"/*; do
    [ -f "$seed" ] || continue
    ext="${seed##*.}" name="$(basename "$seed")"
    inputs=0 crashes=0 hangs=0 start=$SECONDS
    while left=$((BUDGET - (SECONDS - start))); [ "$left" -gt 0 ]; do
        log="$OUT/run.log"
        ASAN_OPTIONS=abort_on_error=0 "$BENCH" fuzz "$seed" --out "$OUT" --seconds "$left" > "$log" 2>&1
        status=$?
        inputs=$((inputs + $(awk '/^inputs / {print $2}' "$log" | tail -1 | grep . || echo 0)))
        case $status in
            0) ;;
            3) hangs=$((hangs + 1)); rm -f "$OUT/current.$ext" ;;
            2) echo "$name: skipped, $(head -1 "$log")" >&2; rm -f "$log"; continue 2 ;;  # not an own format (.psb goes to ImageIO)
            *)
                crashes=$((crashes + 1))
                crash="$(next_name crash "$ext")"
                if [ -f "$OUT/current.$ext" ]; then mv "$OUT/current.$ext" "$crash"; fi
                mv "$log" "$crash.log"
                echo "$name: crash (exit $status), input $crash"
                ;;
        esac
    done
    rm -f "$OUT/run.log"
    summary+=("$(printf '%-24s %9d %8d %6d' "$name" "$inputs" "$crashes" "$hangs")")
done

echo
printf '%-24s %9s %8s %6s\n' seed inputs crashes hangs
printf '%s\n' "${summary[@]}"
echo "(inputs of runs that crashed or hung aren't counted)"
