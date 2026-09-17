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

# dotnet publish ad-hoc signs the binary itself. Ad-hoc has no stable
# identity — every rebuild is an unrecognized signature to Gatekeeper, which
# can SIGKILL it ("Code Signature Invalid") until that exact build is
# individually approved. Re-sign with the stable local identity (see
# scripts/setup_local_codesign_identity.sh) so rebuilds stay trusted.
IDENTITY="BEER Local Dev"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    codesign --force --sign "$IDENTITY" "$DEST/CloudSync"
else
    echo "note: '$IDENTITY' signing identity not found — run"
    echo "  scripts/setup_local_codesign_identity.sh"
    echo "once to avoid Gatekeeper killing freshly rebuilt helpers. Falling back to ad-hoc."
    codesign --force --sign - "$DEST/CloudSync"
fi

echo "Installed CloudSync helper to:"
echo "  $DEST/CloudSync"
