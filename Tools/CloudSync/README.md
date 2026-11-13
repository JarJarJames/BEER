# CloudSync helper

A small .NET 9 / SteamKit2 command-line tool that speaks the real Steam **client**
protocol (CM + unified messages). The Swift app shells out to it for everything
that needs a logged-on Steam session.

Why it exists: the Steam **Web** API (`api.steampowered.com/ICloudService`) gates
cloud enumerate/upload behind a Publisher key. The **client** protocol only needs
the user's own refresh token (the kind SteamKit2's QR flow mints), which is what
unlocks two-way cloud sync — including **upload**, which the old HTML-scrape path
could never do.

## Build / install
```bash
../../scripts/build_cloudsync.sh     # self-contained osx-arm64 → installed to App Support
# or, for the dev build the app also looks for:
dotnet build -c Release
```
`build_app.sh` bundles the published binary inside `BEER.app/Contents/MacOS/CloudSync`.
`CloudSyncClient.locateBinary()` (Swift) searches: App Support → next to the app
executable → the repo dev build.

## Layout

| Path | Contents |
|---|---|
| `Program.cs` | Entry point: parse args, log on once, dispatch, JSON error envelope |
| `Cli/` | `CliArgs` (argument parsing), `SessionRequest` (one request to `session`) and `JsonOutput` (the one stdout writer) |
| `Steam/` | `SteamSession` (logon, retry, callback pump), `BeerDevice` (the device ID BEER logs on as), `LogonFailedException`, `UserStatsHandler`, `AppInfo` (PICS app info) |
| `Commands/` | One class per command below; `CommandDispatch` runs them; `Presence/` holds the long-lived `session` |
| `Transfers/` | `CloudTransfers` (single-file download/upload) and `CloudFileUnwrapper` |
| `Achievements/` | Stats-schema parsing and unlock-bit math |
| `Launch/` | `LaunchConfigPicker`: which `config/launch` entries a Windows install can run |

Rules for adding files are in `PROJECT_STRUCTURE.md` under "C# helper". Tests are in
`../CloudSync.Tests` (`dotnet test ../CloudSync.Tests`), and CI also runs
`dotnet format --verify-no-changes` against `.editorconfig`.

## Commands
Output is one JSON object per line on **stdout**; logs go to **stderr**. Exit 0 = ok.
Auth: `--account NAME --token-file FILE` (refresh token in a file, never on argv).
`--device-file FILE` keeps the device ID BEER logs on as (see below).

**The app runs only `session`.** It logs on once and stays logged on while BEER is
open; every other command below reaches it as a request on stdin:
`{"id": N, "cmd": "enumerate", "args": {"appid": "440"}}`. Requests run
concurrently, every line one emits carries its `id`, and each ends with
`{"id": N, "done": true}`. Lines with no `id` belong to the session itself:
`presence_ready`, status and play reports, and a failed logon's `{error, …}`.
Status and play commands are plain lines: `state <Online|Away|Invisible|Offline>`,
`play <appid>`, `stop`. Offline means the session never sets a status, so it stays
out of Friends. Run by hand, each command logs on for itself.

| Command | What it does | Writes anything? |
|---|---|---|
| `auth` | QR sign-in; emits `{challenge_url}` (re-emits as it rotates) then `{authenticated, account, refresh_token}` | no (account only) |
| `ownedgames --steamid ID` | owned games via `IPlayerService.GetOwnedGames` | no |
| `launchinfo --appid N` | Windows launch options from the app's `config/launch` (`{launch:[{executable,arguments,workingdir,type,description}]}`), best first | no |
| `enumerate --appid N` | list cloud files and save-folder rules (`{files:[{filename,size,timestamp,sha,ugcid}], savefiles:[{root,path,pattern,recursive,platforms}]}`) | **no — safe to run** |
| `download --appid N --file F --out PATH` | download one cloud file | local only |
| `upload --appid N --file F --in PATH [--mtime T]` | upload one file (begin → PUT blocks → commit) | **writes cloud** |
| `batch --appid N --jobs JSON` | many downloads+uploads in ONE logon | local + cloud |
| `prepare-depot-auth --depot-executable PATH` | bridge the existing token into DepotDownloader for one invocation | short-lived local credential cache |
| `updatecheck --jobs JSON` | whether each installed game is behind Steam's public branch, from the DepotDownloader record in its folder (`{games:[{appid,status}]}`, status `current`/`update`/`untracked`/`unknown`) | no |

`batch` jobs file: `{ "appid": N, "downloads":[{"filename","out"}], "uploads":[{"filename","in","mtime"}] }`.
It runs up to four file transfers concurrently, reusing one HTTP connection pool,
inside the one Steam session. Downloads finish
before uploads begin. Per-op it emits `{op, filename, ok|error}`, then
`{summary, downloaded, uploaded, failed}`.

Errors: a logon rejection emits `{error, auth_failed:true}` (revoked/expired → reconnect)
or `{error, rate_limited:true}` (throttled → **wait, don't re-auth**).

## DepotDownloader authentication bridge

DepotDownloader does not expose a command-line option for an existing
SteamClient refresh token, although internally it logs on with one from its
`account.config`. BEER's download controller calls `prepare-depot-auth` with the
same Keychain-owned token used for library and cloud access, runs
DepotDownloader with `-remember-password`, then immediately removes the cache.
The token is passed to this helper through a temporary file, never argv. BEER
also records the cache path so a launch after an app crash removes any remnant.

## Critical design notes
**One logon for all of BEER.** Every command goes through the one `session`.
Spawning a process (= a fresh Steam logon) per file got the account CM-rate-limited
after ~100 logons, and every extra session is another chance to collide with the
user's own Steam clients (#65). Don't add a command that logs on for itself, and
don't go back to per-file `download`/`upload` calls inside a loop. DepotDownloader
is the one exception: it's a separate program and logs on by itself.

**BEER is its own device.** SteamKit2 builds its macOS machine ID from the Mac's
serial number and boot disk, the same inputs Steam's own client uses, so BEER
logged on looking like the Mac's own Steam client. `BeerDevice` gives Steam a
random ID made once per install instead.

## Debugging by hand
`enumerate` and `download` are read-only/safe. Example (do this only with the
account owner's consent — per the repo rules, that's the user, not the agent):
```bash
echo "$REFRESH_TOKEN" > /tmp/tok
./bin/Release/net9.0/CloudSync enumerate --appid 379430 --account NAME --token-file /tmp/tok
```
