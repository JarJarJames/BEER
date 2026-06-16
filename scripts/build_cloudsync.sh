#!/bin/bash
# Build the native CloudSync helper (SteamKit2) and install it where the app
# looks for it: ~/Library/Application Support/BEER/CloudSync/.
#
# Self-contained publish → a single executable that bundles the .NET runtime,
# so the app doesn't need `dotnet` installed at runtime.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJ="$REPO_ROOT/Tools/CloudSync"
SUPPORT="$HOME/Library/Application Support"

# Mirror the app's one-time rename of the support dir (GameNativeMac → BEER).
# Running this before the renamed app's first launch would otherwise create a
# fresh BEER/ and orphan the user's existing bottles and saves.
if [ -d "$SUPPORT/GameNativeMac" ] && [ ! -d "$SUPPORT/BEER" ]; then
    mv "$SUPPORT/GameNativeMac" "$SUPPORT/BEER"
fi

DEST="$SUPPORT/BEER/CloudSync"

echo "Publishing CloudSync (self-contained, osx-arm64)…"
dotnet publish "$PROJ/CloudSync.csproj" \
    -c Release \
    -r osx-arm64 \
    --self-contained true \
    -p:PublishSingleFile=true \
    -p:IncludeNativeLibrariesForSelfExtract=true \
    -o "$PROJ/publish"

mkdir -p "$DEST"
cp "$PROJ/publish/CloudSync" "$DEST/CloudSync"
chmod +x "$DEST/CloudSync"

echo "Installed CloudSync helper to:"
echo "  $DEST/CloudSync"
