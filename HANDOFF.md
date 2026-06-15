# GameNative for Mac — Agent Handoff

Entry point for any new agent (or future you) picking up this project. **What it is, where the code lives, how it works today, how to build/debug, and the known sharp edges.** Keep it current — short bullets, no burying changes in chat.

---

## 0. Ground rules (read first)

- **The user runs ALL tests that touch their Steam account.** Claude writes and compiles code; the user scans QR codes, signs in, and reports results. Never initiate a Steam login / QR / token exchange / sync against the user's live account "to verify." Building and compiling locally is fine. (This is a hard boundary — it was set after an early mistake.)
- The user's long-played saves (60+ hrs in Kingdom Come: Deliverance) are sacred. Cloud sync is built defensively around never losing them.

## 1. What this is

A native macOS SwiftUI app: a Steam-like library that **downloads your games with DepotDownloader**, installs each into its **own Wine bottle** (per-game runtime / graphics / DLL tuning), runs them via Apple's **Game Porting Toolkit (GPTK)** Wine, and does **bidirectional Steam Cloud save sync** so you can move between a Windows PC and the Mac.

It does NOT run the real Steam client (that path is a dead end on GPTK — see §7). Games run directly via Wine, with a Goldberg/GBE Steamworks shim where needed.

## 2. Architecture at a glance

```
~/Library/Application Support/GameNativeMac/
  DepotDownloader/        native Steam downloader (SteamKit2); installed on first run
  CloudSync/CloudSync      our SteamKit2 cloud helper (also bundled inside the .app)
  Goldberg/                GBE_Fork steam_api shims
  Runtimes/                managed GPTK Wine
  Bottles/<game>-<uuid>/   one Wine prefix per game (drive_c/Games/<game>/…)
  CloudSaveBackups/<appid>/ timestamped pre-sync backups + last-sync.log
  steam-cloud-auth.json    QR refresh token + account (cloud/library auth)
  steam-library.json       cached account + owned games
  bottles.json             bottle metadata
```

Two halves:
- **Swift app** (`Sources/GameNativeMac/`) — UI, bottle management, install/launch, sync orchestration.
- **CloudSync helper** (`Tools/CloudSync/`, C# / .NET 9 / SteamKit2) — speaks the real Steam *client* protocol for auth, owned-games, and cloud read/write. See `Tools/CloudSync/README.md`.

## 3. Code map (Swift)

- `GameNativeMacApp.swift` — `@main`; wires all the `@StateObject` stores.
- `ContentView.swift` — router (onboarding → main shell) + `BottleDetailView` (the Display row, Steam Cloud row, Steam-emulator row, launch). `launch(_:)` does auto cloud sync: **pull before play, push after exit**.
- `BottleStore.swift` — runs every Wine command. `launchGameExecutable` + `configureWindowMode` (windowed mode, §6). `environment(for:)`, `dllOverrides(for:)`, `command(for:…)`.
- `DepotDownloaderController.swift` / `DepotDownloaderInstaller.swift` — install games via QR/refresh-token.
- `GoldbergInstaller.swift` / `GoldbergApplicator.swift` — steam_api shim drop-in.
- **Cloud:**
  - `SteamAuth.swift` (`SteamAuthStore`) — QR sign-in **via the helper**; holds account + refresh token; `sessionExpired` flag + `noteCloudError`.
  - `CloudSyncClient.swift` — Swift wrapper that shells out to the CloudSync helper (`locateBinary`, `authenticate`, `ownedGames`, `enumerate`, `batch`). Distinguishes `.authExpired` vs `.rateLimited`.
  - `CloudSyncEngine.swift` — `pull` / `push` / `sync`, conflict logic, mandatory backups, path mapping, `last-sync.log`.
- `SteamLibraryStore.swift` — owned games. `signInWithQR(auth:)` (primary) + legacy Web-API-key path (`signIn`, dormant fallback).
- `SteamLibraryView.swift` — onboarding (`SteamSignInView` = QR), library grid.
- `Paths.swift` — all the Application Support locations, incl. `cloudSyncExecutableURL`, `cloudSaveBackupsDirectory`.

## 4. Cloud saves — how it works

1. **Auth:** `SteamSignInView` → `SteamAuthStore.runQRAuth` → helper `auth` command emits the challenge URL (re-rendered as the QR rotates) then a SteamClient-audience **refresh token**. Persisted to `steam-cloud-auth.json`. (The Steam *Web* API needs a Publisher key — dead end; the *client* protocol via SteamKit2 only needs the user's own token, which is the whole unlock.)
2. **Sync:** `CloudSyncEngine` runs `enumerate` (1 logon) → computes download/upload lists in Swift → one **`batch`** call (1 logon) does all file transfers. **Never one logon per file** — that flood gets the account CM-rate-limited (see §7).
3. **Safety:** before any pull/push, every tracked save file is copied to `CloudSaveBackups/<appid>/<timestamp>-*/`. Sync only overwrites the strictly-older side. "Back up & clear local saves" copies then removes — never a true delete, never touches the cloud.
4. **Path mapping:** Steam cloud names look like `%WinSavedGames%kingdomcome/saves/...`; `CloudSyncEngine.mapToLocal` routes the `%Root%` token to the bottle's `drive_c/users/<user>/…`. Push learns the remote dir convention from existing cloud files.

## 5. Re-auth & rate-limit handling

- Helper tags logon failures: `auth_failed` (revoked/expired → reconnect) vs `rate_limited` (throttled → **wait, don't re-auth**). Swift maps to `.authExpired` / `.rateLimited`.
- `.authExpired` → `SteamAuthStore.sessionExpired = true` → Cloud row shows **Reconnect**; an explicit sync auto-opens the QR sheet. A fresh QR clears the flag.
- `.rateLimited` → message says wait; does NOT flag expired (re-auth would only extend the cooldown).

## 6. Windowed mode (native Mac window)

- `BottleStore.launchGameExecutable` runs the game `.exe` **directly** (no `wine explorer /desktop` — that wrapper was the old borderless, un-movable "virtual desktop").
- `configureWindowMode` writes winemac.drv registry before launch: `Decorated=Y` (title bar → movable + green-button fullscreen) and `CaptureDisplaysForFullscreen=N` when windowed (Wine never switches the display mode → fullscreen scales, no stretch).
- The toggle is `Bottle.useVirtualDesktop` (legacy name; now means "windowed mode"). Default ON for Steam-app bottles.
- **The game's own video setting must be Windowed** for a windowed window — the app can't force it from outside. Caveat: free-resizing to a wild aspect ratio can distort (Wine driver limitation).

## 7. Dead ends / history (don't redo)

- **Real Steam client on GPTK:** `steamwebhelper.exe` (CEF/Chromium) crash-loops in `NetworkChangeNotifierWin` because GPTK's `ws2_32.WSALookupServiceBeginW` is incomplete → no UI ever renders. That's why we use DepotDownloader, not the Steam client. The legacy full-Steam bottle path still exists behind "New Bottle (Manual)" for anyone who installs CrossOver/Whisky.
- **Steam Web `ICloudService` / `remotestorageapp` HTML scrape:** Publisher-key-gated / read-only. Replaced by the SteamKit2 client helper.
- **One Steam logon per file:** caused mass sync failures + got the account rate-limited (mislabeled as "expired"). Fixed by batching. Do not reintroduce.

## 8. Build, run, release

```bash
swift build && swift run GameNativeMac      # dev
./scripts/build_cloudsync.sh                # (re)build + install the helper to App Support
./scripts/build_app.sh 0.2.0                # → .build/GameNative.app + .build/GameNative.zip (bundled helper, ad-hoc signed)
```
- Release: merged to **`master`** (the real main branch; `cloud-saves` was the feature branch). Distributed via `gh release` — v0.2.0 at https://github.com/JarJarJames/GameNative-for-Mac/releases.
- **Not notarized** — downloaders must run `xattr -dr com.apple.quarantine /Applications/GameNative.app`. A paid Apple Developer ID + notarization would remove that step.
- **Apple Silicon only** (helper is osx-arm64; GPTK is arm64).

## 9. Debugging entry points

- **Cloud sync failures:** `CloudSaveBackups/<appid>/last-sync.log` — per-file `FAIL\t<name>\t<reason>` lines + a summary. This is the first place to look.
- **Per-bottle Wine log:** `Bottles/<bottle>/gamenative.log` (the exact command run is logged with a `$` prefix).
- **Run the helper by hand (read-only is safe):** see `Tools/CloudSync/README.md` — `enumerate` just lists cloud files; `download` is safe; only `upload`/`batch`-with-uploads write.
- **Recover a save:** copy from a `CloudSaveBackups/<appid>/<timestamp>-*/` folder back into the bottle.

## 10. Known sharp edges / next bugs to expect

- First-run on a fresh machine: large GPTK runtime download; GPTK install can be finicky. Friend testing will surface this.
- Windowed mode depends on the game's own setting; aspect distortion on free-resize.
- Goldberg/anticheat/multiplayer-with-Steamworks games won't work — by design.
- Push currently only walks directories that already have a cloud file (learns the path from siblings); a brand-new save folder not yet in the cloud is skipped until one file from it exists in the cloud.
- No Keychain yet — refresh token sits in `steam-cloud-auth.json` (TODO in `Paths.swift`).
