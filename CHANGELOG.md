# Changelog

Notable changes to BEER. Versions follow the GitHub releases.

## 0.4.0 — 2026-09-15

The first release where BEER behaves like a Steam client instead of just a
launcher: your account shows as online, friends see what you're playing, hours
count, DLC installs, and controllers work.

### Added
- **Steam presence and play time.** BEER keeps one live Steam session for as
  long as the app is open. Your account shows as online, friends see the game
  you're playing, and time played comes back to your Steam profile when you
  quit — the same hours you'd get from the real client. Status (Online, Away,
  Invisible, Offline) is picked in the app.
- **DLC support.** Each game's page lists its DLC and what your account owns.
  Installing one pulls it into the existing game directory and declares the
  entitlement to the Steamworks shim, so the game actually sees it.
- **Controller support.** BEER now tells Wine about whatever gamepads macOS
  reports, instead of relying on Wine's short list of known IDs — which is why
  Steam's virtual pad used to be invisible to games. An optional per-game
  **Controller Fix** restores the D-pad, stick orientation and Start/Back/L3/R3
  for virtual pads (Steam Input's included); build it once with
  `Tools/ControllerFix/build.sh`.
- **Runtime Manager.** A dedicated pane for downloading and managing Wine
  runtimes and graphics translators (DXVK/DXMT). Which runtime a game uses now
  lives in that game's Advanced settings rather than a global setting.
- **GPTK 4.0 runtime script.** `scripts/install_gptk4.sh` builds a GPTK 4.0
  runtime by overlaying Apple's D3DMetal onto a GPTK Wine base; BEER picks it
  up automatically. Requires macOS 15.
- **High Resolution display mode**, alongside Standard, for games that should
  see Retina resolutions.
- **Per-game launch arguments and environment variables**, with one-click
  presets for the failures that have known fixes — SDL3 games that crash on
  startup, OpenGL games that won't create a context, crackling SDL audio, plus
  the Metal and DXVK performance overlays.
- **Per-game Windows version**, so a game can be told it's on the Windows
  release it expects.
- **Redesigned game page** built around Steam's own library artwork, with hours
  played, install status, DLC, Advanced settings and a log viewer in one place.

### Changed
- **No more QR scan per install.** Downloads reuse the Steam token already in
  your Keychain, so signing in once covers installs, cloud saves and presence.
- **Faster cloud sync.** Files whose contents already match are skipped
  (SHA-1 compared, not timestamped), and transfers run concurrently.
- **Removed the legacy "run the full Steam client in Wine" workflow** and manual
  bottle creation. Games are per-game bottles, which is the path that works.

### Fixed
- Games now launch from their own directory, fixing titles that look for files
  next to the executable.
- Cloud sync: no-op uploads are skipped, conflicts compare actual file contents,
  and Steam-wrapped save files are unwrapped before being written to disk.
- Steam logons retry transient disconnects instead of failing the sync.
- The Runtime tab no longer comes up blank.
- DLC that failed to download in the first pass now installs.

## 0.3.3 — 2026-06-16
- Fixed games failing to launch after the GameNativeMac → BEER rename: stale
  absolute paths stored in bottles are rewritten on load.

## 0.3.2 — 2026-06-16
- Added the app icon. No functional changes.

## 0.3.1 — 2026-06-16
- Renamed the project to **BEER** (Bottled Executable Environment Runner).
- Steam refresh token moved from a plaintext file into the macOS Keychain, with
  automatic migration of existing installs.

## 0.3.0
- Per-game runtime selection, GPTK and mainline Wine downloads, DXVK/DXMT
  graphics translators, Goldberg using your real SteamID, and a fix for save
  paths breaking when a bottle switched runtimes.

## 0.2.x
- Bidirectional Steam Cloud save sync via the native SteamKit2 helper, with a
  local backup taken before every sync.
- Per-game installs through DepotDownloader into isolated Wine bottles.
- Distributable, ad-hoc signed `BEER.app`.
