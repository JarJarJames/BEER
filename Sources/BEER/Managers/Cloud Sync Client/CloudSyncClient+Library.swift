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
    /// ownership from the account's package licences (see `DlcCommand` in Tools/CloudSync/Commands).
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

extension CloudSyncClient {
    /// The Windows launch options Steam lists for `appID`, best first — what
    /// Steam's own Play button would run (see `LaunchConfigPicker` in Tools/CloudSync/Launch).
    func launchEntries(appID: Int, account: String, refreshToken: String) async throws -> [LaunchEntry] {
        try await runOnceArray(
            "launch", args: ["launchinfo", "--appid", String(appID)],
            account: account, refreshToken: refreshToken
        ).compactMap(LaunchEntry.init(json:))
    }
}

extension CloudSyncClient {
    /// Bytes a Windows install of `appIDs` takes on disk together, counting
    /// DLC content the account owns, or nil when Steam lists no size (see
    /// `InstallSize` in Tools/CloudSync/Steam). One Steam logon for the lot.
    func installSize(appIDs: [Int], account: String, refreshToken: String) async throws -> Int64? {
        Self.installBytes(from: try await runOnce(
            args: ["installsize", "--appids", appIDs.map(String.init).joined(separator: ",")],
            account: account, refreshToken: refreshToken
        ))
    }

    static func installBytes(from json: [String: Any]) -> Int64? {
        guard let bytes = (json["bytes"] as? NSNumber)?.int64Value, bytes > 0 else { return nil }
        return bytes
    }
}

extension CloudSyncClient {
    /// Where Steam keeps `appID`'s Windows icon, the multi-size `.ico` Steam
    /// puts on its own shortcuts. Nil when Steam lists none.
    func clientIcon(appID: Int, account: String, refreshToken: String) async throws -> URL? {
        Self.clientIconURL(appID: appID, from: try await runOnce(
            args: ["clienticon", "--appid", String(appID)],
            account: account, refreshToken: refreshToken
        ))
    }

    static func clientIconURL(appID: Int, from json: [String: Any]) -> URL? {
        guard let hash = json["clienticon"] as? String, !hash.isEmpty else { return nil }
        return URL(string: "https://cdn.cloudflare.steamstatic.com/steamcommunity/public/images/apps/\(appID)/\(hash).ico")
    }
}
