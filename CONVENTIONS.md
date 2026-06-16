# Coding Conventions

How to write code that fits BEER. Read this before adding anything non-trivial.
For the rules that protect users (accounts, saves, secrets) see `CONTRIBUTING.md`
and `AGENTS.md`.

## Platform

- **Swift 6.2**, SwiftUI, **macOS 14+**, **Apple Silicon only**. The runtime is
  Apple's Game Porting Toolkit (GPTK) Wine.
- The CloudSync helper is **C# / .NET 9 / SteamKit2** under `Tools/CloudSync/`.
  Keep it a thin, single-purpose binary the app shells out to.

## Architecture

- App code lives in `Sources/BEER/`. State is held in `@MainActor`
  `ObservableObject` stores wired up in `BEERApp.swift` (e.g. `BottleStore`,
  `SteamLibraryStore`, `DownloadsStore`, `SteamAuthStore`, `CloudSyncEngine`).
- **All filesystem paths go through `AppPaths`** (`Paths.swift`). Never hardcode
  `~/Library/Application Support/...`; add a property to `AppPaths` instead so the
  storage migration and layout stay in one place.
- **All process execution goes through `ShellRunner`** with an argument array.
  Never build a shell command string; never use `sh -c` with interpolated input.
- Installers (DepotDownloader, Goldberg, graphics translators, runtimes) follow a
  consistent shape: locate/download → verify → install into Application Support →
  expose state via a store. Copy the nearest existing installer when adding one.

## Style

- Match the surrounding code: naming, spacing, and **comment density**. Comments
  explain *why* (especially non-obvious platform/Wine/Steam quirks), not *what*.
- Errors are typed and conform to `LocalizedError` with a user-readable
  `errorDescription`. Avoid force-unwraps on anything derived from user input,
  the network, or the filesystem.
- Persist non-secret state as pretty-printed, sorted-key JSON in Application
  Support (see the shared `JSONEncoder`/`JSONDecoder` extensions). Persist
  secrets (Steam refresh token) in the Keychain via `Keychain` — never on disk in
  cleartext.
- Logging: the exact Wine command is logged to the per-bottle `beer.log`; cloud
  sync writes `CloudSaveBackups/<appid>/last-sync.log`. **Never log tokens or
  credentials.**

## What "done" means for a PR

- `swift build` succeeds (and `dotnet build` if you touched the helper).
- You tested it against **your own** account and wrote down what you did: which
  Mac/chip, macOS version, game, and what you observed.
- No secrets, no personal paths, no reintroduced `HANDOFF.md` §7 anti-patterns.
- The change is focused — no drive-by reformatting of unrelated files.
