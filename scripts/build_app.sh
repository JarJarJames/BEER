#!/usr/bin/env bash
set -euo pipefail

# Builds a distributable BEER.app:
#   • compiles the SwiftUI app in release
#   • publishes the native CloudSync helper (SteamKit2) and bundles it inside
#     the .app so a fresh machine needs no extra setup
#   • ad-hoc code-signs the bundle so it launches
#   • zips it for download (.build/BEER.zip)
#
# DepotDownloader, Goldberg and the GPTK runtime are still fetched by the app
# itself on first run (the onboarding flow), so they are not bundled here.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

VERSION="${1:-0.2.0}"

echo "==> Building Swift app (release)…"
swift build -c release

APP_DIR="$ROOT_DIR/.build/BEER.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"
cp "$ROOT_DIR/.build/release/BEER" "$MACOS/BEER"
cp "$ROOT_DIR/icon/AppIcon.icns" "$RESOURCES/AppIcon.icns"

echo "==> Publishing CloudSync helper (self-contained osx-arm64)…"
dotnet publish "$ROOT_DIR/Tools/CloudSync/CloudSync.csproj" \
    -c Release -r osx-arm64 --self-contained true \
    -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true \
    -o "$ROOT_DIR/Tools/CloudSync/publish" >/dev/null
# Bundled next to the app executable — CloudSyncClient.locateBinary() looks
# for "CloudSync" alongside the running executable (Contents/MacOS).
cp "$ROOT_DIR/Tools/CloudSync/publish/CloudSync" "$MACOS/CloudSync"
chmod +x "$MACOS/CloudSync"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>BEER</string>
  <key>CFBundleIdentifier</key>
  <string>io.github.jarjarjames.beer</string>
  <key>CFBundleName</key>
  <string>BEER</string>
  <key>CFBundleDisplayName</key>
  <string>BEER</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${VERSION}</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

# Strip extended attributes (quarantine, Finder info) that make codesign
# reject the bundle with "resource fork … not allowed".
xattr -cr "$APP_DIR"

# Deliberately ad-hoc, not the local dev signing identity: "BEER Local Dev"
# (scripts/setup_local_codesign_identity.sh) is trusted only in the keychain
# that created it. Signing a build meant for OTHER people's Macs with it
# would buy them nothing — their Gatekeeper has never heard of that identity
# either way — so this stays ad-hoc, same as every previous release. Anyone
# running the shipped app still needs the `xattr -dr com.apple.quarantine`
# step in the README/release notes; the app's own quarantine self-heal
# (CloudSyncClient.locateBinary) covers the bundled CloudSync helper
# specifically, which is the part that used to SIGKILL silently.
echo "==> Ad-hoc code-signing…"
codesign --force --deep --sign - "$APP_DIR"

echo "==> Zipping for distribution…"
ZIP="$ROOT_DIR/.build/BEER.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP_DIR" "$ZIP"

echo ""
echo "Built:  $APP_DIR"
echo "Zip:    $ZIP"
