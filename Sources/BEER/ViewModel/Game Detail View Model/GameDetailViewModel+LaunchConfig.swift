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

    /// What to run for `exe`: the exe itself, or for a Steam game that needs
    /// it, the emulator's steamclient loader (see `SteamClientLoaderPlan`).
    func steamClientLoaderExecutable(for exe: String, in bottle: Bottle) throws -> String {
        let exeURL = URL(fileURLWithPath: exe)
        guard !game.effectiveIsNonSteam,
              let installDir = bottle.resolvedInstallDirectory,
              let plan = SteamClientLoaderPlan.make(
                  executable: exeURL, installDir: installDir,
                  mode: bottle.effectiveSteamClientLoaderMode,
                  injectsOverlay: bottle.effectiveSteamClientLoaderInjectsOverlay,
                  staysOpen: bottle.effectiveSteamClientLoaderStaysOpen
              ) else { return exe }
        guard let loaderSource = goldberg.coldClientDirectory else {
            throw GoldbergPatchError.coldClientMissing("steamclient_loader")
        }
        let account = cloudAuth.account
        return try ColdClientApplicator.prepare(
            executable: exeURL, installDir: installDir, appID: game.appID, plan: plan,
            loaderSource: loaderSource, oldSteamLibrary: goldberg.oldSteamLibraryURL,
            writeSettings: { [appID = game.appID] folder in
                try GoldbergApplicator.writeSteamSettings(
                    in: folder, appID: appID,
                    account: account?.accountName, steamID64: account?.steamID64,
                    dlc: bottle.effectiveInstalledDLC
                )
            }
        ).path
    }
}
