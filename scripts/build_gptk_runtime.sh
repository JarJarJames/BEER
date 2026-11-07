#!/bin/bash
# Build a GPTK runtime BEER can download and share: CrossOver's open-source
# Wine, built from CodeWeavers' published source, with Apple's D3DMetal
# redistributables copied on top.
#
# Why not ship CrossOver itself: the CrossOver app's license forbids passing
# its files on. Its Wine *source* is LGPL, so a build of it can be shared
# (along with where to get the source). Apple's GPTK license lets the files in
# its /redist folder be shared unchanged and for non-commercial use only
# (sections 2A(iii) and 2C), so they go in as-is, with Apple's License and
# Acknowledgements beside them.
#
# Usage:
#   ./scripts/build_gptk_runtime.sh <apple-redist-dir> [output-dir]
#
#   <apple-redist-dir>  The "redist" folder from Apple's "Evaluation environment
#                       for Windows games" disk image, with Apple's License.rtf
#                       and Acknowledgements.rtf one level above it.
#   [output-dir]        Where the runtime and its .tar.xz go
#                       (default: .build/gptk-runtime).
#
# Env:
#   DEPS_LIB  Folder of x86_64 builds of the libraries Wine loads at runtime
#             (freetype, gnutls and what they need, SDL2). Defaults to the
#             lib folder of the Gcenx GPTK runtime BEER installs.
#   WORK      Build folder (default: a temporary one). Must have no spaces,
#             since Wine's build can't cope with them.
#   SDKROOT   The macOS SDK Wine builds against (default: the Command Line
#             Tools' macOS 15 SDK). Must be the oldest macOS the runtime
#             supports, or configure turns on functions older Macs lack.
#
# x86_64, because GPTK's Wine runs under Rosetta. Needs Homebrew's bison,
# gettext, freetype, gnutls and mingw-w64.
set -euo pipefail

CX_VERSION="26.3.0"
# Bumped for a rebuild of the same Wine and D3DMetal, so BEER sees a new
# release (it installs one folder per tag and never re-downloads a tag).
REVISION="2"
# Apple's D3DMetal 4 needs macOS 15. Wine is built against this macOS's SDK,
# and every binary is checked against it before packing.
MINIMUM_MACOS="15"
CX_SHA256="ac99c8ca4b3848f3e81784135f023df266b61c2345726ea55a50b3e030dd6872"
CX_URL="https://media.codeweavers.com/pub/crossover/source/crossover-sources-$CX_VERSION.tar.gz"
CX_SOURCE_PAGE="https://www.codeweavers.com/crossover/source"
SDL_VERSION="2.32.10"
# Vulkan for Wine (and DXVK). The private-API build, as BEER's DXVK setup uses.
MVK_VERSION="1.4.2"
MVK_SHA256="282099b522f2371a5fc1c2f0956daffb7235ee3bb28a2d0c65d8dc00397b6c1a"
MVK_URL="https://github.com/KhronosGroup/MoltenVK/releases/download/v$MVK_VERSION/MoltenVK-macos-privateapi.tar"
# What a complete runtime ships beside Wine (CrossOver and Gcenx's GPTK both
# do): Wine Mono for .NET games, Wine Gecko for web pages inside programs, and
# GStreamer for video and audio playback. Mono and Gecko are the versions this
# CrossOver release asks for (dlls/appwiz.cpl/addons.c).
MONO_VERSION="10.4.1"
MONO_SHA256="a16606ef0724202e6a6848ece6e0cbba64d11e2f11aefe744af1d93c6d9f99bb"
GECKO_VERSION="2.47.4"
GECKO_X86_SHA256="2cfc8d5c948602e21eff8a78613e1826f2d033df9672cace87fed56e8310afb6"
GECKO_X64_SHA256="fd88fc7e537d058d7a8abf0c1ebc90c574892a466de86706a26d254710a82814"
GST_VERSION="1.28.8"
GST_SHA256="d371ab04a7632713626836c2fc234e863cc98484c74c473eba99b0fbd9b3a3fe"
GST_DEVEL_SHA256="e6d380bc17be7eccf13e0154567d4718fc9321da822408c7ca0cd808b3d4a3f7"
GST_URL="https://gstreamer.freedesktop.org/data/pkg/osx/$GST_VERSION"
# File-change notifications (FindFirstChangeNotification); only its header is
# needed, the library comes with the others.
INOTIFY_VERSION="20240724"
INOTIFY_SHA256="5cc3fb7af407b17b7daa871cc98bb882716c4b5c296fadfb66bfe86c37cc599c"
# CrossOver's fallback fonts, for programs that ask for fonts Wine lacks.
VERA_SHA256="db5b27df7bbb318036ebdb75acd3e98f1bd6eb6608fb70a67d478cd243d178dc"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REDIST="${1:?usage: $0 <apple-redist-dir> [output-dir]}"
REDIST="$(cd "$REDIST" && pwd)"
APPLE_DOCS="$(dirname "$REDIST")"
OUT="${2:-$REPO_ROOT/.build/gptk-runtime}"
CACHE="$REPO_ROOT/.build/gptk-runtime-cache"
DEPS_LIB="${DEPS_LIB:-$HOME/Library/Application Support/BEER/Runtimes/GPTK-Game-Porting-Toolkit-3.0-3/Game Porting Toolkit.app/Contents/Resources/wine/lib}"
BREW="$(brew --prefix)"

die() { echo "error: $*" >&2; exit 1; }

# Downloads $2 into the cache as $1 (once) and checks it against $3.
fetch() {
    local file="$CACHE/$1"
    if [ ! -f "$file" ]; then
        echo "==> Downloading $1…" >&2
        curl -fL -o "$file.part" "$2" && mv "$file.part" "$file"
    fi
    echo "$3  $file" | shasum -a 256 -c - >&2
    echo "$file"
}

[ -f "$REDIST/lib/external/libd3dshared.dylib" ] || die "no lib/external/libd3dshared.dylib in $REDIST"
[ -d "$REDIST/lib/wine/x86_64-windows" ] || die "no lib/wine/x86_64-windows in $REDIST"
[ -f "$APPLE_DOCS/License.rtf" ] || die "Apple's License.rtf must sit next to $REDIST"
[ -f "$DEPS_LIB/libfreetype.6.dylib" ] || die "no x86_64 libfreetype.6.dylib in DEPS_LIB ($DEPS_LIB)"

D3DMETAL_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
    "$REDIST/lib/external/D3DMetal.framework/Versions/A/Resources/Info.plist")"
NAME="gptk-$D3DMETAL_VERSION-winecx-$CX_VERSION-$REVISION"

# Built against the newest SDK, configure finds functions that only exist on
# the newest macOS (pipe2 is macOS 27), and Wine calls them unguarded: on an
# older macOS the import is null and every Wine process segfaults at startup.
export SDKROOT="${SDKROOT:-/Library/Developer/CommandLineTools/SDKs/MacOSX$MINIMUM_MACOS.sdk}"
[ -f "$SDKROOT/usr/lib/libSystem.B.tbd" ] \
    || die "no macOS $MINIMUM_MACOS SDK at $SDKROOT (install the Command Line Tools, or set SDKROOT)"

if [ -z "${WORK:-}" ]; then
    WORK="$(mktemp -d -t beer-gptk)"
    trap 'rm -rf "$WORK"' EXIT
fi
case "$WORK" in *" "*) die "WORK must not contain spaces: $WORK" ;; esac
mkdir -p "$CACHE" "$WORK"

# --- Sources ---------------------------------------------------------------
TARBALL="$CACHE/crossover-sources-$CX_VERSION.tar.gz"
if [ ! -f "$TARBALL" ]; then
    echo "==> Downloading CrossOver $CX_VERSION source…"
    curl -fL -o "$TARBALL" "$CX_URL"
fi
echo "$CX_SHA256  $TARBALL" | shasum -a 256 -c -

if [ ! -d "$WORK/src/wine" ]; then
    echo "==> Unpacking…"
    mkdir -p "$WORK/src"
    tar xzf "$TARBALL" -C "$WORK/src" --strip-components 1 sources/wine
fi
# winedbg includes a header the CrossOver product build generates.
cat > "$WORK/src/wine/programs/winedbg/distversion.h" <<'EOF'
#define WINDEBUG_WHAT_HAPPENED_MESSAGE "This can be caused by a problem in the program or a deficiency in Wine."
#define WINDEBUG_USER_SUGGESTION_MESSAGE "Check the log for any missing native dependencies."
EOF

# SDL2's headers, for winebus (the controller driver). BEER's own SDL build
# (scripts/build_sdl.sh) caches the same release.
SDL_TARBALL="$REPO_ROOT/.build/sdl/SDL2-$SDL_VERSION.tar.gz"
[ -f "$SDL_TARBALL" ] || die "run scripts/build_sdl.sh once first (needs $SDL_TARBALL)"
if [ ! -d "$WORK/sdl" ]; then
    mkdir -p "$WORK/sdl"
    tar xzf "$SDL_TARBALL" -C "$WORK/sdl" --strip-components 1
fi

# The x86_64 libraries Wine links against. Copied to a space-free path, which
# is also what ships in the runtime's lib folder.
mkdir -p "$WORK/deps"
for pattern in 'libfreetype*' 'libgnutls*' 'libSDL2*' 'libz.*' 'libbz2*' 'libpng*' \
               'libbrotli*' 'libnettle*' 'libhogweed*' 'libgmp*' 'libidn2*' 'libintl*' \
               'libiconv*' 'libunistring*' 'libtasn1*' 'libp11-kit*' 'libffi*' \
               'libzstd*' 'libMacportsLegacy*' 'libcharset*' 'libinotify*'; do
    find "$DEPS_LIB" -maxdepth 1 -name "$pattern" -exec cp -a {} "$WORK/deps/" \;
done
[ -f "$WORK/deps/libinotify.0.dylib" ] || die "no x86_64 libinotify.0.dylib in DEPS_LIB ($DEPS_LIB)"
MVK_TARBALL="$(fetch "MoltenVK-$MVK_VERSION-macos-privateapi.tar" "$MVK_URL" "$MVK_SHA256")"
tar xf "$MVK_TARBALL" -C "$WORK/deps" --strip-components 5 \
    MoltenVK/MoltenVK/dynamic/dylib/macOS/libMoltenVK.dylib

INOTIFY_TARBALL="$(fetch "libinotify-$INOTIFY_VERSION.tar.gz" \
    "https://github.com/libinotify-kqueue/libinotify-kqueue/releases/download/$INOTIFY_VERSION/libinotify-$INOTIFY_VERSION.tar.gz" \
    "$INOTIFY_SHA256")"
mkdir -p "$WORK/inotify"
tar xzf "$INOTIFY_TARBALL" -C "$WORK/inotify" --strip-components 1 "libinotify-$INOTIFY_VERSION/sys/inotify.h"

# GStreamer: the official macOS framework, all of it, as Gcenx's GPTK ships
# (including the codecs games' cutscenes use: H.264 via libav, AAC, MP3).
# Two copies: the runtime alone (shipped) and runtime + developer files (to
# build against).
GST_PKG="$(fetch "gstreamer-1.0-$GST_VERSION-universal.pkg" \
    "$GST_URL/gstreamer-1.0-$GST_VERSION-universal.pkg" "$GST_SHA256")"
GST_DEVEL_PKG="$(fetch "gstreamer-1.0-devel-$GST_VERSION-universal.pkg" \
    "$GST_URL/gstreamer-1.0-devel-$GST_VERSION-universal.pkg" "$GST_DEVEL_SHA256")"
# Unpacks an installer's component packages into a framework at $2. With
# "shipped" as $3, leaves out the GTK4 and Python plugins, which Wine never
# loads (Gcenx's GPTK leaves them out too). Devtools stays: the editing plugins
# (ges, nle) need its libgstvalidate.
unpack_gstreamer() {
    local expanded="$WORK/gst-expanded-$(basename "$1" .pkg)" comp
    rm -rf "${expanded:?}"
    pkgutil --expand-full "$1" "$expanded"
    for comp in "$expanded"/*.pkg; do
        [ -d "$comp/Payload" ] || continue
        case "${3:-}:$(basename "$comp")" in
            shipped:gstreamer-1.0-gtk-*|shipped:gstreamer-1.0-python-*) continue ;;
        esac
        case "$(basename "$comp")" in
            osx-framework-*) ditto "$comp/Payload" "$2" ;;
            *) ditto "$comp/Payload" "$2/Versions/1.0" ;;
        esac
    done
    rm -rf "${expanded:?}"
}
GST_RUNTIME="$WORK/gst-runtime/GStreamer.framework"
GST_DEVEL="$WORK/gst-devel/GStreamer.framework"
if [ ! -d "$GST_RUNTIME" ]; then
    echo "==> Unpacking GStreamer $GST_VERSION…"
    unpack_gstreamer "$GST_PKG" "$GST_RUNTIME" shipped
    # Command-line programs (gst-launch and the like). The plugin scanner
    # GStreamer itself runs lives in libexec and stays.
    rm -rf "${GST_RUNTIME:?}/Versions/1.0/bin"
    # Newer plugins for cloud services, streaming servers and machine learning
    # (AWS, ElevenLabs, WebRTC, …). Wine only decodes a game's own media; the
    # decoders among the newer plugins (dav1d for AV1, isobmff, lewton, claxon,
    # gif, …) stay. What remains still covers every plugin Gcenx's GPTK ships.
    for plugin in rswebrtc aws burn quinn webrtchttp elevenlabs reqwest rsrtsp rstracers \
                  icecast speechmatics rsaudiofx rsrtp demucs threadshare rav1e rsclosedcaption \
                  regex rsvideofx ndi rsonvif fallbackswitch raptorq hlsmultivariantsink \
                  rsanalytics hlssink3 textwrap togglerecord rsinter livesync json \
                  uriplaylistbin hsv mpegtslive gopbuffer streamgrouper originalbuffer textahead; do
        rm -f "${GST_RUNTIME:?}/Versions/1.0/lib/gstreamer-1.0/libgst$plugin.dylib"
    done
fi
if [ ! -d "$GST_DEVEL" ]; then
    unpack_gstreamer "$GST_PKG" "$GST_DEVEL"
    unpack_gstreamer "$GST_DEVEL_PKG" "$GST_DEVEL"
fi
GST_ROOT="$GST_DEVEL/Versions/1.0"
[ -f "$GST_ROOT/include/gstreamer-1.0/gst/gst.h" ] || die "GStreamer headers missing from $GST_DEVEL_PKG"
# Their install names are bare ("libfreetype.dylib"), which the build tools
# that link them can't resolve. @rpath names can be; editing the name breaks
# the signature, so sign again (ad hoc).
find "$WORK/deps" -type f -name '*.dylib' | while read -r lib; do
    install_name_tool -id "@rpath/$(basename "$lib")" "$lib" 2>/dev/null
    codesign --force -s - "$lib" 2>/dev/null
done

# --- Configure and build ---------------------------------------------------
export PATH="$BREW/opt/bison/bin:$BREW/opt/gettext/bin:$BREW/bin:$PATH"
export CC="clang -arch x86_64 -isysroot $SDKROOT"
export CXX="clang++ -arch x86_64 -isysroot $SDKROOT"
export CFLAGS="-O2"
export CROSSCFLAGS="-O2 -Wno-error=incompatible-pointer-types"
export LDFLAGS="-L$WORK/deps -Wl,-headerpad_max_install_names -Wl,-rpath,@loader_path/../../"
export MACOSX_DEPLOYMENT_TARGET="11.0"
# Hand configure the flags directly: Homebrew's pkg-config files point at
# arm64 libraries, which an x86_64 link can't use.
export PKG_CONFIG=false
export FREETYPE_CFLAGS="-I$BREW/opt/freetype/include/freetype2"
# Only build tools (sfnt2fon) link freetype directly, and they run during the
# build, so they need to find it; Wine itself loads it by name at runtime.
export FREETYPE_LIBS="-L$WORK/deps -lfreetype -Wl,-rpath,$WORK/deps"
export GNUTLS_CFLAGS="-I$BREW/opt/gnutls/include -I$BREW/opt/nettle/include -I$BREW/opt/libtasn1/include -I$BREW/opt/p11-kit/include/p11-kit-1"
export GNUTLS_LIBS="-L$WORK/deps -lgnutls"
export SDL2_CFLAGS="-I$WORK/sdl/include"
export SDL2_LIBS="-L$WORK/deps -lSDL2"
export INOTIFY_CFLAGS="-I$WORK/inotify"
export INOTIFY_LIBS="-L$WORK/deps -linotify"
# winegstreamer finds the shipped framework next to Wine, as in Gcenx's GPTK.
export GSTREAMER_CFLAGS="-I$GST_ROOT/include/gstreamer-1.0 -I$GST_ROOT/include/glib-2.0 -I$GST_ROOT/lib/glib-2.0/include -I$GST_ROOT/include"
export GSTREAMER_LIBS="-L$GST_ROOT/lib -lgstvideo-1.0 -lgstaudio-1.0 -lgsttag-1.0 -lgstbase-1.0 -lgstreamer-1.0 -lgobject-2.0 -lglib-2.0 -Wl,-rpath,@loader_path/../../GStreamer.framework/Libraries"

BUILD="$WORK/build"
mkdir -p "$BUILD"
cd "$BUILD"
if [ ! -f Makefile ]; then
    echo "==> Configuring Wine (CrossOver $CX_VERSION)…"
    "$WORK/src/wine/configure" \
        --build=x86_64-apple-darwin \
        --prefix= \
        --disable-tests \
        --enable-archs=i386,x86_64 \
        --without-alsa --without-capi --with-coreaudio --without-cups \
        --without-dbus --without-fontconfig --with-freetype --with-gettext \
        --without-gettextpo --without-gphoto --with-gnutls --without-gssapi \
        --with-gstreamer --with-inotify --without-krb5 --with-mingw \
        --without-netapi --without-oss --with-pcap \
        --with-pthread --without-pulse --without-sane --with-sdl --without-udev \
        --with-unwind --without-usb --without-v4l2 --without-x \
        > "$WORK/configure.log" 2>&1 || { tail -40 "$WORK/configure.log"; die "configure failed (log: $WORK/configure.log)"; }
fi

echo "==> Building Wine (this takes a while)…"
make -j"$(sysctl -n hw.ncpu)" > "$WORK/make.log" 2>&1 \
    || { tail -40 "$WORK/make.log"; die "build failed (log: $WORK/make.log)"; }

# --- Assemble the runtime ----------------------------------------------------
# Assembled in WORK, since Wine's install can't cope with spaces in the path
# (and this repo's folder may have them), then moved to OUT.
STAGE="$WORK/stage/$NAME"
rm -rf "$STAGE"
mkdir -p "$STAGE"
echo "==> Installing into $STAGE…"
make install-lib DESTDIR="$STAGE" > "$WORK/install.log" 2>&1 \
    || { tail -40 "$WORK/install.log"; die "install failed (log: $WORK/install.log)"; }
# BEER (and Apple's instructions) run bin/wine64.
[ -e "$STAGE/bin/wine64" ] || ln -s wine "$STAGE/bin/wine64"

cp -a "$WORK/deps/." "$STAGE/lib/"

# Drop debug info, as release runtimes do (and the reason a build is larger
# than CrossOver's otherwise). Editing a binary breaks its signature, so sign
# the host-side ones again (ad hoc).
echo "==> Stripping debug info…"
# --strip-unneeded also drops the symbol table, which is most of the size
# (leaving files the size of CrossOver's own).
for arch in i386:i686 x86_64:x86_64; do
    find "$STAGE/lib/wine/${arch%%:*}-windows" -type f \( -name '*.dll' -o -name '*.exe' -o -name '*.sys' \
        -o -name '*.drv' -o -name '*.ocx' -o -name '*.cpl' -o -name '*.acm' -o -name '*.ax' -o -name '*.ds' \) \
        -exec "${arch##*:}-w64-mingw32-strip" --strip-unneeded {} +
done
find "$STAGE/lib/wine" -path '*-unix/*' -type f -name '*.so' | while read -r so; do
    strip -S -x "$so" && codesign --force -s - "$so" 2>/dev/null
done
strip -S -x "$STAGE/bin/wineserver" && codesign --force -s - "$STAGE/bin/wineserver" 2>/dev/null
# Wine's windows come from bin/wine, the program macOS sees. Linked against
# the macOS 26+ SDK it gets macOS's see-through title bar, which shows
# whatever is behind Wine's windows. Record the macOS 15 SDK instead, as
# CrossOver's own build does, for the opaque title bar.
strip -S -x "$STAGE/bin/wine"
vtool -set-build-version macos "$MACOSX_DEPLOYMENT_TARGET" 15.0 -replace \
    -output "$STAGE/bin/wine" "$STAGE/bin/wine" 2>/dev/null
codesign --force -s - "$STAGE/bin/wine" 2>/dev/null

echo "==> Adding GStreamer $GST_VERSION…"
ditto "$GST_RUNTIME" "$STAGE/lib/GStreamer.framework"
# The framework is universal; Wine runs x86_64 only, so keep that half (and
# sign each trimmed file again, ad hoc).
find "$STAGE/lib/GStreamer.framework" -type f | while read -r f; do
    archs="$(lipo -archs "$f" 2>/dev/null)" || continue
    case "$archs" in
        *x86_64*" "*|*" "*x86_64*)
            lipo -thin x86_64 "$f" -output "$f.thin" && mv "$f.thin" "$f"
            codesign --force -s - "$f" 2>/dev/null ;;
    esac
done
mkdir -p "$STAGE/share/licenses/gstreamer"
cp -R "$GST_RUNTIME/Versions/1.0/share/licenses/." "$STAGE/share/licenses/gstreamer/" 2>/dev/null || true

echo "==> Adding Wine Mono $MONO_VERSION and Wine Gecko $GECKO_VERSION…"
MONO_TARBALL="$(fetch "wine-mono-$MONO_VERSION-x86.tar.xz" \
    "https://dl.winehq.org/wine/wine-mono/$MONO_VERSION/wine-mono-$MONO_VERSION-x86.tar.xz" "$MONO_SHA256")"
GECKO_X86_TARBALL="$(fetch "wine-gecko-$GECKO_VERSION-x86.tar.xz" \
    "https://dl.winehq.org/wine/wine-gecko/$GECKO_VERSION/wine-gecko-$GECKO_VERSION-x86.tar.xz" "$GECKO_X86_SHA256")"
GECKO_X64_TARBALL="$(fetch "wine-gecko-$GECKO_VERSION-x86_64.tar.xz" \
    "https://dl.winehq.org/wine/wine-gecko/$GECKO_VERSION/wine-gecko-$GECKO_VERSION-x86_64.tar.xz" "$GECKO_X64_SHA256")"
# Where Wine looks for them, the same layout CrossOver and Gcenx use.
mkdir -p "$STAGE/share/wine/mono" "$STAGE/share/wine/gecko"
tar xJf "$MONO_TARBALL" -C "$STAGE/share/wine/mono"
tar xJf "$GECKO_X86_TARBALL" -C "$STAGE/share/wine/gecko"
tar xJf "$GECKO_X64_TARBALL" -C "$STAGE/share/wine/gecko"

VERA_TARBALL="$(fetch "ttf-bitstream-vera-1.10.tar.bz2" \
    "https://download.gnome.org/sources/ttf-bitstream-vera/1.10/ttf-bitstream-vera-1.10.tar.bz2" "$VERA_SHA256")"
mkdir -p "$WORK/vera"
tar xjf "$VERA_TARBALL" -C "$WORK/vera" --strip-components 1
cp "$WORK/vera/"*.ttf "$STAGE/share/wine/fonts/"
mkdir -p "$STAGE/share/licenses/bitstream-vera"
cp "$WORK/vera/COPYRIGHT.TXT" "$STAGE/share/licenses/bitstream-vera/"

echo "==> Adding Apple's D3DMetal $D3DMETAL_VERSION…"
# Same as Apple's Read Me: Apple's lib/external and lib/wine go over Wine's own
# (merged, so Wine's other DLLs stay). Files are copied unchanged.
ditto "$REDIST/lib/" "$STAGE/lib/"
# MetalFX (DLSS) support, as Apple's Read Me describes: the shim takes the
# name games look for.
for dir in x86_64-unix x86_64-windows; do
    ext=$([ "$dir" = x86_64-unix ] && echo so || echo dll)
    src="$STAGE/lib/wine/$dir/nvngx-on-metalfx.$ext"
    [ -f "$src" ] && mv "$src" "$STAGE/lib/wine/$dir/nvngx.$ext"
done

mkdir -p "$STAGE/share/licenses/apple-gptk" "$STAGE/share/licenses/wine"
cp "$APPLE_DOCS/License.rtf" "$STAGE/share/licenses/apple-gptk/"
[ -f "$APPLE_DOCS/Acknowledgements.rtf" ] && cp "$APPLE_DOCS/Acknowledgements.rtf" "$STAGE/share/licenses/apple-gptk/"
cp "$WORK/src/wine/COPYING.LIB" "$WORK/src/wine/LICENSE" "$STAGE/share/licenses/wine/" 2>/dev/null || true
cat > "$STAGE/README.txt" <<EOF
BEER GPTK runtime: $NAME

Wine: built from CodeWeavers' CrossOver $CX_VERSION source (LGPL 2.1).
  Source: $CX_URL
  More:   $CX_SOURCE_PAGE
D3DMetal $D3DMETAL_VERSION: Apple's Game Porting Toolkit redistributables,
  unmodified, shared for non-commercial use under Apple's license
  (share/licenses/apple-gptk/License.rtf).
GStreamer $GST_VERSION: the official macOS framework (LGPL; some codec
  plugins GPL), trimmed to x86_64. Source: https://gstreamer.freedesktop.org/src/
Wine Mono $MONO_VERSION and Wine Gecko $GECKO_VERSION: https://dl.winehq.org/wine/
MoltenVK $MVK_VERSION (Apache 2.0): https://github.com/KhronosGroup/MoltenVK
Bitstream Vera fonts: share/licenses/bitstream-vera/COPYRIGHT.TXT

This is not CrossOver and is not made or supported by CodeWeavers or Apple.
EOF

# Marks this as BEER's own build (new games prefer it) and the macOS it needs:
# Apple's D3DMetal 4 needs macOS 15. Read by BEERRuntimeManifest.
cat > "$STAGE/beer-runtime.json" <<EOF
{
  "d3dMetalVersion": "$D3DMETAL_VERSION",
  "crossOverSourceVersion": "$CX_VERSION",
  "minimumMacOS": $MINIMUM_MACOS
}
EOF

# Every system function the runtime calls must exist on its oldest macOS. A
# missing one is a crash there (a weak import is null) or a refusal to load,
# and the Mac this builds on never shows it. Checked against the macOS
# $MINIMUM_MACOS SDK's libSystem, which is what every binary here links.
echo "==> Checking the runtime against macOS $MINIMUM_MACOS…"
cat "$SDKROOT"/usr/lib/libSystem.B.tbd "$SDKROOT"/usr/lib/system/*.tbd \
    | grep -oE "[A-Za-z_][A-Za-z0-9_\$.]*" | sort -u > "$WORK/sdk-symbols.txt"
: > "$WORK/too-new.txt"
find "$STAGE" -type f | while read -r f; do
    file -b "$f" | grep -q '^Mach-O' || continue
    nm -m "$f" 2>/dev/null | awk '/\(undefined\)/ && /\(from libSystem\)/ { for (i = 1; i <= NF; i++) if ($i == "(from") print $(i - 1) }' \
        | sort -u | comm -23 - "$WORK/sdk-symbols.txt" | sed "s|^|${f#$STAGE/}: |" >> "$WORK/too-new.txt"
done
if [ -s "$WORK/too-new.txt" ]; then
    cat "$WORK/too-new.txt" >&2
    die "these call functions macOS $MINIMUM_MACOS doesn't have"
fi

echo "==> Packing…"
mkdir -p "$OUT"
rm -rf "${OUT:?}/$NAME"
mv "$STAGE" "$OUT/$NAME"
tar -C "$OUT" -cJf "$OUT/$NAME.tar.xz" "$NAME"
echo "built $OUT/$NAME.tar.xz"
