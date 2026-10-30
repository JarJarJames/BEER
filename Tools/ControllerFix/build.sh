#!/usr/bin/env bash
set -euo pipefail

# Builds the two halves of the controller fix:
#   dpad_helper  — native arm64 macOS binary (IOKit)
#   hid.dll      — x86_64 PE for the bottle (needs mingw-w64)
#
# hid.dll forwards every export it doesn't implement to a copy of Wine's own
# hid.dll renamed hid_orig.dll. The forward list is `hid.def`, checked in: Wine's
# hid.dll export list is the same across every runtime BEER installs. If a
# runtime ever differs, regenerate it with gen_def.py.
#
# Output goes to $1 if given (scripts/build_app.sh bundles it into the .app),
# otherwise to Application Support, where a `swift run` build finds it.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${1:-${HOME}/Library/Application Support/BEER/ControllerFix}"

if ! command -v x86_64-w64-mingw32-gcc >/dev/null; then
    echo "error: x86_64-w64-mingw32-gcc not found (brew install mingw-w64)" >&2
    exit 1
fi

mkdir -p "$OUT_DIR"

echo "==> dpad_helper (macOS)…"
clang -O2 -o "$OUT_DIR/dpad_helper" "$ROOT_DIR/dpad_helper.c" \
    -framework IOKit -framework CoreFoundation

echo "==> hid.dll (PE)…"
x86_64-w64-mingw32-gcc -O2 -s -shared \
    -o "$OUT_DIR/hid.dll" "$ROOT_DIR/hid_shim.c" "$ROOT_DIR/hid.def" -static

echo "installed into $OUT_DIR"
