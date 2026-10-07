import Foundation

extension CloudSyncClient {
    /// Fetch the signed-in account's owned games via the authenticated client
    /// session (IPlayerService.GetOwnedGames over the Steam network) — no Web
    /// API key required.
    func ownedGames(steamID64: String, account: String, refreshToken: String) async throws -> [OwnedGameInfo] {
        let raw = try await runOnceArray(
            "games", args: ["ownedgames", "--steamid", steamID64],
            account: account, refreshToken: refreshToken
        )
        return raw.compactMap { g in
            guard let appid = (g["appid"] as? NSNumber)?.intValue else { return nil }
            let name = (g["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "App \(appid)"
            let icon = (g["img_icon_url"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let rt = (g["rtime_last_played"] as? NSNumber)?.doubleValue ?? 0
            let minutes = (g["playtime_forever"] as? NSNumber)?.intValue ?? 0
            return OwnedGameInfo(
                appID: appid,
                name: name,
                iconURL: icon.map { "https://media.steampowered.com/steamcommunity/public/images/apps/\(appid)/\($0).jpg" },
                lastPlayed: rt > 0 ? Date(timeIntervalSince1970: rt) : nil,
                playtimeMinutes: minutes > 0 ? minutes : nil
            )
        }
    }

    /// Every DLC Steam lists for `appID`, each flagged with whether this
    /// account owns it. Steam has no owned-DLC endpoint, so the helper derives
    /// ownership from the account's package licences (see `Dlc` in Program.cs).
    func dlc(appID: Int, account: String, refreshToken: String) async throws -> [DLCInfo] {
        let raw = try await runOnceArray(
            "dlc", args: ["dlc", "--appid", String(appID)],
            account: account, refreshToken: refreshToken
        )
        return raw.compactMap { d in
            guard let appid = (d["appid"] as? NSNumber)?.intValue else { return nil }
            return DLCInfo(
                appID: appid,
                name: (d["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "DLC \(appid)",
                owned: d["owned"] as? Bool ?? false,
                hasDepots: d["has_depots"] as? Bool ?? false
            )
        }
    }
}
