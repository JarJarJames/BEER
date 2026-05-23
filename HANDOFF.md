# GameNative for Mac — Agent Handoff

This file is the entry point for any new agent (or future you) picking up this project. It captures **what this project actually is**, **where the code lives**, **how to reproduce the current broken state**, **what is actually wrong**, and **what to try next.**

Keep it up to date — short bullets only. Don't bury changes in the conversation.

---

## 1. What this project actually is

There are **two separate repos** in play. Codex was bouncing between both. Most of the work that matters lives in the second one.

| Repo | Path | What it is |
|---|---|---|
| `MacWine` | `/Users/user/Code/Codex Projects/MacWine` | Planning/docs/scripts for a downstream **GameNative Wine** runtime built from upstream Wine + selected staging patches. Has `docs/`, `patches/`, `scripts/`, a `wine/` checkout, and an empty placeholder `dist/GameNativeWine.runtime/` (only `LICENSES/` and `runtime.json` — no `bin/wine`). The Wine binaries have **not actually been built** yet. |
| `GameNative for Mac` (this repo) | `/Users/user/Documents/GameNative for Mac` | The Swift/SwiftUI macOS app. This is the "nice UI" Codex built. It's a bottle manager that installs Steam into a Wine prefix and launches it. **This is where the bug is being investigated.** |

The Swift app delegates to whichever Wine-like runtime the user picks. Right now the only available runtime is **Gcenx Game Porting Toolkit 3.0-3**, downloaded by the in-app Runtime Manager into:

```
~/Library/Application Support/GameNativeMac/Runtimes/GPTK-Game-Porting-Toolkit-3.0-3/
```

The MacWine repo's plan is to eventually ship its own Wine runtime to replace GPTK, but that path is unbuilt and not the source of the current failure.

## 2. Code layout (Swift app)

`Sources/GameNativeMac/`

- `GameNativeMacApp.swift` — `@main`, wires `BottleStore`, `ToolchainDetector`, `RuntimeInstaller`.
- `ContentView.swift` — all SwiftUI views. Sidebar + `BottleDetailView` (header / configuration / **actions** / logs). All the buttons the user sees live in `BottleDetailView.actions`. ~876 lines.
- `BottleStore.swift` — runs every Wine command. **Read this first.** Functions of interest:
  - `launchSteam` — basic launch.
  - `launchSteamDiagnostic` — same launch with `WINEDEBUG=+timestamp,+pid,+tid,+seh,+loaddll,+module`. This is the "Debug Launch" button and the log the user has been pasting.
  - `runBottleCommand` / `command(for:prefix:mode:)` — chooses how to invoke the runtime (handles GPTK wrapper vs raw wine vs GameNativeWine bundle).
  - `environment(for:prefix:)` — sets `WINEPREFIX`, `WINEARCH=win64`, `WINEDLLOVERRIDES`, `WINEDEBUG=-all` (default), `WINEESYNC=1`, `PATH`, `DYLD_FALLBACK_LIBRARY_PATH`.
  - `dllOverrides(for:)` — DXVK/DXMT/D3DMetal/WineD3D mappings.
  - "Steam Repair" menu: `writeSteamUpdateLock`, `removeSteamUpdateLock`, `refreshSteamClientPackage`, `downgradeSteamClient`.
- `Models.swift` — `Bottle`, `RuntimeCandidate`, `RuntimeKind`, `GraphicsBackend`, `SteamLaunchDefaults`. `SteamLaunchDefaults.basicArguments = "-no-cef-sandbox"`.
- `Paths.swift` — Application Support layout.
- `ToolchainDetector.swift` — finds CrossOver / Whisky / GPTK / Homebrew wine.
- `RuntimeInstaller.swift` — downloads and installs Gcenx GPTK from GitHub.
- `ShellRunner.swift` — `Process` wrapper. Streams combined stdout+stderr to the UI log.
- `SHA256Digest.swift` — tiny hashing util.

`Paths.swift` constants used everywhere:

- `~/Library/Application Support/GameNativeMac/Bottles/<name>-<uuid-prefix>/` — the Wine prefix.
- `~/Library/Application Support/GameNativeMac/Runtimes/` — managed runtimes.
- `~/Library/Application Support/GameNativeMac/bottles.json` — metadata.
- Each bottle has a `gamenative.log` at the prefix root (this is what the "Copy Log" button copies).

## 3. Current bottle state

The active bottle the user is testing is **`Steam-Bottle-3683EB34`**, runtime is GPTK 3.0-3 (`wine64`), graphics backend `automatic`, launch args `-no-cef-sandbox`. Architectures inside the prefix:

```
steam.exe              PE32+  x86-64
SteamUI.dll            PE32+  x86-64
crashhandler64.dll     PE32+  x86-64
Steam.dll              PE32   i386      ← 32-bit, expected, used by 32-bit auxiliaries
```

The **earlier** architecture-mismatch bug (Wine refusing to load a 32-bit `steamui.dll` into a 64-bit process — `arch 14c` / `c000007b`, documented in `MacWine/docs/steam-diagnostics.md`) is **already resolved.** The current `SteamUI.dll` is 64-bit.

## 4. What "Steam doesn't launch" actually means right now

This is the important section. The user's symptom is "no error, no window." That's misleading — Steam **is** launching, just headlessly.

### Wine trace shows a clean exit
The 1-second Wine log the user keeps pasting (`gamenative.log`) ends with:

```
LdrShutdownProcess ()
... PROCESS_DETACH for every DLL ...
Launching Steam with Wine diagnostics finished.
```

This is **not** a crash. The `steam.exe` we invoked detects an already-running Steam, forwards the args via IPC, and exits cleanly. That's normal Steam single-instance behavior.

### The real Steam process is alive and crash-looping its webhelper
The smoking gun is in the prefix's Steam logs (NOT the Wine log):

```
~/Library/Application Support/GameNativeMac/Bottles/Steam-Bottle-.../drive_c/Program Files (x86)/Steam/logs/steamui_html.txt
```

```
Started webhelper process N
Restart webhelper process, counter 2
Shutting down webhelper process N
Started webhelper process N+1
Restart webhelper process, counter 2
Shutting down webhelper process N+1
...
```

…repeating endlessly. Matching pattern in `logs/cef_log.txt`:

```
WARNING:chrome_main_delegate.cc(748)] This is Chrome version 126.0.6478.183 (not a warning)
ERROR:network_change_notifier_win.cc(268)] WSALookupServiceBegin failed with: 8
```

Steam respawns a fresh `steamwebhelper.exe` every ~10 seconds. Each helper dies inside Chromium's `NetworkChangeNotifierWin::CreateIpAddressTable` because `WSALookupServiceBegin` returns error 8 (`WSA_NOT_ENOUGH_MEMORY` / `WSAENOBUFS` — Wine's `ws2_32` doesn't actually fulfill the call). Because Steam's UI is CEF-rendered, no window ever appears. The Steam updater itself is happily idling.

`logs/console_log.txt` confirms: every ~10s, `Created mapping SteamChrome_MasterStream_spid<NNN>_mem when set to fail if created`. Same `spid` across all retries — same parent Steam, fresh helpers.

### Why Codex couldn't find it
Codex was reading `gamenative.log` (the Wine WINEDEBUG trace), which only captures the bootstrap process exiting. Steam's own logs under `drive_c/Program Files (x86)/Steam/logs/` were never surfaced in the UI. **Any new agent should look there before the Wine log.**

## 5. The actual bug to fix

`steamwebhelper.exe` crashes in CEF's `NetworkChangeNotifierWin` because Wine's `ws2_32.WSALookupServiceBeginW` is incomplete on GPTK 3.0-3. Known workarounds, in rough order of how invasive they are:

1. **Pass CEF flags to disable network change detection and GPU paths.** Already partially wired up — the **"Fix WebHelper"** button in the UI appends `-cef-disable-gpu -cef-disable-gpu-compositing` via `SteamLaunchDefaults.webHelperSafeArguments`. **It does not currently disable the network change notifier** and that's the actual cause. Try also adding (in `SteamLaunchDefaults`):
   - `-cef-force-occlusion` (sometimes referenced in Whisky configs)
   - Steam itself does not expose a clean "disable NetworkChangeNotifier" switch, but CEF respects `--disable-features=NetworkServiceInProcess` and `--disable-background-networking`. Steam passes through unknown flags to CEF, so try appending those to `launchArguments`.
2. **Run with a Wine that has a working `WSALookupServiceBeginW`.** CrossOver 24+ ships a patched `ws2_32`. The detector already finds CrossOver if installed — try creating a fresh bottle with the CrossOver runtime and see if the webhelper stays up. If it does, this confirms the diagnosis and points the MacWine runtime build at the right patch.
3. **Downgrade Steam to a pre-MasterStream client.** The "Steam Repair → Downgrade Steam Client" button already exists and points at a Web Archive snapshot. Worth trying as a baseline to confirm the UI can render at all in this bottle.
4. **(Long path) Build the actual GameNative Wine runtime from the MacWine repo with a patched `ws2_32`** and have the app point at it. The plumbing in the Swift app to use a `.runtime` bundle already exists (`RuntimeBundle`, `runtimeKind == .gameNativeWine`), but no such bundle has been built.

## 6. Reproduce the problem cleanly

```bash
cd "/Users/user/Documents/GameNative for Mac"
swift run GameNativeMac
```

1. Select the existing `Steam Bottle` (or create a new one with the GPTK runtime).
2. Click **Launch Steam** (not Debug Launch — Debug just adds WINEDEBUG noise).
3. Wait ~30 seconds. No Steam window appears.
4. **Look in the right place:**
   ```bash
   tail -f "$HOME/Library/Application Support/GameNativeMac/Bottles/Steam-Bottle-3683EB34/drive_c/Program Files (x86)/Steam/logs/steamui_html.txt"
   tail -f "$HOME/Library/Application Support/GameNativeMac/Bottles/Steam-Bottle-3683EB34/drive_c/Program Files (x86)/Steam/logs/cef_log.txt"
   ```
   You'll see the webhelper restart loop.

To reset before retrying, click **Stop** (runs `wineserver -k`), then relaunch.

## 7. Suggested next steps for the next agent

Pick one and report back here when done. Don't do all of them.

- [ ] **Surface the Steam-side logs in the UI.** Add tail viewers (or at minimum buttons that reveal them in Finder) for `bootstrap_log.txt`, `cef_log.txt`, `steamui_html.txt` inside `BottleDetailView`. Codex burned a lot of cycles staring at the wrong log file — fix that for everyone. The right place is the `logs` section of `BottleDetailView` in `ContentView.swift:795`.
- [ ] **Extend `SteamLaunchDefaults.webHelperSafeArguments`** with `-cef-disable-d3d11`, and try injecting `--disable-background-networking` / `--disable-features=NetworkServiceInProcess` through Steam's CEF passthrough. Make this a real button: "Apply CEF Safe Mode."
- [ ] **Add a runtime swap test:** offer a one-click "Try this bottle with CrossOver" if CrossOver is installed, just to confirm whether the webhelper is healthy under CrossOver's patched `ws2_32`. The detector already lists CrossOver candidates; the bottle model already supports changing runtimes (`bottle.useRuntime(_:)`).
- [ ] **Stop conflating "Wine exited cleanly" with "Steam is healthy."** `BottleStore.runBottleCommand` reports the parent process exit code. For Steam launches it should additionally poll for the existence of the Steam main window or at least check whether the webhelper is in a restart loop (parse `steamui_html.txt`). Surface a clear "Steam UI failed to render — webhelper is crash-looping" message instead of "Launching Steam finished."

## 8. Phase 2 — Light Steam (SteamCMD + bottle-per-game) [IN PROGRESS]

The full Steam-client path is permanently blocked on GPTK by an unimplemented `ws2_32.WSALookupServiceBeginW`, which Chromium's NetworkChangeNotifier hits and crashes the webhelper in a loop. Whisky/CrossOver fix it with patches; without them, the Steam UI cannot render.

The user decided to pivot to a **Light Steam** architecture, modeled on Winlator / GameNative-Android. Goal:

- **SteamCMD instead of Steam client.** Valve's official headless Steam binary. No CEF, no Chromium, no webhelper. Runs fine on GPTK because it's just HTTPS + a depot decompressor.
- **Bottle-per-game.** Every game installs into its own Wine prefix with its own runtime / graphics backend / DLL overrides — so each game can be tuned without affecting the others.
- **App-level Steam login.** Log in once via SteamCMD, install many games. SteamCMD itself caches the session token in its own VDF — the app never sees the password.

### Architecture (what exists today)

```
~/Library/Application Support/GameNativeMac/
  SteamCMD/                   ← app-level SteamCMD install
    steamcmd.exe
    ...
  steam-library.json          ← cached account + library
  Bottles/
    Hades-<uuid>/             ← per-game bottle (Wine prefix)
    Stardew-Valley-<uuid>/
    ...
  Runtimes/                   ← unchanged (GPTK / Whisky / etc.)
```

### Code added in this pass

UI-first scaffolding. Backend invocations of SteamCMD are stubbed; library data is mocked.

| File | Role |
|---|---|
| `Models.swift` | New types: `SteamAccount`, `SteamLibraryGame`, `SteamGameInstallStatus`. `Bottle` gained `steamAppID`, `steamGameName`, `gameInstallStatus`, `gameLaunchExecutable` (all optional — legacy bottles keep working). |
| `Paths.swift` | `steamCMDDirectory`, `steamCMDExecutableURL`, `steamLibraryStateURL`. |
| `SteamCMDInstaller.swift` (new) | **Real** download + unzip of `steamcmd.zip` from Valve's CDN into `~/Library/Application Support/GameNativeMac/SteamCMD/`. No Wine needed for setup. |
| `SteamLibraryStore.swift` (new) | App-level account + games store. Persists to `steam-library.json`. `fetchLibrary()` currently returns mock data (8 known Wine-friendly single-player games). |
| `SteamLibraryView.swift` (new) | Sheet UI with a 3-state machine: `SteamCMDSetupView` → `SteamSignInView` → `SteamLibraryGridView`. Library grid renders `AsyncImage` Steam header capsules with Install / Launch / Reveal actions per game. |
| `GameNativeMacApp.swift` | Wires `SteamCMDInstaller` and `SteamLibraryStore` into the env. |
| `ContentView.swift` | New sidebar button: **Steam Library (Beta)**. Legacy "New Bottle" button kept but demoted. |

### What still needs to be built (in order)

1. **Steam Web API library fetch.** When the user provides a SteamID64 + Web API key (already accepted in the sign-in form), call `https://api.steampowered.com/IPlayerService/GetOwnedGames/v1/?key=…&steamid=…&include_appinfo=1` and replace the mock games list with real data. Fallback to SteamCMD `+licenses_print` parsing when no API key is given.
2. **`SteamCMDController`.** A wrapper around `Process` that invokes `wine .../SteamCMD/steamcmd.exe` with appropriate `+args`. Must support:
   - `login(username)` — opens **Terminal.app** with a one-liner (`osascript -e 'tell application "Terminal" to do script "..."'`). The user enters password + 2FA in Terminal; SteamCMD caches the token. We never touch the password.
   - `installGame(appID, into: bottle)` — runs `+force_install_dir <bottle's drive_c/Games/<gameName>> +app_update <appID> validate +quit`, streams progress to the bottle log.
   - `appInfo(appID)` — `+app_info_print <appID> +quit`, parses VDF for `installdir`, `launch` entries, name.
3. **Game launch wiring.** After `installGame` finishes, parse the game's launch config from `app_info` and store the resulting `gameLaunchExecutable` on the bottle. The library grid's Launch button then runs that exe directly via Wine — no Steam client touched.
4. **Goldberg Steam Emu drop-in (optional).** For games that check `steam_api.dll` at runtime: ship Goldberg's open-source shim, toggle per bottle. Lets some Steamworks-protected single-player games run without a real Steam process. Out of scope for v1.
5. **Replace the BottleDetailView's "Install Steam" / "Launch Steam" actions on Steam-game bottles.** When `bottle.steamAppID != nil`, those buttons become "Reinstall/Validate Game", "Launch Game", and the "Steam Repair" menu disappears.

### Constraints and known dead-ends

- **Anti-cheat / multiplayer with Steamworks runtime checks**: this approach won't work. Same constraint Steam Deck / Linux power-users hit. Not a bug, a feature decision.
- **Achievements / cloud saves**: don't sync without the client unless you layer Goldberg, and even then it's local-only. Document this in the Sign-In sheet text.
- **The legacy full-Steam path stays in the app**, accessed via "New Bottle (Manual)". Don't delete it — it's still the right tool for someone who installs Whisky/CrossOver later and wants the full client.
- **Do not store the Steam password anywhere.** Use Terminal.app for the initial login. SteamCMD does its own credential caching.

### Test plan for next agent

1. Open Steam Library sheet → click Install SteamCMD. Should download `steamcmd.zip`, unzip, and show "SteamCMD is installed."
2. Sign-in screen accepts a username. After signing in, the mock library grid should appear with 8 game capsules.
3. Clicking "Install" on a game creates a new bottle named after the game and selects it. The grid card flips to "Installed" with a Launch button.
4. Bottle persists across app restarts. Re-opening the Steam Library sheet shows the same game as installed.

Everything past that — actual SteamCMD invocations, real library fetch, real game launch — is the Phase 2 work above.

## 9. Things to NOT redo

- Don't keep re-reading the Wine WINEDEBUG trace looking for the failure. It's not there.
- Don't run "Downgrade Steam Client" without first noting the current `package/` state — the previous run already produced a `crashhandler64.dll.old` and `steam.exe.old` that Steam couldn't clean up (filesystem perms via Wine). Capture state before destroying it.
- Don't touch the `MacWine/wine/` checkout to chase this bug. The fix is either in the Swift app (better CEF args / surfaced logs) or in choosing a different runtime. Building Wine is a much bigger project (see `MacWine/docs/macos-build-pipeline.md`).
- Don't add a `bin/wine` shim into `MacWine/dist/GameNativeWine.runtime/` to satisfy the Swift app's `.runtime` detection. There is no actual Wine there yet. The Swift app currently uses GPTK and that's correct for now.
