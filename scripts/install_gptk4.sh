#!/usr/bin/env bash
# Build a "GPTK 4.0" runtime for BEER by overlaying Apple's Game Porting Toolkit
# 4.0 D3DMetal libraries onto an installed Gcenx GPTK Wine base.
#
# Why this is a build step and not an in-app download:
#   Apple's official "Evaluation environment for Windows games" DMG ships ONLY
#   the D3DMetal redistributable overlay (redist/lib/{external,wine}) — it has no
#   Wine of its own. So GPTK 4.0 = a base GPTK Wine + Apple's current D3DMetal on
#   top. Apple's libraries are NOT redistributable, so they never enter this repo
#   or a build artifact; you supply the DMG locally and this script reads it in
#   place, exactly like Apple's own Read Me describes for updating Gcenx/CrossOver.
#
# What it does:
#   1. Locates Apple's redist/lib (a mounted DMG, a .dmg in ~/Downloads, or a path
#      you pass in).
#   2. Copies an installed Gcenx GPTK Wine ("Game Porting Toolkit.app") as the base.
#   3. MERGES Apple's external/ (D3DMetal.framework + libd3dshared.dylib) and the
#      d3d/dxgi/nvapi/nvngx files into the base Wine's lib tree, replacing the
#      older D3DMetal the base shipped. (A merge, NOT Apple's literal
#      `mv wine wine.old`, which would wipe Wine's whole PE-DLL tree.)
#   4. Renames the MetalFX shim (nvngx-on-metalfx -> nvngx) per Apple's setup notes.
#   5. Strips quarantine so the freshly-copied dylibs will load.
#
# Result: ~/Library/Application Support/BEER/Runtimes/GPTK-4.0-beta, which BEER's
# runtime scanner picks up automatically (listed as "Managed GPTK-4.0-beta").
#
# Requirements: GPTK 4.0 / D3DMetal needs Apple Silicon + macOS 15 Sequoia or
# higher (newer than BEER's usual macOS 14 floor — a 4.0-specific constraint).
#
# Usage:
#   ./scripts/install_gptk4.sh [path-to-redist/lib | path-to.dmg | mounted-volume]
# Env overrides:
#   BASE_WINE=/path/to/Game Porting Toolkit.app   pick the base Wine explicitly
set -euo pipefail

TARGET_NAME="GPTK-4.0-beta"

SUPPORT="$HOME/Library/Application Support"
# Mirror the app's one-time GameNativeMac -> BEER rename (see build_cloudsync.sh)
# so running this before the renamed app's first launch can't orphan bottles.
if [ -d "$SUPPORT/GameNativeMac" ] && [ ! -d "$SUPPORT/BEER" ]; then
    mv "$SUPPORT/GameNativeMac" "$SUPPORT/BEER"
fi
RUNTIMES="$SUPPORT/BEER/Runtimes"
TARGET="$RUNTIMES/$TARGET_NAME"

# --- cleanup: detach any DMG we mount ourselves -----------------------------
MOUNTED_BY_US=""
cleanup() {
    if [ -n "$MOUNTED_BY_US" ]; then
        hdiutil detach "$MOUNTED_BY_US" -quiet >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

die() { echo "error: $*" >&2; exit 1; }

# --- 1. Locate Apple's redist/lib ------------------------------------------
# Accepts: a redist/lib dir, the DMG's mount point, a .dmg file, or nothing
# (then we look for a mounted volume, then a DMG in ~/Downloads).
resolve_redist_lib() {
    local arg="$1"
    # Given a directory: it may BE redist/lib, or contain redist/lib.
    if [ -d "$arg" ]; then
        if [ -d "$arg/external" ] && [ -d "$arg/wine" ]; then echo "$arg"; return; fi
        if [ -d "$arg/redist/lib" ]; then echo "$arg/redist/lib"; return; fi
    fi
    # Given a .dmg: mount it read-only and locate redist/lib inside.
    if [ -f "$arg" ] && [[ "$arg" == *.dmg ]]; then
        local mnt
        mnt="$(hdiutil attach -readonly -nobrowse -noverify "$arg" 2>/dev/null \
            | grep -o '/Volumes/.*' | head -1)" || true
        [ -n "$mnt" ] || die "could not mount $arg"
        MOUNTED_BY_US="$mnt"
        [ -d "$mnt/redist/lib" ] || die "mounted $arg but found no redist/lib"
        echo "$mnt/redist/lib"; return
    fi
    return 1
}

LIB_SRC=""
if [ "${1:-}" != "" ]; then
    LIB_SRC="$(resolve_redist_lib "$1")" || die "couldn't find redist/lib at: $1"
else
    # Already-mounted Evaluation Environment volume?
    for v in /Volumes/*Evaluation*environment*for*Windows*games*; do
        if [ -d "$v/redist/lib" ]; then LIB_SRC="$v/redist/lib"; break; fi
    done
    # Otherwise a DMG sitting in ~/Downloads.
    if [ -z "$LIB_SRC" ]; then
        for d in "$HOME/Downloads/"*[Ee]valuation*[Ww]indows*games*.dmg; do
            [ -f "$d" ] || continue
            LIB_SRC="$(resolve_redist_lib "$d")" && break
        done
    fi
fi
[ -n "$LIB_SRC" ] || die "no Apple GPTK redist/lib found. Mount the \
'Evaluation environment for Windows games' DMG, or pass its path."
[ -f "$LIB_SRC/external/libd3dshared.dylib" ] || die "redist/lib looks wrong (no external/libd3dshared.dylib): $LIB_SRC"
echo "==> Apple D3DMetal source: $LIB_SRC"

# --- 2. Locate a base Gcenx GPTK Wine --------------------------------------
# Looks for an installed "Game Porting Toolkit.app" with a real wine64 bin.
find_base_app() {
    if [ -n "${BASE_WINE:-}" ]; then echo "$BASE_WINE"; return; fi
    # Prefer a managed GPTK runtime (not our own target), newest first.
    local dir app
    for dir in "$RUNTIMES"/*; do
        [ -d "$dir" ] || continue
        [ "$(basename "$dir")" = "$TARGET_NAME" ] && continue
        app="$dir/Game Porting Toolkit.app"
        if [ -x "$app/Contents/Resources/wine/bin/wine64" ]; then echo "$app"; return; fi
    done
    # Fallback: a system-wide GPTK install.
    if [ -x "/Applications/Game Porting Toolkit.app/Contents/Resources/wine/bin/wine64" ]; then
        echo "/Applications/Game Porting Toolkit.app"; return
    fi
    return 1
}

BASE_APP="$(find_base_app)" || die "no base GPTK Wine found. Install a Game \
Porting Toolkit version in BEER's Runtime Manager first (or set BASE_WINE=...)."
[ -d "$BASE_APP" ] || die "base Wine not found: $BASE_APP"
echo "==> Base GPTK Wine:       $BASE_APP"

# D3DMetal 4.0's PE DLLs (d3d11/d3d12/dxgi) call into libd3dshared.dylib through
# Wine's internal __wine_unix_call ABI, which is locked to the Wine version they
# were built against (CrossOver 25 / Wine ~10.x). Overlaying onto an older Wine
# builds fine but produces a non-functional D3D backend — games report
# "Unsupported Graphics Card / D3D FeatureLevel 11.0 required". As of this
# writing the newest freely-available base (Gcenx game-porting-toolkit 3.0-3) is
# still wine-7.7. Warn loudly rather than hand back a runtime that won't run.
WINE_VER="$("$BASE_APP/Contents/Resources/wine/bin/wine64" --version 2>/dev/null | sed -n 's/^wine-\([0-9]*\).*/\1/p')"
if [ -n "$WINE_VER" ] && [ "$WINE_VER" -lt 10 ]; then
    echo "" >&2
    echo "  !! WARNING: base reports wine-$WINE_VER. Apple's D3DMetal 4.0 needs a" >&2
    echo "  !! newer Wine (CrossOver 25 / wine ~10+). On this base the overlay" >&2
    echo "  !! installs but D3D11 will fail (\"Unsupported Graphics Card\")." >&2
    echo "  !! Use GPTK 3.0 until a wine-10+ GPTK base is available." >&2
    echo "" >&2
fi

# --- 3. Copy the base, then overlay Apple's D3DMetal -----------------------
mkdir -p "$RUNTIMES"
if [ -e "$TARGET" ]; then
    echo "==> Removing previous $TARGET_NAME"
    rm -rf "$TARGET"
fi
mkdir -p "$TARGET"
echo "==> Copying base Wine into $TARGET_NAME …"
ditto "$BASE_APP" "$TARGET/Game Porting Toolkit.app"

WINE_LIB="$TARGET/Game Porting Toolkit.app/Contents/Resources/wine/lib"
[ -d "$WINE_LIB/wine/x86_64-windows" ] || die "base Wine has no lib/wine tree at $WINE_LIB"

echo "==> Overlaying Apple D3DMetal 4.0 …"
# external/ holds only D3DMetal — safe to overwrite wholesale.
ditto "$LIB_SRC/external" "$WINE_LIB/external"
# wine/{x86_64-unix,x86_64-windows} merge IN PLACE: overwrites the handful of
# d3d/dxgi/nvapi/nvngx files, leaves the rest of the PE-DLL tree untouched.
ditto "$LIB_SRC/wine" "$WINE_LIB/wine"

# --- 4. MetalFX: make nvngx the on-metalfx shim (Apple "Prepare your env") --
UNIX="$WINE_LIB/wine/x86_64-unix"
WIN="$WINE_LIB/wine/x86_64-windows"
if [ -e "$UNIX/nvngx-on-metalfx.so" ]; then
    ln -sf ../../external/libd3dshared.dylib "$UNIX/nvngx.so"
fi
if [ -f "$WIN/nvngx-on-metalfx.dll" ]; then
    cp -f "$WIN/nvngx-on-metalfx.dll" "$WIN/nvngx.dll"
fi

# --- 5. Quarantine strip (DMG-sourced dylibs won't load otherwise) ----------
xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null || true

# --- verify -----------------------------------------------------------------
echo "==> Verifying overlay…"
src_sha="$(shasum -a256 "$LIB_SRC/external/libd3dshared.dylib" | awk '{print $1}')"
dst_sha="$(shasum -a256 "$WINE_LIB/external/libd3dshared.dylib" | awk '{print $1}')"
[ "$src_sha" = "$dst_sha" ] || die "libd3dshared.dylib mismatch after overlay"

echo
echo "Installed GPTK 4.0 runtime:"
echo "  $TARGET"
echo "  libd3dshared.dylib sha256 ${dst_sha:0:16}… (matches Apple DMG)"
echo
echo "BEER will list it as \"Managed $TARGET_NAME\". Assign it per-game in the"
echo "game's Compatibility section. Requires macOS 15 Sequoia or higher."
