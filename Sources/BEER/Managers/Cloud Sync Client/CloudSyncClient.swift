import Foundation

// Swift wrapper around the native `CloudSync` helper (Tools/CloudSync, built on
// SteamKit2). The helper speaks the real Steam *client* cloud protocol — the
// same one the Steam app uses — so it can both download AND upload cloud saves,
// authenticating with the user's own refresh token (no Publisher key needed).
//
// The helper prints one JSON object per line on stdout; human/log noise goes to
// stderr. ShellRunner merges both streams, so we parse line-by-line and act on
// whichever lines decode to a recognized JSON shape — anything that isn't JSON
// (the helper's "connected; logging on…" notes) is ignored.

struct CloudSyncClient {}
