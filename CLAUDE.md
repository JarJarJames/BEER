# CLAUDE.md

Guidance for AI agents working in this repo. Read `HANDOFF.md` for the full architecture; this is the quick operating guide.

## Hard rules
- **Never authenticate to or access the user's Steam account.** Claude writes/compiles code; the **user runs every test that involves signing in, scanning QR, or syncing** against their live account. Don't run the CloudSync helper's `auth`/`enumerate`/`upload`/`batch` against their token to "verify." Compiling and building are fine.
- **Protect saves.** The user has 60+ hrs of irreplaceable Kingdom Come: Deliverance saves. Anything that writes or deletes local/cloud saves must back up first (the engine already does — keep it that way).

## Commands
```bash
swift build                      # compile the app
swift run BEER          # run it (the user does this to test)
./scripts/build_cloudsync.sh     # build + install the CloudSync helper to App Support
./scripts/build_app.sh [version] # build distributable .app + zip (bundles helper, ad-hoc signs)
```
The CloudSync helper lives in `Tools/CloudSync/` (C# / .NET 9 / SteamKit2). `dotnet` is installed. See `Tools/CloudSync/README.md`.

## Testing
- Prefer **Swift Tests (XCTest)** over manual/live verification for account-related logic. When you write or touch code that deals with Steam account state — auth/token handling, cloud sync, presence, achievements, anything that parses or reacts to CloudSync output — add an offline test alongside it rather than relying solely on the user to click through it live.
- Tests must be **offline-capable**: mock/stub the CloudSync helper boundary (its CLI output, JSON, exit codes) or inject fake protocol responses — never authenticate against the real account from a test (this doesn't relax the hard rule above).
- Goal is cumulative: build a real, growing suite of offline Account tests over time, so regressions in account-adjacent logic get caught without a live Steam session every time.

## Layout
- `Sources/BEER/` — the SwiftUI app. Follow [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md) when adding files: views nest under the screen that owns them, shared views go in `Reuseable Views/`, numbers and strings go in `Constants/`.
- `Tools/CloudSync/` — the native Steam-client helper (auth, owned games, cloud read/write).
- `scripts/` — build scripts.
- State lives in `~/Library/Application Support/BEER/` (see `Paths.swift`).

## Conventions
- Apple Silicon + macOS 14+ only. Runtime is Apple GPTK Wine (`winemac.drv`).
- Branch: work on a feature branch; `master` is the main line. Commit/push only when asked.
- When debugging cloud sync, read `CloudSaveBackups/<appid>/last-sync.log` first, then the bottle's `beer.log`.
- Don't reintroduce: per-file Steam logons (rate-limit), `wine explorer /desktop` for windowed mode (borderless/un-movable), or the real Steam client on GPTK (webhelper crash-loop). See `HANDOFF.md` §7.
- **Wine username is pinned to `crossover`** (`USER`/`USERNAME` in `BottleStore.environment`). It's GPTK's hardcoded default; we force it on every runtime so save paths (`drive_c/users/crossover/…`) stay consistent when a bottle switches Wine. Not a CrossOver dependency — just a compatibility constant. Don't change it without migrating existing bottles' user folders.
