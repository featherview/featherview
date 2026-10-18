#!/bin/sh
# Extracts every localizable string from the code into Resources/Localizable.xcstrings.
# Run by hand after changing UI text: a full build with the compiler's typed extraction
# (finds literals passed to our own LocalizedStringKey parameters too), then xcstringstool sync.
set -eu
cd "$(dirname "$0")/.."

OUT=.build/strings
rm -rf "$OUT"                                   # full build: incremental builds only emit recompiled files
mkdir -p "$OUT/data"                            # the compiler doesn't create it
swift build --product Featherview --scratch-path "$OUT/build" \
  -Xswiftc -emit-localized-strings -Xswiftc -emit-localized-strings-path -Xswiftc "$PWD/$OUT/data"
[ -f Resources/Localizable.xcstrings ] ||
  printf '{"sourceLanguage":"en","strings":{},"version":"1.0"}\n' > Resources/Localizable.xcstrings
xcrun xcstringstool sync Resources/Localizable.xcstrings --stringsdata "$OUT"/data/*.stringsdata
