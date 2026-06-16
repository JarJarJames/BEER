# Contributing to GameNative for Mac

Thanks for your interest! This started as a personal project and is now open so
others can build their own launchers, fix bugs, and add features. Pull requests
are welcome — small focused ones are easiest to review and merge.

## Ground rules

- **Apple Silicon (M1+) and macOS 14+ only.** The runtime is Apple's Game
  Porting Toolkit (GPTK) Wine. Intel Macs are out of scope.
- **Only ever test against your *own* Steam account.** Sign-in, cloud-save sync,
  and library features touch a live Steam account. Use yours, never anyone
  else's, and never paste credentials or tokens into an issue or PR.
- **Protect saves.** Anything that writes or deletes local or cloud saves must
  back up first — the engine already does this, so keep it that way. Treat save
  data as irreplaceable.

## Project layout

- `Sources/GameNativeMac/` — the SwiftUI app (UI, bottle management, install /
  launch, sync orchestration).
- `Tools/CloudSync/` — the native Steam-client helper (C# / .NET 9 / SteamKit2)
  for auth, owned games, and cloud read/write. See its `README.md`.
- `scripts/` — build scripts.
- `HANDOFF.md` — full architecture, debugging entry points, and known sharp
  edges. **Read this before making non-trivial changes.**
- `CLAUDE.md` — operating guide if you use an AI coding agent in this repo.

## Building

```bash
swift build                      # compile the app
swift run GameNativeMac          # run it
./scripts/build_cloudsync.sh     # build + install the CloudSync helper
./scripts/build_app.sh [version] # build a distributable .app + zip
```

`dotnet` (>= .NET 9) is required for the CloudSync helper. You can also just open
`Package.swift` in Xcode and hit Cmd+R.

## Submitting a pull request

1. Fork the repo and branch off `master`.
2. Keep changes focused; one concern per PR.
3. Make sure `swift build` succeeds. If you touched the helper, make sure
   `./scripts/build_cloudsync.sh` builds too.
4. Describe **what** you changed and **how you tested it** (which game, which
   Mac, what you observed). Since most features need a live account, reviewers
   often can't reproduce — your testing notes are how we gain confidence.
5. Don't reintroduce the known-bad patterns documented in `HANDOFF.md` §7
   (per-file Steam logons, `wine explorer /desktop` for windowed mode, the real
   Steam client on GPTK).

## Reporting bugs

Open an issue with your macOS version, Mac model (chip), the game/app involved,
and the relevant log. For sync problems, the most useful logs are
`CloudSaveBackups/<appid>/last-sync.log` and the bottle's `gamenative.log`.
**Redact your account name and any tokens** before pasting logs.
