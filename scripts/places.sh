#!/bin/sh
# Builds build/places/places.fvpl, the info panel's place data, fresh from GeoNames and Natural Earth
# (featherview-bench places). Offline, the bench uses its cached downloads; with none, the last built
# file stays, with a warning. Usage: scripts/places.sh
set -eu
cd "$(dirname "$0")/.."
OUT=build/places/places.fvpl
mkdir -p build/places
if swift run -c release featherview-bench places "$OUT.new"; then
  mv "$OUT.new" "$OUT"
elif [ -f "$OUT" ]; then
  rm -f "$OUT.new"
  echo "warning: can't build place data; keeping $OUT from $(date -r "$OUT" +%Y-%m-%d)" >&2
else
  echo "error: can't build place data and there is no earlier $OUT" >&2
  exit 1
fi
