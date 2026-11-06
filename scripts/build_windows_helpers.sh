#!/bin/bash
# Build BEER's Windows helpers (Tools/WindowsHelpers) and install them where
# the app looks for them: ~/Library/Application Support/BEER/WindowsHelpers/
# (or $1, for scripts/build_app.sh).
#   beer_launch.exe, beer_launch_hook.dll  start a launcher that starts a
#                                          SteamStub-wrapped game itself
#   beer_xse_start.dll                     starts F4SE in the game
#
# 64-bit Windows binaries, so this needs mingw-w64 (brew install mingw-w64).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$REPO_ROOT/Tools/WindowsHelpers"
DEST="${1:-$HOME/Library/Application Support/BEER/WindowsHelpers}"
CC=x86_64-w64-mingw32-gcc

command -v "$CC" >/dev/null || { echo "error: $CC not found; brew install mingw-w64" >&2; exit 1; }

# No C runtime: they only call Windows, and have nothing to start up.
FLAGS=(-O2 -s -nostdlib -Wl,--no-insert-timestamp)
# libgcc only for the stack probe big local buffers need.
LIBS=(-lkernel32 -luser32 -lgcc)

mkdir -p "$DEST"
echo "==> Building BEER's Windows helpers…"
"$CC" "${FLAGS[@]}" -shared -e DllMain -o "$DEST/beer_xse_start.dll" "$SRC/xse_start.c" "${LIBS[@]}" -lversion
"$CC" "${FLAGS[@]}" -shared -e DllMain -o "$DEST/beer_launch_hook.dll" "$SRC/launch_hook.c" "${LIBS[@]}"
"$CC" "${FLAGS[@]}" -mwindows -e start -o "$DEST/beer_launch.exe" "$SRC/launch.c" "${LIBS[@]}"
echo "Installed to $DEST"
