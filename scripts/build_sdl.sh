#!/bin/bash
# Build the SDL2 that BEER gives Wine's controller driver (winebus) on GPTK
# runtimes, and install it where the app looks for it:
# ~/Library/Application Support/BEER/SDL/ (or $1, for scripts/build_app.sh).
#
# GPTK's own SDL2 is built with Apple's GameController framework, which then
# owns Xbox One/Series pads. GameController doesn't deliver input inside
# Wine's background driver process, so on GPTK those pads never reach a game
# whenever SDL is reading the pads. This is the same SDL release built without
# that backend, so SDL reads them itself.
#
# x86_64, because GPTK's Wine runs under Rosetta.
set -euo pipefail

VERSION="2.32.10"
SHA256="5f5993c530f084535c65a6879e9b26ad441169b3e25d789d83287040a9ca5165"
URL="https://github.com/libsdl-org/SDL/releases/download/release-$VERSION/SDL2-$VERSION.tar.gz"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${1:-$HOME/Library/Application Support/BEER/SDL}"
CACHE="$REPO_ROOT/.build/sdl"
# SDL's autotools build can't cope with spaces in its path, which the repo's
# may have, so it builds in a temporary directory.
WORK="$(mktemp -d -t beer-sdl)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$CACHE"
TARBALL="$CACHE/SDL2-$VERSION.tar.gz"
if [ ! -f "$TARBALL" ]; then
    echo "==> Downloading SDL2 $VERSION…"
    curl -fL -o "$TARBALL" "$URL"
fi
echo "$SHA256  $TARBALL" | shasum -a 256 -c -

mkdir -p "$WORK/src" "$WORK/build"
tar xzf "$TARBALL" -C "$WORK/src" --strip-components 1

echo "==> Building SDL2 $VERSION (x86_64, no GameController)…"
cd "$WORK/build"
CC="clang -arch x86_64" \
CFLAGS="-O2 -mmacosx-version-min=11.0" \
LDFLAGS="-mmacosx-version-min=11.0" \
    "$WORK/src/configure" \
        --host=x86_64-apple-darwin \
        --disable-joystick-mfi \
        --disable-static \
        --prefix="$WORK/out" >/dev/null
make -j"$(sysctl -n hw.ncpu)" >/dev/null
make install >/dev/null

LIB="$WORK/out/lib/libSDL2-2.0.0.dylib"
if otool -L "$LIB" | grep -q GameController; then
    echo "error: built SDL2 still links GameController" >&2
    exit 1
fi

mkdir -p "$DEST"
cp "$LIB" "$DEST/libSDL2-2.0.0.dylib"
# Its install name is the temporary build path; give it the conventional one,
# which invalidates the linker's signature, so sign it again (ad hoc).
install_name_tool -id @rpath/libSDL2-2.0.0.dylib "$DEST/libSDL2-2.0.0.dylib"
codesign --force -s - "$DEST/libSDL2-2.0.0.dylib"
echo "installed into $DEST"
