import Foundation

extension GameDetailViewModel {
    /// The Windows launch options Steam lists for this game, best first. Throws
    /// when Steam can't be asked, so callers can fall back to a guess and try
    /// again later rather than treating "unknown" as "nothing listed".
    func steamLaunchEntries() async throws -> [CloudSyncClient.LaunchEntry] {
        guard let account = cloudAuth.account, !cloudAuth.sessionExpired else {
            throw CloudSyncClientError.authExpired
        }
        return try await CloudSyncClient().launchEntries(
            appID: game.appID, account: account.accountName, refreshToken: account.refreshToken
        )
    }

    /// Installs from builds that only guessed the .exe are checked against
    /// Steam once, on their next launch. Best-effort: if Steam can't be asked
    /// the guess stands and the check runs again next time.
    func adoptSteamLaunchConfigIfNeeded(_ bottle: Bottle) async {
        guard bottle.steamLaunchConfigChecked != true,
              let installDir = bottle.resolvedInstallDirectory,
              let entries = try? await steamLaunchEntries() else { return }
        await bottles.recordSteamLaunchConfig(
            bottle, target: SteamLaunchResolver.resolve(entries, in: installDir)
        )
    }
}
