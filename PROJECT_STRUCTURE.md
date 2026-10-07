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
| `BEERApp.swift`, `AppDelegate.swift` | App entry point and app-delegate hooks | Feature code |
| `Managers/` | Long-lived objects with state or side effects: stores (`BottleStore`, `SteamLibraryStore`, `DLCStore`, `DownloadsStore`, `SteamAuthStore`, `SteamPresenceStore`), `CloudSyncEngine`, `CloudSyncClient`, `AchievementWatcher`, `DepotDownloaderController`, `ToolchainDetector`, ... | Views, pure helpers |
| `Installers/` | Things that download/install or patch components: `RuntimeInstaller`, `GraphicsTranslatorInstaller`, `GoldbergInstaller`, `GoldbergApplicator`, `DepotDownloaderInstaller` | Long-lived app state (that's a Manager) |
| `ViewModel/` | State and actions for one screen or sheet (`GameDetailViewModel`, `DLCManagerViewModel`, `SteamQRAuthViewModel`, `SteamLibraryGridViewModel`, `EnvironmentEditorViewModel`) | Layout, or state shared by the whole app (that's a Manager) |
| `Model/` | Data types, one per file: structs, enums, errors, reports. A type nested in a manager lives here as `Owner.Name.swift` | Logic that talks to the network or disk |
| `Utilities/` | Stateless helpers and small concurrency boxes: `ShellRunner`, `Keychain`, `AppPaths`, `QRCodeGenerator`, the digests, `RuntimeBundle` | Anything holding long-lived state |
| `Extensions/` | Small type extensions, one per file, named `Type+Purpose.swift` | App-specific business logic |
| `Constants/` | Shared values (`SteamRootRouting`). Spacing, sizing, and user-facing strings go here as they are needed | Magic numbers or string literals inside new views |
| `Resources/` | Bundled resources (`achievement-unlock.mp3`); declared in `Package.swift` | Code |
| `View/` | All SwiftUI views | |

Rule of thumb for "where does this go?": has long-lived state or side effects -> `Managers/`. Downloads, installs, or patches something -> `Installers/`. State and actions for one screen -> `ViewModel/`. Data shape -> `Model/`. Pure and stateless -> `Utilities/`. Adds to an existing type -> `Extensions/`. Any number or string a view needs -> `Constants/`.

### A manager or view model that outgrows one file

A type that gets big is split into extensions by concern, and the files move into a folder named after the type:

```
Managers/Bottle Store/
├── BottleStore.swift                stored properties, init, core operations
├── BottleStore+Launch.swift
├── BottleStore+Commands.swift
├── BottleStore+Environment.swift
└── BottleStore+Logging.swift
```

`CloudSyncClient`, `CloudSyncEngine`, `ControllerSupport` (in `Managers/`) and `GameDetailViewModel` (in `ViewModel/`) are split the same way. Stored properties can't live in extensions, so they stay in the main file; members the extensions share are internal, not `private`.

## Views (`View/`)

Views mirror the **app's navigation**: `ContentView` is the shell (sidebar in `Main Shell View/`, `Library Pane/`, `Steam Account Bar/`), and each screen the shell presents gets a folder directly under `View/`.

```
View/
├── Content View/
│   └── Main Shell View/ -> Library Pane/, Steam Account Bar/
├── Steam Library Grid View/ -> Game Card View/, Library Toolbar View/, Library Empty State View/
├── Game Detail View/
│   ├── Game Detail Screen/            Owns the GameDetailViewModel
│   ├── Game Hero View/ -> Game Action Row/, Steam Hero Artwork/, Steam Library Logo/
│   ├── Download Progress View/
│   ├── Installed Details View/        One folder per settings row
│   │   ├── Runtime Row/, Graphics Row/, Display Mode Row/, Controller Fix Row/,
│   │   │   Launch Arguments Row/, Steam Emulator Row/, DLC Row/, Steam Cloud Row/
│   │   └── Advanced Settings View/ -> Environment Row/, Wine Log View/, Labeled Value/
│   ├── Settings Row/                  Shared by every row above
│   ├── DLC Manager View/ -> DLC Manager Row/, DLC Manager Footer/, ...
│   └── Steam Cloud QR Sheet/
├── Downloads Pane/ -> Download Row/
├── Runtime Manager View/ -> Runtime Section/, Runtime Release Row/, ...
├── Steam Sign In View/
├── Depot Downloader Setup View/
└── Reuseable Views/ -> QR Code View/    Components shared by more than one screen
```

### Nesting rule: a component lives inside the screen that owns it

A view that is only used by one parent sits in a folder **inside that parent's folder**, named after the view. The nesting depth tells you who uses what (`DLCManagerView` is only presented by the game detail screen, so it lives inside `Game Detail View/`). A component used by several siblings goes up to their common parent (`Settings Row/`); one used by more than one screen goes to `Reuseable Views/`.

### Views versus view models

A view describes layout and reads state. A screen with logic gets a view model in `ViewModel/` that holds its `@Published` state and its actions; the view owns it with `@StateObject`. The view model takes the stores it needs at init (a `@StateObject` initializer can't read the SwiftUI environment, so a thin wrapper view such as `GameDetailView` collects them) and forwards their `objectWillChange` so the screen redraws as it would if it observed them directly. Rows that only read or edit a store use `@EnvironmentObject` themselves and need no view model.

## Conventions

1. **One type per file, named after the type.** `GameDetailViewModel.swift` holds `GameDetailViewModel`. Extension files are `Type+Purpose.swift`; a model nested in another type is `Owner.Name.swift`. Private helpers that exist only for one type may stay next to it.
2. **Keep files short.** Aim for under about 300 lines. Past that, split by concern as above rather than adding a section.
3. **One folder per view, named after the view.** Folder names use spaces and Title Case; Swift files do not.
4. **Single-use components nest under their parent; shared ones go to `Reuseable Views/`.** Do not leave a component at the top level of `View/` just because it is small.
5. **Folders mirror the navigation hierarchy.** If screen B is presented from screen A, B's folder is inside A's.
6. **Views, view models and models stay separate.** No store calls, disk access, or business rules in a view body; no SwiftUI in `Model/`.
7. **Role folders are flat**, except that a manager or view model split across files gets its own folder.
8. **No hard-coded values in new views.** Spacing, sizes, and strings come from `Constants/`. Existing views still contain literals; move them when you touch the code.
9. **Moving files is its own change.** Use `git mv` so history follows, and don't mix moves with behavior edits.
10. **Docs and scripts stay out of the source targets.** They live at the repo root or in `scripts/`.

## Adding something new

| I'm adding... | Put it in... |
|---|---|
| A new screen presented from an existing screen | A new folder inside that screen's folder, with the same name as the view |
| A new top-level pane or sheet from the shell | `View/<Name>/`, plus an entry in `Main Shell View` |
| State and actions for a screen | `ViewModel/<Name>ViewModel.swift` |
| A small component used by one screen | A folder inside that screen's folder |
| A component a second screen now needs | Move it to `View/Reuseable Views/<Name>/` |
| A service with state/side effects | `Managers/<Name>.swift` |
| Something that downloads/installs/patches | `Installers/<Name>.swift` |
| A stateless helper | `Utilities/<Name>.swift` |
| A new data type or error | `Model/<Name>.swift` |
| A string or number | `Constants/` |
| A test | `Tests/BEERTests/`, offline only |
