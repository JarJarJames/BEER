#!/bin/bash
# SwiftPM build-tool hook (see Plugins/CloudSyncPrebuild). llbuild only runs
# this when one of the declared input files (Tools/CloudSync/**/*.cs,
# *.csproj) actually changed, so there's no staleness check to do here.
#
# Build-tool plugin commands run under SwiftPM's sandbox, which only allows
# writes inside the plugin's own outputFilesDirectory ($1) — not the package
# source tree, not ~/Library/Application Support. So unlike
# build_cloudsync.sh (which installs to Application Support for a release
# build), this redirects dotnet's obj/bin/publish output into that output
# directory. CloudSyncClient.locateBinary() knows to look there too.
set -uo pipefail

OUT_DIR="$1"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJ="$REPO_ROOT/Tools/CloudSync"
BIN_PATH="$OUT_DIR/publish/CloudSync"
INSTALLED_FALLBACK="$HOME/Library/Application Support/BEER/CloudSync/CloudSync"

echo "Rebuilding CloudSync helper (dev build, sources changed)…"
mkdir -p "$OUT_DIR/publish"

dotnet publish "$PROJ/CloudSync.csproj" \
    -c Release \
    -r osx-arm64 \
    --self-contained true \
    -p:PublishSingleFile=true \
    -p:IncludeNativeLibrariesForSelfExtract=true \
    -p:BaseIntermediateOutputPath="$OUT_DIR/obj/" \
    -p:BaseOutputPath="$OUT_DIR/bin/" \
    -p:MSBuildProjectExtensionsPath="$OUT_DIR/obj/" \
    -o "$OUT_DIR/publish"
publish_status=$?

if [ $publish_status -ne 0 ] || [ ! -f "$BIN_PATH" ]; then
    # Xcode runs build-tool-plugin commands under a much stricter sandbox
    # than `swift build`'s — dotnet's NuGet restore needs filesystem/network
    # access that sandbox often denies outright, so a fresh publish can fail
    # here even though it works fine from the terminal. Rather than take the
    # whole Xcode build down over a dev-convenience rebuild, fall back to
    # whatever helper is already installed (from build_cloudsync.sh or an
    # earlier successful `swift build`) so the app/Previews still work with
    # a slightly stale helper instead of not building at all.
    echo "warning: dotnet publish failed under this sandbox (likely Xcode's plugin sandbox, not a real error) — falling back to the already-installed helper." >&2
    if [ -f "$INSTALLED_FALLBACK" ]; then
        cp "$INSTALLED_FALLBACK" "$BIN_PATH"
    else
        echo "error: no CloudSync helper is installed anywhere to fall back to. Run ./scripts/build_cloudsync.sh from the terminal first." >&2
        exit 1
    fi
fi

chmod +x "$BIN_PATH"

# Same signing rationale as build_cloudsync.sh: ad-hoc signatures aren't
# stable across rebuilds and Gatekeeper can SIGKILL an unrecognized one.
IDENTITY="BEER Local Dev"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    codesign --force --sign "$IDENTITY" "$BIN_PATH"
else
    codesign --force --sign - "$BIN_PATH"
fi
