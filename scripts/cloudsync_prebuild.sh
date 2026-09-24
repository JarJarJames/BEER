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
set -euo pipefail

OUT_DIR="$1"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJ="$REPO_ROOT/Tools/CloudSync"
BIN_PATH="$OUT_DIR/publish/CloudSync"

echo "Rebuilding CloudSync helper (dev build, sources changed)…"
mkdir -p "$OUT_DIR"
dotnet publish "$PROJ/CloudSync.csproj" \
    -c Release \
    -r osx-arm64 \
    --self-contained true \
    -p:PublishSingleFile=true \
    -p:IncludeNativeLibrariesForSelfExtract=true \
    -p:BaseIntermediateOutputPath="$OUT_DIR/obj/" \
    -p:BaseOutputPath="$OUT_DIR/bin/" \
    -o "$OUT_DIR/publish"

chmod +x "$BIN_PATH"

# Same signing rationale as build_cloudsync.sh: ad-hoc signatures aren't
# stable across rebuilds and Gatekeeper can SIGKILL an unrecognized one.
IDENTITY="BEER Local Dev"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    codesign --force --sign "$IDENTITY" "$BIN_PATH"
else
    codesign --force --sign - "$BIN_PATH"
fi
