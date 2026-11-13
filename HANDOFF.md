# BEER — Agent Handoff

Entry point for any new agent (or future you) picking up this project. **What it is, where the code lives, how it works today, how to build/debug, and the known sharp edges.** Keep it current — short bullets, no burying changes in chat.

---

## 0. Ground rules (read first)

The hard rules, commands and testing guide are in [`AGENTS.md`](AGENTS.md). The two that shaped this codebase most:

- **A human runs every test that touches a Steam account**, on their own account. Agents write code, build it and run the offline tests; they never sign in, scan a QR code or sync "to verify."
- **Saves are irreplaceable.** Cloud sync is built defensively around never losing them.

## 1. What this is

A native macOS SwiftUI app: a Steam-like library that **downloads your games with DepotDownloader**, installs each into its **own Wine bottle** (per-game runtime / graphics / DLL tuning), runs them via Apple's **Game Porting Toolkit (GPTK)** Wine, and does **bidirectional Steam Cloud save sync** so you can move between a Windows PC and the Mac.

It does NOT run the real Steam client (that path is a dead end on GPTK — see §7). Games run directly via Wine, with a Goldberg/GBE Steamworks shim where needed.

## 2. Architecture at a glance

```
~/Library/Application Support/BEER/
  DepotDownloader/        native Steam downloader (SteamKit2); installed on first run
  CloudSync/CloudSync      our SteamKit2 cloud helper (also bundled inside the .app)
  Goldberg/                GBE_Fork steam_api shims
  Runtimes/                managed GPTK Wine
  Bottles/<game>-<uuid>/   one Wine prefix per game (drive_c/Games/<game>/…)
  CloudSaveBackups/<appid>/ timestamped pre-sync backups + last-sync.log
  steam-library.json       cached account + owned games
  bottles.json             bottle metadata
```

The Steam refresh token is in the macOS Keychain, not in this folder.

Two halves:
- **Swift app** (`Sources/BEER/`) — UI, bottle management, install/launch, sync orchestration.
- **CloudSync helper** (`Tools/CloudSync/`, C# / .NET 9 / SteamKit2) — speaks the real Steam *client* protocol for auth, owned-games, and cloud read/write. One class per command; offline xUnit tests in `Tools/CloudSync.Tests/`. See `Tools/CloudSync/README.md`.

## 3. Code map (Swift)

- `BEERApp.swift` — `@main`; wires all the `@StateObject` stores.
- `ContentView.swift` — onboarding router; `MainShellView` is the top bar (Downloads and the account, top right; the All Games / Installed switch is in the library's own bar) and the library/detail navigation boundary.
- `GameDetailView.swift` (and the views under `View/Game Detail View/`) — game hero, install/play actions, per-game runtime/graphics/display/cloud controls, collapsible advanced bottle settings, and auto cloud sync: **pull before play, push after exit**.
- `DownloadsPane.swift` — active and completed download UI.
- `RuntimeManagerView.swift` — the Settings window's Runtimes tab, for installing Wine/GPTK runtimes and graphics translators.
- `BottleStore` (`Managers/Bottle Store/`) — runs every Wine command. `launchGameExecutable` + `configureDisplayMode` (resolution mode, §6). `environment(for:)`, `dllOverrides(for:)`, `command(for:…)`.
- `DepotDownloaderController.swift` / `DepotDownloaderInstaller.swift` — install games using the same Keychain-owned Steam refresh token as library/cloud access. `CloudSync prepare-depot-auth` creates DepotDownloader's short-lived compatibility cache; the controller removes it after the process exits and on crash recovery.
- `GoldbergInstaller.swift` / `GoldbergApplicator.swift` — steam_api shim drop-in.
- **Cloud:**
  - `SteamAuthStore.swift` — QR sign-in **via the helper**; holds the account and keeps the refresh token in the Keychain; `sessionExpired` flag + `noteCloudError`.
  - `CloudSyncClient` (`Managers/Cloud Sync Client/`) — Swift wrapper around the CloudSync helper (`locateBinary`, `authenticate`, `ownedGames`, `enumerate`, `batch`). Distinguishes `.authExpired` vs `.rateLimited`. Every Steam call goes through `SteamSessionHost`: one helper `session` process, logged on once, that takes each call as a request. Session output is in `play-session.log`.
  - `CloudSyncEngine` (`Managers/Cloud Sync Engine/`) — `pull` / `push` / `sync`, conflict logic, mandatory backups, path mapping, `last-sync.log`.
- `SteamLibraryStore.swift` — owned games, fetched through the helper after `signInWithQR(auth:)`.
- `DepotDownloaderSetupView.swift` / `SteamSignInView.swift` — first-run installation and QR onboarding.
- `SteamLibraryGridView.swift` — owned-game library grid and cards.
- `AppPaths.swift` — all the Application Support locations, incl. `cloudSyncExecutableURL`, `cloudSaveBackupsDirectory`.

## 4. Cloud saves — how it works

1. **Auth:** `SteamSignInView` → `SteamAuthStore.runQRAuth` → helper `auth` command emits the challenge URL (re-rendered as the QR rotates) then a SteamClient-audience **refresh token**, which is stored in the Keychain. Builds that kept it in `steam-cloud-auth.json` have it migrated to the Keychain and the file deleted on load. (The Steam *Web* API needs a Publisher key — dead end; the *client* protocol via SteamKit2 only needs the user's own token, which is the whole unlock.)
2. **Sync:** `CloudSyncEngine` runs `enumerate` → computes download/upload lists in Swift → one **`batch`** request does all file transfers, both on BEER's one Steam session. The batch uses a shared HTTP client and at most four concurrent files, with downloads completing before uploads start. **Never one logon per file** — that flood gets the account CM-rate-limited (see §7).
3. **Safety:** before any pull/push, every tracked save file is copied to `CloudSaveBackups/<appid>/<timestamp>-*/`. Sync only overwrites the strictly-older side; when timestamps differ but Steam's SHA-1 matches the local content, the unchanged file is skipped. "Back up & clear local saves" copies then removes — never a true delete, never touches the cloud.
4. **Path mapping:** Steam cloud names look like `%WinSavedGames%kingdomcome/saves/...`; `CloudSyncEngine.mapToLocal` routes the `%Root%` token to the bottle's `drive_c/users/<user>/…`. Push learns the remote dir convention from existing cloud files.

## 5. Re-auth & rate-limit handling

- Helper tags logon failures: `auth_failed` (revoked/expired → reconnect) vs `rate_limited` (throttled → **wait, don't re-auth**). Swift maps to `.authExpired` / `.rateLimited`.
- `.authExpired` → `SteamAuthStore.sessionExpired = true` → Cloud row shows **Reconnect**; an explicit sync auto-opens the QR sheet. A fresh QR clears the flag.
- `.rateLimited` → message says wait; does NOT flag expired (re-auth would only extend the cooldown).

## 6. Display mode (what GPTK actually allows)

Researched June 2026 — a native, movable/resizable macOS window with the green fullscreen button is **NOT possible on GPTK**: GPTK runs games as borderless *processes* with no macOS window chrome, and window style is owned by the game (Wine just mirrors it). There is no `Decorated` key in `winemac.drv` (that's X11). We accept this — GPTK is free and fastest. See the chat research for sources (winemac.drv `macdrv_main.c`, AppleGamingWiki).

What we actually do:
- `BottleStore.launchGameExecutable` runs the game `.exe` **directly** (no `wine explorer /desktop`).
- `configureDisplayMode` writes winemac.drv's `RetinaMode`, Windows `LogPixels` (96/192), and Wine 10's global `HIGHDPIAWARE` compatibility override before restarting the Wine server. Standard uses macOS point dimensions; High Resolution doubles the dimensions exposed to the game. It also writes `CaptureDisplaysForFullscreen` from the per-bottle "Capture Display" toggle (default N). Without capture, the fullscreen window sits at `NSStatusWindowLevel+1` and the Dock/menu bar stay live, so the hidden cursor reappears at screen edges; with capture, Wine calls `CGCaptureAllDisplays` and raises the window to the shielding level. Capture alone does not change the display mode; only a game's own `ChangeDisplaySettings` call does (winemac.drv `cocoa_app.m`). Capture is only a partial fix: winemac.drv treats a `ClipCursor` rect covering the whole screen as no clip, so mouse-look games (e.g. Dark Souls Remastered) leave the hidden cursor pinned at the screen edges, where hot corners and Wine's own edge handling can still reveal it.
- Library games store executable-specific flags in `gameLaunchArguments`. `BottleStore.load` migrates custom values from the old Steam-only field once; unknown legacy display fields in existing JSON are ignored by `Codable`.
- For a smaller view, the user sets the game's own Windowed video option — the app can't impose it.

## 7. Dead ends / history (don't redo)

- **Real Steam client on GPTK:** `steamwebhelper.exe` (CEF/Chromium) crash-loops in `NetworkChangeNotifierWin` because GPTK's `ws2_32.WSALookupServiceBeginW` is incomplete → no UI ever renders. The old manual full-Steam-bottle workflow was removed; use DepotDownloader's per-game path.
- **Steam Web `ICloudService` / `remotestorageapp` HTML scrape:** Publisher-key-gated / read-only. Replaced by the SteamKit2 client helper.
- **One Steam logon per file:** caused mass sync failures + got the account rate-limited (mislabeled as "expired"). Fixed by batching. Do not reintroduce.
- **Fighting the user's other Steam devices (#65):** BEER logs on once (`SteamSessionHost` → the helper's `session`) and every command is a request on it; don't add a logon. The session logs on as its own device (`BeerDevice`), not with SteamKit's hardware-derived machine ID, which matches the Mac's own Steam client. Persona state is account-wide: BEER sends only the status the user picked, always with `persona_set_by_user` (`PersonaStatus`) — SteamKit2's `SetPersonaState` leaves it off, and that signed the user's own Steam clients out of Friends, while JavaSteam (GameNative) sets it — and never re-sends it on a timer. Games-played must not be announced while Steam reports another device playing (`ClientPlayingSessionState`), or for 60 s after it stops (`PlayingLock`), or that device gets kicked with `LoggedInElsewhere`.

## 8. Build, run, release

```bash
swift build && swift run BEER      # dev
./scripts/build_cloudsync.sh                # (re)build + install the helper to App Support
./scripts/build_app.sh 0.7.0                # → .build/BEER.app + .build/BEER.zip (bundled helper, ad-hoc signed)
```
- Work lands in **`dev`**; a release merges `dev` into `master` and is tagged there. Distributed via `gh release` at https://github.com/JarJarJames/BEER/releases. The full release steps are in `GOVERNANCE.md`.
- **Not notarized** — downloaders must run `xattr -dr com.apple.quarantine /Applications/BEER.app`. A paid Apple Developer ID + notarization would remove that step.
- **Apple Silicon only** (helper is osx-arm64; GPTK is arm64).

### Releasing a GPTK runtime

BEER's own GPTK runtime (CrossOver's open-source Wine + Apple's D3DMetal,
GStreamer, Wine Mono, Wine Gecko) is built locally and published to
https://github.com/JarJarJames/BEER-runtimes, which the Runtimes tab reads
(`RuntimeSources`). Builds need macOS 15+ to run; older Macs get Gcenx's GPTK.

1. Download Apple's Game Porting Toolkit from developer.apple.com (needs an
   Apple ID), open its disk image, then the "Evaluation environment for
   Windows games" image inside it. Copy that image's `redist` folder,
   `License.rtf` and `Acknowledgements.rtf` into one folder. Re-read
   `License.rtf`: sharing is allowed only non-commercially (§2A(iii), §2C).
2. Run `./scripts/build_gptk_runtime.sh <that folder>/redist`. It downloads
   and checksums everything else, builds Wine (about 20 minutes), and writes
   `.build/gptk-runtime/gptk-<d3dmetal>-winecx-<crossover>-<revision>.tar.xz`. It needs
   Homebrew's `bison gettext freetype gnutls mingw-w64`, `scripts/build_sdl.sh`
   run once, Gcenx's GPTK installed in BEER (its x86_64 libraries are reused),
   and the Command Line Tools' macOS 15 SDK. Wine builds against that SDK, not
   the Mac's own: built against a newer one, it calls functions older macOS
   lacks and crashes there (build 1 crashed on everything before macOS 27).
   The script refuses to pack a runtime that calls anything macOS 15 lacks.
3. Test the unpacked runtime: copy it into `Runtimes/GPTK-<d3dmetal>-winecx-<crossover>-<revision>`
   and play a few games on it. A test on this Mac only covers this Mac's macOS.
4. Bump `REVISION` in the script for any rebuild: BEER never re-downloads a tag
   it has. Publish with the tag `<d3dmetal>-winecx-<crossover>-<revision>`
   (e.g. `4.0b3-winecx-26.3.0-2`), so it installs into the folder named in step 3:
   `gh release create 4.0b3-winecx-26.3.0-2 .build/gptk-runtime/gptk-4.0b3-winecx-26.3.0-2.tar.xz --repo JarJarJames/BEER-runtimes`.
   The release notes should link CodeWeavers' source (https://www.codeweavers.com/crossover/source)
   for the LGPL.

## 9. Debugging entry points

- **Cloud sync failures:** `CloudSaveBackups/<appid>/last-sync.log` — per-file `FAIL\t<name>\t<reason>` lines + a summary. This is the first place to look.
- **Per-bottle Wine log:** `Bottles/<bottle>/beer.log` (the exact command run is logged with a `$` prefix).
- **Run the helper by hand (read-only is safe):** see `Tools/CloudSync/README.md` — `enumerate` just lists cloud files; `download` is safe; only `upload`/`batch`-with-uploads write.
- **Recover a save:** copy from a `CloudSaveBackups/<appid>/<timestamp>-*/` folder back into the bottle.

## 10. Known sharp edges / next bugs to expect

- First-run on a fresh machine: large GPTK runtime download; GPTK install can be finicky. Friend testing will surface this.
- Windowed mode depends on the game's own setting; aspect distortion on free-resize.
- Goldberg/anticheat/multiplayer-with-Steamworks games won't work — by design.
- Push walks folders that already have cloud files, plus the folders named by the game's Steam `ufs/savefiles` rules (`enumerate` reports them as `savefiles`). A new file takes its cloud name from sibling cloud files when it has any, otherwise from its rule (`%Root%/path/file`). Rules for other platforms, unknown roots, or unknown `{placeholders}` are dropped. A game with no rules still only pushes folders already in the cloud.
