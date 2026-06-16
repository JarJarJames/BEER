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

## Commands
Output is one JSON object per line on **stdout**; logs go to **stderr**. Exit 0 = ok.
Auth: `--account NAME --token-file FILE` (refresh token in a file, never on argv).

| Command | What it does | Writes anything? |
|---|---|---|
| `auth` | QR sign-in; emits `{challenge_url}` (re-emits as it rotates) then `{authenticated, account, refresh_token}` | no (account only) |
| `ownedgames --steamid ID` | owned games via `IPlayerService.GetOwnedGames` | no |
| `enumerate --appid N` | list cloud files (`{files:[{filename,size,timestamp,sha,ugcid}]}`) | **no — safe to run** |
| `download --appid N --file F --out PATH` | download one cloud file | local only |
| `upload --appid N --file F --in PATH [--mtime T]` | upload one file (begin → PUT blocks → commit) | **writes cloud** |
| `batch --appid N --jobs JSON` | many downloads+uploads in ONE logon | local + cloud |

`batch` jobs file: `{ "appid": N, "downloads":[{"filename","out"}], "uploads":[{"filename","in","mtime"}] }`.
Per-op it emits `{op, filename, ok|error}`, then `{summary, downloaded, uploaded, failed}`.

Errors: a logon rejection emits `{error, auth_failed:true}` (revoked/expired → reconnect)
or `{error, rate_limited:true}` (throttled → **wait, don't re-auth**).

## Critical design note
**One logon per process; one process per sync.** Spawning a process (= a fresh
Steam logon) per file gets the account CM-rate-limited after ~100 logons — that was
a real bug. `enumerate` is one logon, `batch` is one logon; that's it. Don't go back
to per-file `download`/`upload` calls inside a loop.

## Debugging by hand
`enumerate` and `download` are read-only/safe. Example (do this only with the
account owner's consent — per the repo rules, that's the user, not the agent):
```bash
echo "$REFRESH_TOKEN" > /tmp/tok
./bin/Release/net9.0/CloudSync enumerate --appid 379430 --account NAME --token-file /tmp/tok
```
