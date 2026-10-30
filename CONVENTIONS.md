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
  sync writes `CloudSaveBackups/<appid>/last-sync.log`. Everything else goes to
  the unified log through `Log` (`Log.cloudSync`, `Log.auth`, `Log.install`,
  `Log.session`, `Log.achievements`). Interpolated values are private unless
  marked `privacy: .public`; mark only values that can't identify the user.
  **Never log tokens or credentials.**

### Errors: `throw`, `attempt`, or `try?`

A bare `try?` makes a failure disappear. Pick one of these on purpose:

1. **Throw** when the failure changes what the user believes or risks their
   data: a save backup, writing or deleting saves, the Keychain, deleting a
   credential file, patching game files. The UI shows the error.
2. **`attempt("what", log: Log.area) { ... }`** when the failure is unexpected
   but safe to continue past: a log file, a cache, a retry queue, a record
   used for cleanup. It logs and returns nil.
3. **`try?`** only when failure is a normal outcome and needs no trace:
   probing for a file or folder that may not exist, reading optional
   resource values, closing a handle. If that isn't obvious from the line,
   add a comment saying why.

To delete something, use `FileManager.removeItemIfPresent(at:)`. It forgives
"already gone" and nothing else, so it can go under any of the three. A
plain `try? removeItem` also hides a delete that failed.

## What "done" means for a PR

- `swift build` and `swift test` succeed, and CI is green (it also builds,
  style-checks and tests the helper).
- You tested it against **your own** account and wrote down what you did: which
  Mac/chip, macOS version, game, and what you observed.
- No secrets, no personal paths, no reintroduced `HANDOFF.md` §7 anti-patterns.
- The change is focused — no drive-by reformatting of unrelated files.
