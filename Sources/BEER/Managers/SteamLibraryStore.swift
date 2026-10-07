import AppKit
import Foundation

// App-level Steam account + owned-games store.
//
// Sign-in is QR-only: the user scans a code with the Steam Mobile App (see
// SteamAuthStore), and we pull the owned-games list through that authenticated
// client session via the CloudSync helper — no Steam Web API key, no password.
@MainActor
final class SteamLibraryStore: ObservableObject {
    @Published var account: SteamAccount = .signedOut
    @Published private(set) var games: [SteamLibraryGame] = []
    @Published private(set) var isFetchingLibrary = false
    @Published var lastError: String?

    private let cloudClient = CloudSyncClient()

    func load() {
        guard let data = try? Data(contentsOf: AppPaths.steamLibraryStateURL),
              let payload = try? JSONDecoder().decode(StoredState.self, from: data) else {
            return
        }
        account = payload.account
        games = payload.games
    }

    func signOut() {
        account = .signedOut
        games = []
        persist()
    }

    /// Finish sign-in after a successful QR auth: pull the owned-games list via
    /// the authenticated client session. `auth` holds the account name +
    /// refresh token + SteamID64 from the QR flow.
    func signInWithQR(auth: SteamAuthStore) async {
        guard let acct = auth.account else {
            lastError = "Steam sign-in didn't complete. Try scanning the QR again."
            return
        }
        isFetchingLibrary = true
        defer { isFetchingLibrary = false }

        // The QR auth already succeeded, so we ARE signed in — mark it first.
        // Fetching the games list is a separate step that can be retried; if
        // it's throttled (e.g. Steam rate-limited us), we still let the user
        // into the app with an empty grid + a Refresh button, rather than
        // trapping them on the sign-in screen.
        account = SteamAccount(
            username: acct.accountName,
            steamID64: acct.steamID64,
            avatarURL: nil,
            isLoggedIn: true
        )
        persist()

        do {
            let fetched = try await fetchOwnedGamesViaClient(account: acct)
            games = fetched.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            persist()
        } catch {
            auth.noteCloudError(error)
            lastError = "Signed in, but couldn't load your games yet (\((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)). Tap Refresh in a minute."
        }
    }

    /// Refresh the owned-games list via the authenticated client session.
    func fetchLibrary(auth: SteamAuthStore? = nil) async {
        guard account.isLoggedIn, let acct = auth?.account else { return }
        isFetchingLibrary = true
        defer { isFetchingLibrary = false }

        do {
            let fetched = try await fetchOwnedGamesViaClient(account: acct)
            let fetchedAppIDs = Set(fetched.map(\.appID))
            // Preserve installedBottleID associations.
            var merged = fetched.map { fresh -> SteamLibraryGame in
                if let existing = games.first(where: { $0.appID == fresh.appID }) {
                    var updated = fresh
                    updated.installedBottleID = existing.installedBottleID
                    return updated
                }
                return fresh
            }
            // A game already installed here must never vanish from the list
            // just because this particular fetch didn't include its appID —
            // that would silently orphan a working bottle from the UI that
            // launches it. Steam's owned-games response is the source of
            // truth for everything else, but not for "is this uninstalled".
            let stillInstalledButMissing = games.filter {
                $0.installedBottleID != nil && !fetchedAppIDs.contains($0.appID)
            }
            merged.append(contentsOf: stillInstalledButMissing)
            games = merged
            persist()
        } catch {
            auth?.noteCloudError(error)
            lastError = "Could not refresh library: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
        }
    }

    private func fetchOwnedGamesViaClient(account acct: SteamCloudAccount) async throws -> [SteamLibraryGame] {
        let owned = try await cloudClient.ownedGames(
            steamID64: acct.steamID64,
            account: acct.accountName,
            refreshToken: acct.refreshToken
        )
        return owned.map {
            SteamLibraryGame(
                appID: $0.appID,
                name: $0.name,
                headerImageURL: nil,
                iconURL: $0.iconURL,
                sizeOnDiskBytes: nil,
                lastPlayed: $0.lastPlayed,
                playtimeMinutes: $0.playtimeMinutes
            )
        }
    }

    /// Apply a fresh play-time total reported by a finished play session.
    ///
    /// Never moves the counter backwards: Steam may not have credited the
    /// session yet when the helper re-reads it, and a stale-but-lower total
    /// must not overwrite a good one. The next library refresh corrects it.
    func recordPlaytime(appID: Int, minutes: Int) {
        guard let index = games.firstIndex(where: { $0.appID == appID }) else { return }
        guard minutes > (games[index].playtimeMinutes ?? 0) else { return }
        games[index].playtimeMinutes = minutes
        persist()
    }

    func markInstalled(appID: Int, bottleID: UUID) {
        guard let index = games.firstIndex(where: { $0.appID == appID }) else { return }
        games[index].installedBottleID = bottleID
        persist()
    }

    func markUninstalled(appID: Int) {
        guard let index = games.firstIndex(where: { $0.appID == appID }) else { return }
        games[index].installedBottleID = nil
        persist()
    }

    private func persist() {
        do {
            try AppPaths.ensureBaseDirectories()
            let payload = StoredState(account: account, games: games)
            let data = try JSONEncoder().encode(payload)
            try data.write(to: AppPaths.steamLibraryStateURL, options: .atomic)
        } catch {
            lastError = "Could not save Steam library state: \(error.localizedDescription)"
        }
    }

    private struct StoredState: Codable {
        let account: SteamAccount
        let games: [SteamLibraryGame]
    }
}
