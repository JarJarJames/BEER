#!/usr/bin/env bash
set -euo pipefail

# Builds the two halves of the controller fix:
#   dpad_helper  — native arm64 macOS binary (IOKit)
#   hid.dll      — x86_64 PE for the bottle (needs mingw-w64)
#
# hid.dll forwards every export to a copy of Wine's own hid.dll renamed
# hid_orig.dll, so the export list is generated from whichever runtime the
# bottle uses. Pass that runtime's hid.dll as $1.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# BEER looks for the artifacts here (AppPaths.controllerFixDirectory), the same
# way the CloudSync helper is installed into Application Support.
OUT_DIR="${HOME}/Library/Application Support/BEER/ControllerFix"
WINE_HID="${1:-}"

# Default to the newest installed runtime's hid.dll when none is given.
if [[ -z "$WINE_HID" ]]; then
    WINE_HID="$(find "${HOME}/Library/Application Support/BEER/Runtimes" \
        -path '*/x86_64-windows/hid.dll' 2>/dev/null | sort | tail -1)"
fi

mkdir -p "$OUT_DIR"

echo "==> dpad_helper (macOS)…"
clang -O2 -o "$OUT_DIR/dpad_helper" "$ROOT_DIR/dpad_helper.c" \
    -framework IOKit -framework CoreFoundation

if [[ -z "$WINE_HID" || ! -f "$WINE_HID" ]]; then
    echo "==> skipping hid.dll: no runtime hid.dll found (pass one as \$1)"
    exit 0
fi

echo "==> generating forward list from $(basename "$WINE_HID")…"
python3 "$ROOT_DIR/gen_def.py" "$WINE_HID" > "$OUT_DIR/hid.def"

echo "==> hid.dll (PE)…"
x86_64-w64-mingw32-gcc -O2 -s -shared \
    -o "$OUT_DIR/hid.dll" "$ROOT_DIR/hid_shim.c" "$OUT_DIR/hid.def" -static

echo "installed into $OUT_DIR"
echo "Enable it per game with the Controller toggle in BEER."
