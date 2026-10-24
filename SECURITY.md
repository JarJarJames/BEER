# Security Policy

This app authenticates to Steam on the user's behalf and handles Steam
refresh tokens and save data. If you find a vulnerability — especially one
that could leak a token, a credential, or a save file, or that authenticates
against an account other than the running user's — please report it privately.

**Do not open a public issue for security problems.** Instead, use GitHub's
[private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability)
(the "Report a vulnerability" button under the repo's **Security** tab).

Please never include real tokens, passwords, or another person's account data
in a report — a description and reproduction steps are enough.

## Withdrawn releases

Releases before 0.5.0 have been taken down. Builds before 0.3.1 kept Steam
credentials in plaintext JSON files in `~/Library/Application Support`:

- **Before 0.2.1:** the Steam Web API key you entered at sign-in. 0.2.1 replaced
  that sign-in with QR-only login and dropped the key.
- **Before 0.3.1:** the Steam refresh token from QR sign-in. 0.3.1 moved it into
  the macOS Keychain, and on first launch it migrates the old file and then
  deletes it.

The files could only be read by your macOS user account. No remote exploit was
reported. Current builds store no Steam credentials in plaintext.

**If you used a build older than 0.3.1:** update. Then revoke the Web API key at
[steamcommunity.com/dev/apikey](https://steamcommunity.com/dev/apikey) if you
ever entered one. Signing in to BEER again with a new QR code issues a fresh
token. You can also end old sessions from **Steam Guard → Deauthorize all other
devices** in the Steam Mobile App.
