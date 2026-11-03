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
    func steamClientLoaderExecutable(for exe: String, in bottle: Bottle) async throws -> String {
        guard !game.effectiveIsNonSteam, let installDir = bottle.resolvedInstallDirectory else { return exe }
        let mode = bottle.effectiveSteamClientLoaderMode
        let injectsOverlay = bottle.effectiveSteamClientLoaderInjectsOverlay
        let staysOpen = bottle.effectiveSteamClientLoaderStaysOpen
        let loaderSource = goldberg.coldClientDirectory
        let oldSteamLibrary = goldberg.oldSteamLibraryURL
        let appID = game.appID
        let accountName = cloudAuth.account?.accountName
        let steamID64 = cloudAuth.account?.steamID64
        let dlc = bottle.effectiveInstalledDLC

        // Off the main thread: this reads the game's exe and can copy ~44 MB
        // of emulator into the game's folder, which on a USB drive froze the
        // window for seconds.
        return try await Task.detached {
            let exeURL = URL(fileURLWithPath: exe)
            guard let plan = SteamClientLoaderPlan.make(
                executable: exeURL, installDir: installDir,
                mode: mode, injectsOverlay: injectsOverlay, staysOpen: staysOpen
            ) else { return exe }
            guard let loaderSource else {
                throw GoldbergPatchError.coldClientMissing("steamclient_loader")
            }
            return try ColdClientApplicator.prepare(
                executable: exeURL, installDir: installDir, appID: appID, plan: plan,
                loaderSource: loaderSource, oldSteamLibrary: oldSteamLibrary,
                writeSettings: { folder in
                    try GoldbergApplicator.writeSteamSettings(
                        in: folder, appID: appID, account: accountName, steamID64: steamID64, dlc: dlc
                    )
                }
            ).path
        }.value
    }
}
