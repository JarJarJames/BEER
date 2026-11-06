# AGENTS.md

Rules and commands for **any** AI coding agent working in this repo (Claude,
Cursor, Copilot, Aider, etc.). This is the single source: `CLAUDE.md` only
points here, and `CONTRIBUTING.md` / `CONVENTIONS.md` link to the sections
below instead of repeating them. Read `HANDOFF.md` for the architecture.

## Hard rules (do not break)

1. **Never authenticate to or access anyone's Steam account.** Agents write and
   compile code only. A human runs every test that involves signing in, scanning
   a QR code, downloading, or syncing — against **their own** account. Do not run
   the CloudSync helper's `auth` / `enumerate` / `upload` / `batch` against a real
   token to "verify." Compiling, building and running the offline tests are fine.
2. **Protect saves.** Anything that writes or deletes local or cloud saves must
   back up first. The engine already does this — keep it that way. Treat save
   data as irreplaceable.
3. **Never commit secrets or personal data.** No tokens, refresh tokens,
   passwords, account names, or absolute home paths (`/Users/<name>/…`) in code,
   comments, logs, or commit messages.
4. **Don't reintroduce known-bad patterns** (see `HANDOFF.md` §7):
   per-file Steam logons (rate-limit), `wine explorer /desktop` for windowed mode
   (un-movable borderless window), or the real Steam client on GPTK (webhelper
   crash-loop).
5. **Keep the Wine username pinned to `crossover`** (`USER`/`USERNAME` in
   `BottleStore.environment`). It's GPTK's hardcoded default, forced on every
   runtime so save paths (`drive_c/users/crossover/…`) stay the same when a
   bottle switches Wine. Changing it strands existing bottles' saves unless
   their user folders are migrated.

## Commands

```bash
swift build                      # compile the app
swift test                       # run the offline Swift tests
swift run BEER                   # run the app (a human does this to test)
./scripts/build_cloudsync.sh     # build the CloudSync helper and install it to App Support
./scripts/build_app.sh [version] # build a distributable .app + zip (bundles the helper, ad-hoc signs)
dotnet test Tools/CloudSync.Tests/CloudSync.Tests.csproj -c Release  # helper's offline tests
```

The helper lives in `Tools/CloudSync/` (C# / .NET 9 / SteamKit2); see its
`README.md`. CI runs `swift build`, `swift test`, and the helper's build,
`dotnet format --verify-no-changes` and tests.

## Testing

Test offline first. A human testing on their own account is the last step, for
what a fake can't cover — not the first.

1. **Write an XCTest that fakes the outside world.** Anything that touches Steam
   account state (auth and tokens, cloud sync, presence, achievements, anything
   that reads CloudSync output) or machine state (drives, disk space, network
   downloads) gets an offline test alongside it. Tests never sign in to a real
   account.
2. **Reuse an existing seam before adding one.** If none fits, make the lookup
   swappable the same way (a stored closure defaulting to the real one) and add
   it to the list below.
3. **Then list what still needs a person**: signing in, QR scans, a real sync
   or download, a game actually launching. Say in the PR what you tested and
   what you didn't.

### Test seams that exist

| Fakes | Seam | Example test |
|---|---|---|
| Steam (the CloudSync helper) | `Tests/BEERTests/Support/FakeSteam.swift`, passed as `CloudSyncClient(binary:)`. Answers commands from what the test sets and records every call. Teach it new commands as needed. | `CloudSaveRestoreSyncTests` |
| Free disk space | `InstallSpaceCheck.freeSpace` | `InstallSpaceCheckTests` |
| Mounted drives | `Tests/BEERTests/Support/FakeDrives.swift`, handed in as a `VolumeCatalog` | `InstallLocationTests`, `CloudSyncDriveTests` |
| Same-volume check for moves | `GameMove.isSameVolume` | `GameMoveTests` |
| Network downloads (icons) | `GameShortcutStore.fetch`, `ShortcutIconViewModel`'s `fetch` | `GameShortcutTests`, `ShortcutIconViewModelTests` |
| GitHub release lists, macOS version (runtimes) | `RuntimeInstaller(fetch:macOSMajorVersion:)`; `ToolchainDetector.preferredGameRuntime(in:macOSMajorVersion:manifest:)` | `RuntimeCatalogTests`, `PreferredRuntimeTests` |
| Large file downloads (runtimes) | `FileDownload.run(configuration:)`, given a session whose `protocolClasses` serve the bytes | `FileDownloadTests` |
| Rosetta installed | `BottleStore.rosettaInstalled` | `RosettaCheckTests` |
| Custom art folder | `CustomArtFiles.copy(into:)` / `remove(in:)`, pointed at a temp folder | `LibraryOrganizeTests` |

The helper has its own offline xUnit tests in `Tools/CloudSync.Tests/`.

## Project layout

See [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md) for the folder map and placement rules. Follow it when adding files: views nest under the screen that owns them, shared views go in `Reuseable Views/`, and numbers and strings go in `Constants/`.

- Apple Silicon + macOS 14+ only. The runtime is Apple GPTK Wine (`winemac.drv`).
- App state lives in `~/Library/Application Support/BEER/` (see `AppPaths.swift`).
- When debugging cloud sync, read `CloudSaveBackups/<appid>/last-sync.log`
  first, then the bottle's `beer.log`.

## Working agreement

- **Verify by building and testing offline, not by running against an
  account.** State honestly what you did and did not test.
- **Shell out safely:** use `ShellRunner` with an argument array (`Process`),
  never a shell string. No `sh -c` with interpolated user input.
- **Persist secrets in the Keychain** (`Keychain` / `SteamAuthStore`), never in a
  plaintext file. Non-secret state goes in Application Support as JSON.
- **Scope your changes.** One concern per change. Don't rename, reformat, or
  refactor unrelated code in the same diff.
- **Match the surrounding code** — naming, comment density, and idiom. Read
  `CONVENTIONS.md` before adding a new store/installer.
- **You cannot merge.** All changes land via pull request and require the
  maintainer's approval (`master` is protected). Branch off `dev`, open the PR
  against `dev`, and don't push to `master`.
- **Never push to `dev` or `master`.** Not directly, not by accident. Create
  branches with `git switch -c <branch> --no-track origin/dev`: without
  `--no-track`, the branch's upstream is `dev` and a plain `git push` lands
  your commits on `dev` with no PR. Push only with
  `git push -u origin <branch>`, and only when asked.
