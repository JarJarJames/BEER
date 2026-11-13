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
    var updateCheck = GameUpdateCheck()

    func load() {
        guard let data = try? Data(contentsOf: AppPaths.steamLibraryStateURL),
              let payload = try? JSONDecoder().decode(StoredState.self, from: data) else {
            return
        }
        account = payload.account
        games = payload.games
    }

    /// Sign out without touching the games. Each one carries what BEER
    /// knows about it locally — which bottle it's installed in, favorite,
    /// hidden, custom art — and dropping the Steam ones here lost all of it:
    /// signing back in rebuilt the list from Steam, which knows none of it.
    /// The next sign-in folds Steam's list into this one (`merge`).
    func signOut() {
        account = .signedOut
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
            games = Self.merge(existing: games, fetched: fetched)
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
            games = Self.merge(existing: games, fetched: fetched)
            persist()
        } catch {
            auth?.noteCloudError(error)
            lastError = "Could not refresh library: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
        }
    }

    /// Fold a fresh owned-games fetch into the current list.
    nonisolated static func merge(existing: [SteamLibraryGame], fetched: [SteamLibraryGame]) -> [SteamLibraryGame] {
        let fetchedAppIDs = Set(fetched.map(\.appID))
        // Keep what BEER knows about each game that Steam's list doesn't carry.
        var merged = fetched.map { fresh -> SteamLibraryGame in
            if let current = existing.first(where: { $0.appID == fresh.appID }) {
                var updated = fresh
                updated.installedBottleID = current.installedBottleID
                updated.clientIconURL = current.clientIconURL
                updated.shortcutIcon = current.shortcutIcon
                updated.isFavorite = current.isFavorite
                updated.isHidden = current.isHidden
                updated.customArt = current.customArt
                updated.updateStatus = current.updateStatus
                return updated
            }
            return fresh
        }
        // A game already installed here must never vanish from the list
        // just because this particular fetch didn't include its appID —
        // that would silently orphan a working bottle from the UI that
        // launches it. Steam's owned-games response is the source of
        // truth for everything else, but not for "is this uninstalled".
        merged.append(contentsOf: existing.filter {
            !$0.effectiveIsNonSteam && $0.installedBottleID != nil && !fetchedAppIDs.contains($0.appID)
        })
        // Non-Steam games aren't in Steam's response at all.
        merged.append(contentsOf: existing.filter(\.effectiveIsNonSteam))
        return merged
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

    /// Link each Steam game that has an installed bottle but no install on
    /// record. The bottle keeps its app ID even when the library loses the
    /// link — as an older sign-out did — and without it the game looks
    /// uninstalled though its files and saves are all there.
    func relinkInstalledGames(bottles: [Bottle]) {
        guard let relinked = Self.relinking(games, to: bottles) else { return }
        games = relinked
        persist()
    }

    /// `games` with lost install links restored, or nil when none were lost.
    /// Of two installed bottles for one game, the latest-updated wins.
    nonisolated static func relinking(_ games: [SteamLibraryGame], to bottles: [Bottle]) -> [SteamLibraryGame]? {
        var bottleForApp: [Int: Bottle] = [:]
        for bottle in bottles {
            guard let appID = bottle.steamAppID,
                  bottle.gameInstallStatus == .installed || bottle.gameInstallStatus == .updateAvailable else { continue }
            if let current = bottleForApp[appID], current.updatedAt >= bottle.updatedAt { continue }
            bottleForApp[appID] = bottle
        }
        var changed = false
        let relinked = games.map { game -> SteamLibraryGame in
            guard !game.effectiveIsNonSteam, game.installedBottleID == nil,
                  let bottle = bottleForApp[game.appID] else { return game }
            var linked = game
            linked.installedBottleID = bottle.id
            changed = true
            return linked
        }
        return changed ? relinked : nil
    }

    func markInstalled(appID: Int, bottleID: UUID) {
        guard let index = games.firstIndex(where: { $0.appID == appID }) else { return }
        games[index].installedBottleID = bottleID
        persist()
    }

    func setClientIconURL(_ url: URL?, appID: Int) {
        guard let index = games.firstIndex(where: { $0.appID == appID }),
              games[index].clientIconURL != url?.absoluteString else { return }
        games[index].clientIconURL = url?.absoluteString
        persist()
    }

    func setShortcutIcon(_ choice: ShortcutIconChoice, appID: Int) {
        guard let index = games.firstIndex(where: { $0.appID == appID }) else { return }
        games[index].shortcutIcon = choice
        persist()
    }

    func markUninstalled(appID: Int) {
        guard let index = games.firstIndex(where: { $0.appID == appID }) else { return }
        games[index].installedBottleID = nil
        games[index].updateStatus = nil
        persist()
    }

    /// Ask Steam whether installed games have an update, and record each one's
    /// status. Quiet on failure: statuses stay as the last check left them, and
    /// a missed check never stops anyone playing.
    func checkForUpdates(bottles: BottleStore, auth: SteamAuthStore?) async {
        guard account.isLoggedIn, let acct = auth?.account, auth?.sessionExpired != true else { return }
        let targets = GameUpdateCheck.targets(games: games, bottles: bottles.bottles) {
            bottles.installLocation(of: $0).url
        }
        guard !targets.isEmpty else { return }
        do {
            applyUpdateCheck(try await updateCheck.run(targets: targets, account: acct))
        } catch {
            auth?.noteCloudError(error)
            Log.install.error("Update check failed: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)")
        }
    }

    /// Set the status of each game in `results`; others keep theirs.
    func applyUpdateCheck(_ results: [Int: GameUpdateStatus]) {
        guard let updated = Self.applying(updateCheck: results, to: games) else { return }
        games = updated
        persist()
    }

    /// `games` with each status in `results` set, or nil when nothing changes.
    nonisolated static func applying(
        updateCheck results: [Int: GameUpdateStatus], to games: [SteamLibraryGame]
    ) -> [SteamLibraryGame]? {
        var games = games
        var changed = false
        for (appID, status) in results where status != .unknown {
            guard let index = games.firstIndex(where: { $0.appID == appID }),
                  games[index].updateStatus != status else { continue }
            games[index].updateStatus = status
            changed = true
        }
        return changed ? games : nil
    }

    /// Add a game that lives outside Steam. Gets a negative placeholder appID,
    /// which can't collide with a real one and is kept in the saved state so
    /// the game keeps its identity across launches.
    @discardableResult
    func addNonSteamGame(name: String, bottleID: UUID, customImagePath: String?) -> SteamLibraryGame {
        let taken = Set(games.map(\.appID))
        var appID: Int
        repeat { appID = -Int.random(in: 1...Int(Int32.max)) } while taken.contains(appID)
        let game = SteamLibraryGame(
            appID: appID, name: name, installedBottleID: bottleID,
            isNonSteam: true, customImagePath: customImagePath
        )
        games.append(game)
        games.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        persist()
        return game
    }

    func removeNonSteamGame(appID: Int) {
        guard let game = games.first(where: { $0.appID == appID }), game.effectiveIsNonSteam else { return }
        games.removeAll { $0.appID == appID }
        if let path = game.customImagePath {
            try? FileManager.default.removeItem(atPath: path)
        }
        game.customArt?.paths.forEach { CustomArtFiles.remove(path: $0) }
        persist()
    }

    func setFavorite(_ isFavorite: Bool, appID: Int) {
        guard let index = games.firstIndex(where: { $0.appID == appID }) else { return }
        games[index].isFavorite = isFavorite ? true : nil
        persist()
    }

    func setHidden(_ isHidden: Bool, appID: Int) {
        guard let index = games.firstIndex(where: { $0.appID == appID }) else { return }
        games[index].isHidden = isHidden ? true : nil
        persist()
    }

    /// Points one piece of a game's art at a copy in `AppPaths.customArtDirectory`,
    /// or back to Steam's with nil. The copy it replaces is deleted.
    func setCustomArt(_ path: String?, slot: GameArtSlot, appID: Int) {
        guard let index = games.firstIndex(where: { $0.appID == appID }) else { return }
        var art = games[index].customArt ?? CustomGameArt()
        if let old = art.path(for: slot), old != path { CustomArtFiles.remove(path: old) }
        art.setPath(path, for: slot)
        games[index].customArt = art.isEmpty ? nil : art
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
