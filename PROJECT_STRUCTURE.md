# Project Structure

How the BEER repo is organized, and the rules behind it. Folder names below are exact, so match them when searching or adding files.

## Repo root

```
BEER/
├── AGENTS.md / CLAUDE.md      Guidance for AI agents
├── PROJECT_STRUCTURE.md       This file
├── CONVENTIONS.md             Code conventions (stores, installers, shelling out)
├── HANDOFF.md                 Full architecture
├── Package.swift              SwiftPM manifest (targets: BEER, AchievementUI, BEERTests, CloudSyncPrebuild plugin)
├── Sources/                   Swift source (see below)
├── Tests/BEERTests/           Offline unit tests
├── Tools/CloudSync/           Native Steam-client helper (C# / .NET 9 / SteamKit2)
├── Plugins/CloudSyncPrebuild/ SwiftPM build-tool plugin that rebuilds the helper
└── scripts/                   Build and dev helper scripts
```

## Swift source (`Sources/`)

Two targets. `AchievementUI/` is a separate library target so its SwiftUI Previews build fast; it holds only the achievement toast content and its data type, and must not depend on `BEER`.

The `BEER` target (`Sources/BEER/`) is grouped **by role**, with one exception: `View/` is grouped **by screen** (see below).

| Folder | What lives here | What does *not* |
|---|---|---|
| `BEERApp.swift` | App entry point and `AppDelegate` | Feature code |
| `Managers/` | Long-lived objects with state or side effects: `BottleStore`, `SteamLibraryStore`, `DLCStore`, `DownloadsStore`, `SteamAuthStore`, `SteamPresenceStore`, `AchievementWatcher`, `AchievementToastCenter`, `CloudSyncEngine`, `CloudSyncClient`, `DepotDownloaderController`, `ToolchainDetector`, `ControllerSupport` | Views, pure helpers |
| `Installers/` | Things that download/install or patch components: `RuntimeInstaller`, `GraphicsTranslatorInstaller`, `GoldbergInstaller`, `GoldbergApplicator`, `DepotDownloaderInstaller` | Long-lived app state (that's a Manager) |
| `Model/` | Data types (`Bottle`, `SteamLibraryGame`, `RuntimeKind`, ...) | Logic that talks to the network or disk |
| `Utilities/` | Stateless helpers: `ShellRunner`, `Keychain`, `AppPaths`, `SHA1Digest`, `SHA256Digest` | Anything holding long-lived state |
| `Resources/` | Bundled resources (`achievement-unlock.mp3`); declared in `Package.swift` | Code |
| `Constants/` | Shared numbers (spacing, sizing, timings) and user-facing strings. Created when first needed | Magic numbers or string literals inside views |
| `Extensions/` | Small type extensions, one per file, named `Type+Purpose.swift`. Created when first needed | App-specific business logic |
| `View/` | All SwiftUI views | |

Rule of thumb for "where does this go?": has long-lived state or side effects -> `Managers/`. Downloads, installs, or patches something -> `Installers/`. Pure and stateless -> `Utilities/`. Adds to an existing type -> `Extensions/`. Data shape -> `Model/`. Any number or string a view needs -> `Constants/`.

## Views (`View/`)

Views mirror the **app's navigation**: `ContentView.swift` is the shell (sidebar, `MainShellView`, `LibraryPane`), and each screen it presents gets one folder.

```
View/
├── ContentView.swift                  App shell
├── Steam Library View/                SteamLibraryGridView, GameCardView
├── Game Detail View/                  GameDetailView
│   ├── DLC Manager View/              Presented from Game Detail
│   └── Steam Cloud QR Sheet/          Presented from Game Detail
├── Downloads View/                    DownloadsPane
├── Runtime Manager View/              RuntimeManagerView
├── Steam Sign In View/                SteamSignInView
├── Depot Downloader Setup View/       DepotDownloaderSetupView
└── Reuseable Views/                   Components shared by more than one screen (created when first needed)
```

### Nesting rule: a component lives inside the screen that owns it

A view that is only used by one parent sits in a folder **inside that parent's folder**, named after the view. The nesting depth tells you who uses what (`DLCManagerView` is only presented by `GameDetailView`, so it lives inside `Game Detail View/`).

## Conventions

1. **One folder per view, named after the view.** The folder name matches the primary type name with spaces (`Game Detail View/` holds `GameDetailView.swift`). Folder names use spaces and Title Case; Swift files do not.
2. **Single-use components nest under their parent; shared ones go to `Reuseable Views/`.** Do not leave a component at the top level of `View/` just because it is small.
3. **Folders mirror the navigation hierarchy.** If screen B is presented from screen A, B's folder is inside A's.
4. **Role folders are flat.** Outside `View/`, do not add subfolders to `Managers/`, `Installers/`, `Utilities/`, `Model/`, or `Extensions/`.
5. **Extensions are named `Type+Purpose.swift`**, one concern per file.
6. **No hard-coded values in new views.** Spacing, sizes, and strings come from `Constants/`. Existing views still contain literals; move them when you touch the code.
7. **Moving files is its own change.** Use `git mv` so history follows, and don't mix moves with behavior edits.
8. **Docs and scripts stay out of the source targets.** They live at the repo root or in `scripts/`.

## Adding something new

| I'm adding... | Put it in... |
|---|---|
| A new screen presented from an existing screen | A new folder inside that screen's folder, with the same name as the view |
| A new top-level pane or sheet from the shell | `View/<Name>/`, plus an entry in `ContentView.swift` |
| A small component used by one screen | A folder inside that screen's folder |
| A component a second screen now needs | Move it to `View/Reuseable Views/<Name>/` |
| A service with state/side effects | `Managers/<Name>.swift` |
| Something that downloads/installs/patches | `Installers/<Name>.swift` |
| A stateless helper | `Utilities/<Name>.swift` |
| A new data type | `Model/` |
| A string or number | `Constants/` |
| A test | `Tests/BEERTests/`, offline only |
