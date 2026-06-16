# GameNative for Mac

An experimental native macOS app that turns your Steam library into installable,
per-game Wine bottles — with **bidirectional Steam Cloud save sync** so you can
move between a Windows PC and your Mac.

Inspired by GameNative on Android, adapted to macOS where Wine prefixes ("bottles")
fit better than Docker-style containers.

> **Apple Silicon (M1+) and macOS 14+.** Not for Intel Macs.

## What it does

- **QR sign-in** — log in by scanning a code with the Steam Mobile App. No password
  is ever typed into the app, and no Steam Web API key is needed.
- **Library** — lists your owned games (installed ones float to the top; there's a
  dedicated "Installed" tab).
- **Install per game** — downloads each game with [DepotDownloader](https://github.com/SteamRE/DepotDownloader)
  into its own Wine bottle, drops in the Goldberg/GBE Steamworks shim where needed,
  and runs it on Apple's Game Porting Toolkit (GPTK) Wine.
- **Display handling** — a per-game "Keep my display resolution" option makes
  fullscreen scale to your current resolution instead of switching modes (no
  stretching on unusual Mac resolutions). Note: GPTK runs games borderless and
  owns the window itself, so there's no macOS title bar or green fullscreen
  button — use the game's own Windowed video option for a smaller view.
- **Cloud saves** — saves sync both ways with Steam Cloud automatically (pull before
  play, push after). Every sync backs up local saves first, so nothing is overwritten
  without a recoverable copy.

This does **not** run the real Steam client and does not bypass DRM, anti-cheat, or
platform restrictions. (A legacy "run the Steam client in Wine" path still exists
behind Compatibility → New Manual Bottle, but it's parked — see `HANDOFF.md` §7.)

## Run (development)

```bash
swift run GameNativeMac
```

## Build a distributable app

```bash
scripts/build_app.sh 0.2.0      # → .build/GameNative.app + .build/GameNative.zip
```
The script compiles the app, bundles the native CloudSync helper, ad-hoc signs, and
zips it. The build isn't notarized, so a downloader must run once:
```bash
xattr -dr com.apple.quarantine /Applications/GameNative.app
```

## First run

The app installs DepotDownloader, walks you through QR sign-in, and downloads Apple's
Game Porting Toolkit runtime (large) the first time you install a game.

## More

- `HANDOFF.md` — architecture, debugging entry points, and known sharp edges.
- `CONTRIBUTING.md` — how to build, test, and submit a pull request.
- `CLAUDE.md` — operating guide for AI agents working in this repo.
- `Tools/CloudSync/README.md` — the SteamKit2 cloud helper.

## Project status

This is a working hobby project, now community-driven. The original author is
stepping back from active development, so the best way forward is forks and pull
requests — build your own launcher, fix what bugs you, send improvements back.
Issues and PRs are welcome; see `CONTRIBUTING.md` to get started.

## Contributing

Contributions are welcome. Please read `CONTRIBUTING.md` first — the short
version: Apple Silicon + macOS 14+ only, test only against your **own** Steam
account, and never let anything touch saves without a backup.

## License

[MIT](LICENSE). DepotDownloader, Goldberg/GBE, and Apple's Game Porting Toolkit
are fetched at runtime by the app and keep their own licenses — they are not
redistributed in this repository.
