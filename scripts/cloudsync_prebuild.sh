#!/bin/bash
# SwiftPM build-tool hook (see Plugins/CloudSyncPrebuild). Runs on every
# build; dotnet skips the compile when the helper's sources haven't changed.
#
# Build-tool plugin commands run under SwiftPM's sandbox, which only allows
# writes inside the plugin's own outputFilesDirectory ($1) — not the package
# source tree, not ~/Library/Application Support. So unlike
# build_cloudsync.sh (which installs to Application Support for a release
# build), this redirects dotnet's obj/bin/publish output into that output
# directory. CloudSyncClient.locateBinary() knows to look there too.
set -uo pipefail

OUT_DIR="$1"
STAMP="$2"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJ="$REPO_ROOT/Tools/CloudSync"
BIN_PATH="$OUT_DIR/publish/CloudSync"
INSTALLED_FALLBACK="$HOME/Library/Application Support/BEER/CloudSync/CloudSync"

echo "Rebuilding CloudSync helper…"
mkdir -p "$OUT_DIR/publish"
# dotnet only re-bundles the single-file helper when its inputs are newer than
# the bundle, so a broken bundle newer than the sources would survive every
# rebuild. Remove it so each publish writes a fresh one.
rm -f "$BIN_PATH"

# --disable-build-servers: otherwise dotnet leaves a compiler server running
# that inherits SwiftPM's output pipe. SwiftPM waits for that pipe to close,
# so the whole build hangs until the server's ~10 minute idle timeout.
#
# env -i: the build hands this script Xcode-style settings (TARGETNAME,
# PRODUCT_NAME, … for BEER's resource bundle), and MSBuild reads every
# environment variable as a property, ignoring case. TARGETNAME=BEER_BEER
# renamed the helper's assembly, leaving a launcher that looks for a
# CloudSync.dll that was never built. Pass on only what dotnet needs.
env -i HOME="$HOME" PATH="$PATH" TMPDIR="${TMPDIR:-/tmp}" USER="${USER:-}" \
    DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1 \
    ${DOTNET_ROOT:+DOTNET_ROOT="$DOTNET_ROOT"} ${NUGET_PACKAGES:+NUGET_PACKAGES="$NUGET_PACKAGES"} \
dotnet publish "$PROJ/CloudSync.csproj" \
    --disable-build-servers \
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

# Rewrite the stamp the plugin takes as input, so the next build runs this
# again (see Plugins/CloudSyncPrebuild). Done even when the checks below
# fail, so a failed build retries next time.
date > "$STAMP"

# A helper that can't start fails the app only at runtime, with an error that
# doesn't say to rebuild. Fail the build here instead. With no arguments it
# prints its usage and exits. It unpacks its native libraries on first start,
# and the sandbox only allows that under the temp folder.
check_output="$(DOTNET_BUNDLE_EXTRACT_BASE_DIR="${TMPDIR:-/tmp}" "$BIN_PATH" 2>&1)"
if ! grep -q "^usage: CloudSync" <<< "$check_output"; then
    echo "error: the CloudSync helper at $BIN_PATH doesn't start:" >&2
    head -5 <<< "$check_output" >&2
    exit 1
fi
