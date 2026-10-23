#!/usr/bin/env python3
"""Resolves a merge conflict on Resources/Localizable.xcstrings.

Run during the conflicted merge (or rebase): reads the base, ours and theirs from the index
(stages 1, 2 and 3), keeps ours, adds every key theirs added or changed, and writes the file in
xcstringstool's own format. Stops with exit 1, writing nothing, when both sides changed a key
differently, and names each such key. Then: git add Resources/Localizable.xcstrings
"""
import json
import re
import subprocess
import sys

PATH = "Resources/Localizable.xcstrings"


def stage(n):
    """The catalog at index stage n, or None when that stage is absent (no base: added on both sides)."""
    r = subprocess.run(["git", "show", f":{n}:{PATH}"], capture_output=True)
    if r.returncode != 0:
        return None
    return json.loads(r.stdout.decode("utf-8"))


def main():
    root = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True, check=True)
    base, ours, theirs = stage(1), stage(2), stage(3)
    if ours is None or theirs is None:
        sys.exit(f"{PATH} is not in a merge conflict.")
    base_strings = (base or {}).get("strings", {})
    merged = ours["strings"]
    conflicts = []
    for key, value in theirs["strings"].items():
        if value == base_strings.get(key):
            continue  # theirs left it alone
        if key not in merged or merged[key] == base_strings.get(key) or merged[key] == value:
            merged[key] = value
        else:
            conflicts.append(key)
    if conflicts:
        print("Both sides changed these keys differently; resolve them by hand:", file=sys.stderr)
        for key in conflicts:
            print(f"  {json.dumps(key, ensure_ascii=False)}", file=sys.stderr)
        sys.exit(1)
    with open(f"{root.stdout.strip()}/{PATH}", "w", encoding="utf-8") as f:
        f.write(layout(ours))


def layout(catalog):
    """xcstringstool's layout: keys sorted, two-space indent, " : " separators, UTF-8 unescaped,
    an empty object over two lines with a blank one between, no trailing newline."""
    text = json.dumps(catalog, indent=2, ensure_ascii=False, separators=(",", " : "), sort_keys=True)
    return re.sub(r'^( *)(".*" : )\{\}', lambda m: f"{m[1]}{m[2]}{{\n\n{m[1]}}}", text, flags=re.M)


if __name__ == "__main__":
    main()
