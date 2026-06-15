import AppKit
import Foundation

// App-level Steam account + owned-games store.
//
// Sign-in flow calls Valve's public Steam Web API:
//   1. ResolveVanityURL — turn a custom URL / vanity into a SteamID64
//   2. GetPlayerSummaries — pull the persona name + avatar
//   3. GetOwnedGames — pull the user's owned games (appID + name)
//
// We never store the Steam password. SteamCMD itself caches a session token
// after its own login (used later for game downloads).
@MainActor
final class SteamLibraryStore: ObservableObject {
    @Published var account: SteamAccount = .signedOut
    @Published private(set) var games: [SteamLibraryGame] = []
    @Published private(set) var isFetchingLibrary = false
    @Published var lastError: String?

    func load() {
        guard let data = try? Data(contentsOf: AppPaths.steamLibraryStateURL),
              let payload = try? JSONDecoder().decode(StoredState.self, from: data) else {
            return
        }
        account = payload.account
        games = payload.games
    }

    // Top-level sign-in: resolves the profile input, pulls persona + library.
    func signIn(profile: String, webAPIKey: String) async {
        let trimmedProfile = profile.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = webAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedProfile.isEmpty else {
            lastError = "Enter your Steam profile URL, vanity name, or SteamID64."
            return
        }
        guard !trimmedKey.isEmpty else {
            lastError = "Enter your Steam Web API key. Get one free at https://steamcommunity.com/dev/apikey"
            return
        }

        isFetchingLibrary = true
        defer { isFetchingLibrary = false }

        do {
            let steamID = try await resolveSteamID(input: trimmedProfile, apiKey: trimmedKey)
            let summary = try await fetchPlayerSummary(steamID: steamID, apiKey: trimmedKey)
            let fetchedGames = try await fetchOwnedGames(steamID: steamID, apiKey: trimmedKey)

            account = SteamAccount(
                username: summary.personaname.isEmpty ? steamID : summary.personaname,
                steamID64: steamID,
                webAPIKey: trimmedKey,
                avatarURL: summary.avatarfull,
                isLoggedIn: true
            )
            games = fetchedGames
            persist()
        } catch let error as SteamAPIError {
            lastError = error.errorDescription
        } catch {
            lastError = "Sign-in failed: \(error.localizedDescription)"
        }
    }

    func signOut() {
        account = .signedOut
        games = []
        persist()
    }

    private let cloudClient = CloudSyncClient()

    /// Finish sign-in after a successful QR auth: pull the owned-games list via
    /// the authenticated client session (no Web API key). `auth` holds the
    /// account name + refresh token + SteamID64 from the QR flow.
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
            webAPIKey: nil,
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

    /// Refresh the owned-games list. Uses the authenticated client session when
    /// we have a refresh token (QR sign-in), else falls back to the Web API key
    /// path for legacy accounts.
    func fetchLibrary(auth: SteamAuthStore? = nil) async {
        guard account.isLoggedIn else { return }
        isFetchingLibrary = true
        defer { isFetchingLibrary = false }

        do {
            let fetched: [SteamLibraryGame]
            if let acct = auth?.account {
                fetched = try await fetchOwnedGamesViaClient(account: acct)
            } else if let steamID = account.steamID64, let key = account.webAPIKey {
                fetched = try await fetchOwnedGames(steamID: steamID, apiKey: key)
            } else {
                return
            }
            // Preserve installedBottleID associations.
            games = fetched.map { fresh in
                if let existing = games.first(where: { $0.appID == fresh.appID }) {
                    var merged = fresh
                    merged.installedBottleID = existing.installedBottleID
                    return merged
                }
                return fresh
            }
            persist()
        } catch let error as SteamAPIError {
            lastError = error.errorDescription
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
                lastPlayed: $0.lastPlayed
            )
        }
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

    // MARK: - Steam Web API plumbing

    private func resolveSteamID(input: String, apiKey: String) async throws -> String {
        let parsed = SteamLibraryStore.parseProfileInput(input)
        switch parsed {
        case .steamID64(let id):
            return id

        case .vanity(let vanity):
            guard let encoded = vanity.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: "https://api.steampowered.com/ISteamUser/ResolveVanityURL/v1/?key=\(apiKey)&vanityurl=\(encoded)") else {
                throw SteamAPIError.invalidProfileInput(input)
            }
            let payload: ResolveVanityResponse = try await get(url)
            guard payload.response.success == 1, let id = payload.response.steamid, !id.isEmpty else {
                throw SteamAPIError.vanityNotResolved(vanity)
            }
            return id

        case .empty:
            throw SteamAPIError.invalidProfileInput(input)
        }
    }

    private func fetchPlayerSummary(steamID: String, apiKey: String) async throws -> PlayerSummary {
        guard let url = URL(string: "https://api.steampowered.com/ISteamUser/GetPlayerSummaries/v2/?key=\(apiKey)&steamids=\(steamID)") else {
            throw SteamAPIError.invalidProfileInput(steamID)
        }
        let payload: PlayerSummariesResponse = try await get(url)
        guard let summary = payload.response.players.first else {
            throw SteamAPIError.playerNotFound(steamID)
        }
        return summary
    }

    private func fetchOwnedGames(steamID: String, apiKey: String) async throws -> [SteamLibraryGame] {
        guard let url = URL(string: "https://api.steampowered.com/IPlayerService/GetOwnedGames/v1/?key=\(apiKey)&steamid=\(steamID)&include_appinfo=1&include_played_free_games=1&format=json") else {
            throw SteamAPIError.invalidProfileInput(steamID)
        }
        let payload: GetOwnedGamesResponse = try await get(url)
        let owned = payload.response.games ?? []
        // game_count of 0 with a present `games: []` is a valid empty library.
        // game_count nil + games nil suggests profile privacy is blocking the response.
        if owned.isEmpty && payload.response.game_count == nil {
            throw SteamAPIError.libraryHidden
        }
        return owned
            .map { game in
                SteamLibraryGame(
                    appID: game.appid,
                    name: game.name?.isEmpty == false ? game.name! : "App \(game.appid)",
                    headerImageURL: nil,
                    iconURL: game.img_icon_url.map { "https://media.steampowered.com/steamcommunity/public/images/apps/\(game.appid)/\($0).jpg" },
                    sizeOnDiskBytes: nil,
                    lastPlayed: game.rtime_last_played.flatMap { $0 > 0 ? Date(timeIntervalSince1970: TimeInterval($0)) : nil }
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SteamAPIError.networkFailure("No HTTP response")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw SteamAPIError.invalidAPIKey
        }
        guard 200..<300 ~= http.statusCode else {
            throw SteamAPIError.networkFailure("HTTP \(http.statusCode)")
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw SteamAPIError.decoding(error.localizedDescription)
        }
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

    // MARK: - Profile input parsing

    enum ProfileInput {
        case steamID64(String)
        case vanity(String)
        case empty
    }

    static func parseProfileInput(_ input: String) -> ProfileInput {
        let trimmed = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty else { return .empty }

        // Bare 17-digit SteamID64.
        if trimmed.count == 17, trimmed.allSatisfy(\.isNumber) {
            return .steamID64(trimmed)
        }
        // URL like https://steamcommunity.com/profiles/76561198000000000
        if let range = trimmed.range(of: "/profiles/") {
            let after = String(trimmed[range.upperBound...])
            let id = String(after.split(separator: "/", maxSplits: 1).first ?? Substring(after))
            if id.count == 17, id.allSatisfy(\.isNumber) {
                return .steamID64(id)
            }
        }
        // URL like https://steamcommunity.com/id/username
        if let range = trimmed.range(of: "/id/") {
            let after = String(trimmed[range.upperBound...])
            let vanity = String(after.split(separator: "/", maxSplits: 1).first ?? Substring(after))
            if !vanity.isEmpty {
                return .vanity(vanity)
            }
        }
        // Otherwise treat the entire thing as a vanity name.
        return .vanity(trimmed)
    }
}

// MARK: - Web API response shapes

private struct ResolveVanityResponse: Decodable {
    let response: Result
    struct Result: Decodable {
        let steamid: String?
        let success: Int
    }
}

private struct PlayerSummariesResponse: Decodable {
    let response: Result
    struct Result: Decodable {
        let players: [PlayerSummary]
    }
}

struct PlayerSummary: Decodable {
    let steamid: String
    let personaname: String
    let avatarfull: String?
}

private struct GetOwnedGamesResponse: Decodable {
    let response: Result
    struct Result: Decodable {
        let game_count: Int?
        let games: [OwnedGame]?
    }
}

private struct OwnedGame: Decodable {
    let appid: Int
    let name: String?
    let img_icon_url: String?
    let rtime_last_played: Int?
}

// MARK: - Errors

enum SteamAPIError: LocalizedError {
    case invalidProfileInput(String)
    case vanityNotResolved(String)
    case playerNotFound(String)
    case libraryHidden
    case invalidAPIKey
    case networkFailure(String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .invalidProfileInput(let s):
            return "Could not interpret '\(s)' as a Steam profile. Paste your profile URL or your 17-digit SteamID64."
        case .vanityNotResolved(let v):
            return "Steam couldn't find a profile for '\(v)'. Double-check your vanity / custom URL."
        case .playerNotFound(let id):
            return "Steam returned no player for \(id). The SteamID might be wrong."
        case .libraryHidden:
            return "Your game library is private. Set your profile + game details to Public in Steam privacy settings, or check that your Web API key belongs to this account."
        case .invalidAPIKey:
            return "Steam rejected the Web API key (HTTP 401/403). Get a fresh one at https://steamcommunity.com/dev/apikey"
        case .networkFailure(let detail):
            return "Network error talking to Steam: \(detail)"
        case .decoding(let detail):
            return "Could not parse Steam's response: \(detail)"
        }
    }
}
