# AGENTS.md

Rules for **any** AI coding agent working in this repo (Claude, Cursor, Copilot,
Aider, etc.). These mirror the human contributor rules — see `CONTRIBUTING.md`,
`CONVENTIONS.md`, and `CLAUDE.md` (the Claude-specific operating guide).

## Hard rules (do not break)

1. **Never authenticate to or access anyone's Steam account.** Agents write and
   compile code only. A human runs every test that involves signing in, scanning
   a QR code, downloading, or syncing — against **their own** account. Do not run
   the CloudSync helper's `auth` / `enumerate` / `upload` / `batch` against a real
   token to "verify." Compiling and building are fine.
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
5. **Keep the Wine username pinned to `crossover`.** It's GPTK's hardcoded
   default; changing it strands existing bottles' save paths.

## Project Layout

See [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md) for the folder map and placement rules. Follow it when adding files: views nest under the screen that owns them, shared views go in `Reuseable Views/`, and numbers and strings go in `Constants/`.

## Working agreement

- **Verify by building, not by running against an account:** `swift build` for
  the app, `dotnet build Tools/CloudSync/CloudSync.csproj -c Release` for the
  helper. State honestly what you did and did not test.
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
