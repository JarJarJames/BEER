#!/usr/bin/env bash
# Render icon/BEER.svg into a macOS AppIcon.icns at all required sizes.
# Requires librsvg (brew install librsvg) for rsvg-convert, plus iconutil (Xcode).
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SVG="$DIR/BEER.svg"
SET="$DIR/AppIcon.iconset"

if ! command -v rsvg-convert >/dev/null 2>&1; then
    echo "rsvg-convert not found — installing librsvg via Homebrew…"
    brew install librsvg
fi

rm -rf "$SET"
mkdir -p "$SET"

render() { rsvg-convert -w "$1" -h "$1" "$SVG" -o "$SET/$2"; }

render 16   icon_16x16.png
render 32   icon_16x16@2x.png
render 32   icon_32x32.png
render 64   icon_32x32@2x.png
render 128  icon_128x128.png
render 256  icon_128x128@2x.png
render 256  icon_256x256.png
render 512  icon_256x256@2x.png
render 512  icon_512x512.png
render 1024 icon_512x512@2x.png

iconutil -c icns "$SET" -o "$DIR/AppIcon.icns"
rm -rf "$SET"
echo "Built: $DIR/AppIcon.icns"
