# BEER

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
swift run BEER
```

## Build a distributable app

```bash
scripts/build_app.sh 0.3.1      # → .build/BEER.app + .build/BEER.zip
```
The script compiles the app, bundles the native CloudSync helper, ad-hoc signs, and
zips it. The build isn't notarized, so a downloader must run once:
```bash
xattr -dr com.apple.quarantine /Applications/BEER.app
```

## First run

The app installs DepotDownloader, walks you through QR sign-in, and downloads Apple's
Game Porting Toolkit runtime (large) the first time you install a game.

## More

- `HANDOFF.md` — architecture, debugging entry points, and known sharp edges.
- `CONTRIBUTING.md` — how to build, test, and submit a pull request.
- `CONVENTIONS.md` — coding conventions and what "done" means for a PR.
- `GOVERNANCE.md` — how changes land and the senior-maintainer path.
- `CODE_OF_CONDUCT.md` — expectations for everyone in the project's spaces.
- `AGENTS.md` / `CLAUDE.md` — rules for AI coding agents working in this repo.
- `Tools/CloudSync/README.md` — the SteamKit2 cloud helper.

## Project status

This started with one goal: play **Kingdom Come: Deliverance** on a MacBook,
seamlessly. That goal is met — the game runs well, saves sync, and the original
author has largely wrapped up active development.

**Honest disclaimer:** most of this codebase was written by AI, and it shows.
It works, but it is heavily AI-generated and needs real human hands — refactoring,
hardening, test coverage, and architectural judgment. Treat the current code as a
working prototype to be cleaned up, not as a polished foundation.

The maintainer is a senior developer and can review pull requests, but can't push
the project forward alone. **If you're an experienced developer who wants to help
steer it** — clean up the AI cruft, own a subsystem, or come on as a senior
maintainer — reach out at **[redacted]**. Forks and PRs from anyone
are welcome regardless; see `CONTRIBUTING.md` to get started.

## Contributing

Contributions are welcome. Please read `CONTRIBUTING.md` first — the short
version: Apple Silicon + macOS 14+ only, test only against your **own** Steam
account, and never let anything touch saves without a backup.

## Disclaimers

Please read these before using or distributing BEER. This is not legal advice.

- **For games you own.** BEER uses *your own* Steam account to download games
  *you have purchased*, via [DepotDownloader](https://github.com/SteamRE/DepotDownloader).
  It is not a piracy tool and does not unlock, crack, or grant access to content
  you don't own. Don't use it to obtain or run software you haven't bought.
- **Steam Subscriber Agreement / account risk.** Downloading outside the official
  client, running games outside it, and applying the Goldberg/GBE Steamworks shim
  may violate Steam's terms of service and could put your Steam account at risk,
  up to suspension or ban. **Use entirely at your own risk.** Only ever sign in
  with your own account.
- **Goldberg/GBE.** BEER applies the Goldberg/GBE Steamworks emulator so games
  that call the Steamworks API can run without the official client. It emulates
  that API for games you own; it is not a means of bypassing purchase.
- **Not affiliated.** BEER is an independent project. It is not affiliated with,
  endorsed by, or sponsored by Valve, Steam, Apple, or the GameNative project.
  "Steam" and all other trademarks belong to their respective owners; names are
  used only to describe interoperability.
- **No warranty.** Provided "as is" under the MIT license, with no warranty of
  any kind. BEER manipulates game files and save data; despite automatic save
  backups, the authors are not liable for lost saves, data, or any action taken
  against your account.

If you are a rights holder with a concern about this repository, please open an
issue or contact the maintainer at **[redacted]**.

## License

[MIT](LICENSE). DepotDownloader, Goldberg/GBE, and Apple's Game Porting Toolkit
are fetched at runtime by the app and keep their own licenses — they are not
redistributed in this repository.
