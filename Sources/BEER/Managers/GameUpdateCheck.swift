import Foundation

/// Asks Steam whether installed games have an update. Only games whose files
/// can be read right now are asked about: one on an unplugged drive keeps
/// what the last check found.
struct GameUpdateCheck {
    var client = CloudSyncClient()

    /// One installed game to ask about. `leftOutDepots` are the DLC depots the
    /// player left out of its download: Update won't fetch them, so they can't
    /// make it out of date.
    struct Target: Equatable {
        let appID: Int
        let directory: URL
        var leftOutDepots: [Int] = []
    }

    /// The installed Steam games to check, with their folders. `folder` is nil
    /// for a game whose files can't be reached now.
    static func targets(
        games: [SteamLibraryGame], bottles: [Bottle], folder: (Bottle) -> URL?
    ) -> [Target] {
        games.compactMap { game in
            guard !game.effectiveIsNonSteam,
                  let bottleID = game.installedBottleID,
                  let bottle = bottles.first(where: { $0.id == bottleID }),
                  bottle.gameInstallStatus == .installed,
                  let directory = folder(bottle) else { return nil }
            return Target(appID: game.appID, directory: directory,
                          leftOutDepots: bottle.skippedDLC?.flatMap(\.depotIDs) ?? [])
        }
    }

    /// Each game's status. A game Steam couldn't judge is left out, so it
    /// keeps what it had; a failed check throws, leaving every game as it was.
    func run(targets: [Target], account: SteamCloudAccount) async throws -> [Int: GameUpdateStatus] {
        try await client.updateCheck(
            games: targets, account: account.accountName, refreshToken: account.refreshToken
        ).filter { $0.value != .unknown }
    }
}
