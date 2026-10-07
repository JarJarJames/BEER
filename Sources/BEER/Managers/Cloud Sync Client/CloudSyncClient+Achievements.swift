import Foundation

extension CloudSyncClient {
    /// Real achievement schema + current unlock state for `appID`, read
    /// straight from Steam over the client protocol (same one cloud saves
    /// use) — used to seed gbe_fork's local `steam_settings/achievements.json`
    /// with the account's actual unlocks so the emulator doesn't re-fire
    /// "just unlocked" toasts for achievements already earned on the real
    /// profile.
    func achievementSchema(appID: Int, steamID64: String, account: String, refreshToken: String) async throws -> AchievementSchema {
        let obj = try await runOnce(
            args: ["achievements-get", "--appid", String(appID), "--steamid", steamID64],
            account: account, refreshToken: refreshToken
        )
        guard let raw = obj["achievements"] as? [[String: Any]] else {
            throw CloudSyncClientError.badOutput("no achievements array")
        }
        let achievements = raw.compactMap { a -> AchievementInfo? in
            guard let name = a["name"] as? String else { return nil }
            let unlockTime = (a["unlockTime"] as? NSNumber)?.doubleValue
            return AchievementInfo(
                name: name,
                displayName: (a["displayName"] as? String) ?? name,
                description: (a["description"] as? String) ?? "",
                hidden: a["hidden"] as? Bool ?? false,
                icon: a["icon"] as? String,
                iconGray: a["icongray"] as? String,
                unlocked: a["unlocked"] as? Bool ?? false,
                unlockTime: unlockTime.map { Date(timeIntervalSince1970: $0) }
            )
        }
        return AchievementSchema(achievements: achievements)
    }

    /// Push newly-unlocked achievements to the account's REAL Steam profile.
    /// This is the write side of the pair — see `UserStatsHandler` (CloudSync)
    /// for why it's the one part of achievements support that genuinely needs
    /// the user's own live-account verification rather than just compiling.
    func pushAchievementUnlocks(appID: Int, steamID64: String, unlockedNames: [String], account: String, refreshToken: String) async throws -> AchievementSyncResult {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("gn-achievements-\(UUID().uuidString).json")
        try JSONSerialization.data(withJSONObject: unlockedNames).write(to: tmp, options: .atomic)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let obj = try await runOnce(
            args: ["achievements-store", "--appid", String(appID), "--steamid", steamID64, "--unlocks", tmp.path],
            account: account, refreshToken: refreshToken
        )
        return AchievementSyncResult(
            ok: obj["ok"] as? Bool ?? false,
            eresult: obj["eresult"] as? String ?? "Unknown",
            statsOutOfDate: obj["statsOutOfDate"] as? Bool ?? false
        )
    }
}
