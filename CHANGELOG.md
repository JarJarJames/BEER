# Changelog

Notable changes to BEER. Versions follow the GitHub releases.

## 0.7.0 — 2026-11-03

### Added
- **Restore save backups.** The Steam Cloud row's menu has **Manage or
  Restore Backups…**, which lists a game's backups with their date, size and
  file count. Restoring shows exactly what will change and backs up the
  current saves first. If the restored saves differ from Steam's, the next
  sync asks whether to keep the restored saves or use Steam's, like Steam's
  own sync conflict, and nothing uploads until you choose.
- **Install sheet with a space check.** Install, Reinstall and Validate open
  a sheet showing the game's size, where it goes and how much space is free.
  An install that won't fit with 5 GB to spare is refused before anything
  downloads, so a full disk can't leave a half-installed game. The DLC
  manager checks the same way before installing DLC.
- **Game shortcuts.** A game's menu can now put a shortcut on the Desktop or
  in Applications that opens BEER and starts the game. **Shortcut Icon…**
  picks what it shows: a square cut from the game's cover (drag and zoom to
  choose) or Steam's own Windows icon. The install sheet can make either
  shortcut as part of an install, and uninstalling a game removes the
  shortcuts BEER made. A shortcut you moved or renamed is left alone.
- **Install games to external drives.** The install sheet lists This Mac and
  every usable drive with its free space; drives a game can't run from
  (exFAT, case-sensitive) are greyed out with the reason. Only the game's
  files go on the drive: its bottle, saves and save backups stay on the Mac.
  The sheet updates live as drives are plugged in or pulled out.
- **Move games between your Mac and drives.** A game's Location row can move
  it. BEER copies the game, checks the copy, switches over, backs up any
  saves kept in the game folder, and only then deletes the old copy. A move
  cut short by a crash or a pulled drive is finished or undone the next time
  the drive is connected.
- **Games on an unplugged drive.** The game page says "Connect <drive> to
  play", and launching, cloud sync and anything that writes into the game
  folder wait until it's back. Drives are tracked by their ID, so renaming
  one doesn't lose its games, even while BEER is open.
- **Games found on a drive.** Plugging in a drive that holds games BEER
  installed elsewhere (another Mac, or before a reinstall) offers to add
  them back. Non-Steam games can be added to a drive too.

### Changed
- **The Wine log follows new output.** The Wine log and the DepotDownloader
  output keep the newest line in view, stay put when you scroll up to read,
  and follow again once you scroll back to the end.

### Fixed
- **BEER crashed while a game started or closed.** The window could get
  stuck re-laying itself out until macOS closed BEER, most often with the
  Wine log open while a game launched. The sidebar, the game page and the
  log panels now have fixed sizes, so changing content can't set this off.
- **BEER froze for seconds when a game started from a USB drive.** Every
  launch copied the Steam emulator's 44 MB of files into the game folder
  again, and the window waited for it. Files already in place are now
  skipped, and the rest are copied in the background.
- **Download status stuck on "Pre-allocating" or "Validating".** The status
  now switches to "Downloading…" once data arrives, and the game page shows
  the percentage next to it.
- **Games whose name ends in "." wouldn't start.** Windows drops a trailing
  dot, so Wine couldn't find anything inside a folder like
  "Easy Delivery Co.". New installs leave the dot off, and existing folders
  are renamed the next time BEER opens.
- **Installing a game signed you out of Steam.** BEER's downloader logged on
  with the same session ID the Steam client on your Mac uses, and Steam ends
  the older session when two match. Installs and updates now use their own
  ID, so a Steam client running alongside BEER stays signed in.
- **Cloud-save backups filled the disk.** BEER copied a game's whole save
  folder before every sync and never removed old copies, so Kingdom Come
  games alone reached hundreds of GB. It now keeps the newest 3 backups per
  game (plus every backup taken before clearing local saves), skips the copy
  when the saves haven't changed, and no longer leaves empty backup folders.
  On first launch BEER offers to apply this to backups already on disk.
- **Saves in a new folder never reached Steam Cloud.** BEER only looked for
  new saves in folders that already had cloud files, so a game's first saves
  made on the Mac, or a new save folder per playthrough, were never uploaded
  and nothing said so. It now also checks the save folders Steam lists for
  the game.
- **Saves in Documents never uploaded.** Saves under the bottle's
  `Documents` folder, which links to your Mac's, weren't matched to their
  cloud files, so games like Dark Souls Remastered couldn't upload them.
- **`build_app.sh` stopped while fetching SDL.** On a machine without SDL's
  source already downloaded, macOS's bash read the "…" in the download
  message as part of `$VERSION` and quit with "unbound variable".

## 0.6.2 — 2026-11-01

### Fixed
- **Some games opened a bundled tool instead of the game.** BEER guessed the
  .exe from its name and size, so The Binding of Isaac opened its Mod
  Uploader. It now runs the .exe Steam's own Play button runs, and keeps the
  guess only as a fallback. Games installed earlier are corrected on their
  next launch.
- **Games wrapped in Steam's DRM quit on launch.** Some executables, The
  Binding of Isaac's among them, check for a running Steam client before the
  game starts. BEER now launches those through the Steam emulator's loader,
  which answers that check.
- **Older Steam games.** The Steam emulator is now told which Steam
  interface versions each game was built against, read from the game's own
  `steam_api.dll`. Steam2-era games built on `Steam.dll`, and games that load
  Steam's client library without a `steam_api.dll`, now start through the
  loader too. Advanced Settings has a per-game Steam client loader setting
  (Automatic, Always, Off), plus two options for the rare games that need
  them.

## 0.6.1 — 2026-10-31

### Added
- **Discord Rich Presence.** While a game runs, your Discord profile shows
  "[Game] with BEER" with the game's cover art, a BEER badge, an elapsed
  timer and a "Get BEER" button. It needs only the Discord desktop app
  running, not a Discord login, and the card clears when the game exits.

### Fixed
- **Steam play time and "now playing" sometimes never recorded.** A cleanup
  step at launch could kill the Steam session BEER had just started, so
  games went unannounced and uncounted. BEER now shows when the session
  is lost instead of failing silently.

## 0.6.0 — 2026-10-30

### Added
- **Dependencies** in a game's Advanced settings: one-click install of the
  Visual C++ 2015–2026 runtime (x86 + x64) and the DirectX June 2010 runtime
  into that game's bottle. Files come only from Microsoft and are checked
  against a pinned SHA-256 before they run. Runtimes already in the bottle,
  including ones installed with winetricks, show as installed.
- **Steam's redistributable install scripts now run before launch.** Games
  list shared redistributables (Visual C++, DirectX) that Steam installs on
  first launch. BEER downloaded them into `_CommonRedist/` but never ran
  them, so a game like Kenshi exited at startup missing the VC++ 2010
  runtime. Each script entry now runs once per bottle and is recorded in
  `beer-steam-redist.log` in the prefix. A failure is logged and retried
  next launch, and the game still launches. .NET Framework installers are
  skipped because they hang under Wine.
- **Capture Display** toggle under Resolution in a game's settings. When on,
  a fullscreen game captures the display, so the Dock and menu bar can't
  appear over it and bring back a hidden cursor at the screen edges. Off by
  default, so existing games behave as before.

### Changed
- The Steam emulator row's **Test: unlock next achievement** and **Test:
  reset local unlocks** tools are now only in development builds. A test
  unlock goes through the same path as a real one, so it would reach the
  real Steam account; release builds no longer offer it.
- **Controllers go through SDL, and any mix works at once.** Xbox,
  PlayStation (DualShock 4, DualSense) and Steam controllers now all reach
  games together, so splitscreen works with whatever pads you have. Before,
  Wine never presented a PlayStation pad as an XInput controller, so games
  like Dark Souls Remastered didn't see one. BEER now has Wine read every pad
  through SDL, using BEER's own SDL build: GPTK's copy hands Xbox One/Series
  pads to Apple's GameController framework, which doesn't deliver them inside
  Wine. BEER's SDL is placed beside Wine's controller driver in the runtime;
  no runtime or game file is replaced. The Steam Controller Fix setting is
  gone, because SDL maps the Steam Controller's D-pad and buttons correctly
  itself.
- README rewritten around the architecture, cloud sync and security model,
  including a plain description of how and why the Steam emulator is used.
- Errors that were silently ignored in cloud sync, sign-in, downloads,
  achievements and play sessions now go to the macOS unified log. Filter
  Console.app on `io.github.jarjarjames.beer`. Paths and account details are
  redacted in the log.
- The CloudSync helper was restructured into one class per command, with
  offline tests. Its commands and output are unchanged. CI now builds and
  tests the app and the helper on every pull request.

### Fixed
- **A cloud sync no longer runs if its save backup fails.** The backup
  step's error was being ignored, so a sync on a full or unwritable disk
  carried on and could overwrite local saves with no copy to go back to.
  Now the sync stops before writing anything, says your saves are
  untouched, and records why in `last-sync.log`. A game still launches
  with its local saves if the pre-play pull stops this way.
- **DepotDownloader's temporary credential cache can no longer be lost
  track of.** If deleting it failed, BEER still erased its record of where
  the cache was, so the crash-recovery cleanup could never find it again.
  The record now stays until the cache is really gone.
- "Back up & clear local saves" reports a folder it couldn't delete instead
  of saying the saves were cleared.
- **BEER no longer freezes when a game floods its log.** The in-app log
  kept every line in memory and copied the whole list on each new one, so a
  game run with a verbose `WINEDEBUG` channel could lock up the app. It now
  keeps the most recent 2,000 lines; `beer.log` in the bottle still has
  everything.

### Security
- Releases before 0.5.0 were withdrawn. Builds before 0.3.1 stored Steam
  credentials (a Web API key before 0.2.1, then the refresh token) in
  plaintext files. Current builds keep the token in the Keychain. See
  `SECURITY.md` for what to do if you used an old build.

## 0.5.1 — 2026-10-07

Non-Steam games, in testing.

### Added
- **Add Non-Steam Game.** A **+** button in the library toolbar adds a game
  you already have on disk. Pick its folder and executable, optionally a
  cover image, and choose whether to move or copy the folder into BEER. The
  game gets its own GPTK bottle with the same graphics, display, controller
  and launch settings as a Steam game, and its folder lives in the bottle's
  `drive_c/Games` next to the rest. Steam-only features (Cloud sync, play
  time, achievements, DLC, the Steam emulator) don't apply and are hidden.
  Removing one asks first, since it deletes the folder BEER holds.
  Early: expect rough edges.

### Fixed
- Failed DepotDownloader installs now leave a per-app log, and the
  "not owned" message names the app instead of a generic value.

## 0.5.0 — 2026-10-07

Steam achievements, and a source tree that's easier to work in.

### Added
- **Steam achievements.** When BEER applies the Steam emulator to a game
  (on install, or from the game's settings), it now seeds the emulator with
  the game's real achievement list from Steam. While the game runs, BEER
  watches for unlocks and shows a toast in its own always-on-top overlay
  window, so it appears over the game rather than behind it, with a sound.
  Each unlock is also pushed to your real Steam account. Unlocks that can't
  reach Steam (offline, expired sign-in) are queued and retried the next
  time BEER starts.
- **Achievement testing tools.** On a game with the emulator applied, the
  Steam emulator row's menu can unlock the next achievement locally and reset
  the local test state, to try the toast and sync path without playing for
  it. Resetting only clears BEER's local record; real Steam unlocks stay.

### Changed
- `swift build` and `swift run` now rebuild the CloudSync helper whenever its
  sources change (a SwiftPM build-tool plugin), so the helper is always
  current without running `scripts/build_cloudsync.sh` by hand.
- **Source reorganized for contributors; no behavior change.** `Sources/BEER/`
  is now grouped into `Managers/`, `Installers/`, `ViewModel/`, `Model/`,
  `Utilities/`, `Extensions/`, `Constants/` and `View/`, with one type per
  file and no file past about 300 lines. The 1,700-line game detail screen is
  split into a view model plus one view per settings row, and the DLC
  manager, runtime manager, library grid and both QR sign-in screens got the
  same treatment. The folder map and placement rules are in
  `PROJECT_STRUCTURE.md`, linked from `AGENTS.md`.

### Fixed
- **App freezing before a game starts.** The controller HID lookup and
  helper launch are now capped at 3 seconds. A Bluetooth pad that stopped
  answering could block the main thread indefinitely, hanging BEER before
  Wine ever started.

## 0.4.2 — 2026-09-17

### Fixed
- **Cloud sync could silently lose its result on larger syncs**, surfacing
  as "Couldn't understand the CloudSync helper's output" even though
  nothing was actually wrong with the helper or its version. The cause was
  in BEER itself: it treated the helper's process-termination notification
  as the signal that all of its output had arrived, but termination and the
  pipe finishing delivery are two independent events with no guaranteed
  order — a large result (hundreds of cloud files) could still be in
  transit when termination fired, and that tail got silently dropped. BEER
  now waits for the pipe's own end-of-file, the only signal that actually
  guarantees nothing more is coming, before treating a sync's output as
  complete.

## 0.4.1 — 2026-09-16

### Fixed
- **Cloud sync crashing with "Couldn't understand the CloudSync helper's
  output."** A distributed BEER.app's bundled CloudSync helper could keep a
  leftover quarantine flag from being downloaded/unzipped, which macOS
  doesn't always clear from a helper launched as a subprocess — the kernel
  would intermittently kill it mid-sync (SIGKILL, invalid code signature)
  with no output to explain why. BEER now strips that flag from the helper
  itself before running it, so this can't recur even after a fresh
  download.
- The error you'd see for a genuinely broken helper invocation now shows
  the helper's actual output and exit code instead of a generic "no JSON
  result", and a sync that fails before it can list cloud files now records
  that failure in `last-sync.log` instead of silently leaving the previous
  successful sync's entry in place.

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
