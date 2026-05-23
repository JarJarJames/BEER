# GameNative for Mac

An experimental native macOS bottle manager for installing and running Windows Steam in isolated Wine/CrossOver-style environments.

This is inspired by the container-based workflow used by GameNative on Android, but macOS works better with Wine prefixes, also known as bottles, than with Docker-style containers for games.

## Current MVP

- Detects Wine-like runtimes from Homebrew, CrossOver, Whisky, and common Game Porting Toolkit locations.
- Fetches and installs the latest managed Gcenx Game Porting Toolkit runtime from GitHub.
- Creates isolated per-game/per-library `WINEPREFIX` bottles under Application Support.
- Persists bottle metadata as JSON.
- Lets you run Wine initialization, install Steam from a selected `SteamSetup.exe`, launch Steam, reveal bottle files, and delete bottles.
- Keeps per-bottle operation logs in the UI.

## Run

```bash
swift run GameNativeMac
```

For a bundled app:

```bash
scripts/build_app.sh
open .build/GameNativeMac.app
```

## Runtime expectations

You need at least one Wine-compatible runtime installed. CrossOver is the most practical target today. Homebrew Wine, Whisky-provided Wine, or Game Porting Toolkit wrappers may work depending on your Mac and the game.

Use **Runtime Manager** in the app to download the current Gcenx Game Porting Toolkit build into:

```text
~/Library/Application Support/GameNativeMac/Runtimes/
```

Downloaded runtimes are scanned automatically and appear in the New Bottle runtime picker.

This app does not bypass Steam, DRM, anticheat, or platform restrictions. It creates isolated Windows compatibility environments and launches Steam inside them.
