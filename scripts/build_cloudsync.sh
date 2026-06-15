#!/bin/bash
# Build the native CloudSync helper (SteamKit2) and install it where the app
# looks for it: ~/Library/Application Support/GameNativeMac/CloudSync/.
#
# Self-contained publish → a single executable that bundles the .NET runtime,
# so the app doesn't need `dotnet` installed at runtime.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJ="$REPO_ROOT/Tools/CloudSync"
DEST="$HOME/Library/Application Support/GameNativeMac/CloudSync"

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
