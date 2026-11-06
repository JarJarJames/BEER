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
    /// it, the emulator's steamclient loader (see `SteamClientLoaderPlan`), or
    /// for a launcher that starts such a game, BEER's launcher that sends the
    /// game's start through the loader.
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
            func prepare(_ executable: URL, _ plan: SteamClientLoaderPlan) throws -> URL {
                guard let loaderSource else {
                    throw GoldbergPatchError.coldClientMissing("steamclient_loader")
                }
                return try ColdClientApplicator.prepare(
                    executable: executable, installDir: installDir, appID: appID, plan: plan,
                    loaderSource: loaderSource, oldSteamLibrary: oldSteamLibrary,
                    writeSettings: { folder in
                        try GoldbergApplicator.writeSteamSettings(
                            in: folder, appID: appID, account: accountName, steamID64: steamID64, dlc: dlc
                        )
                    }
                )
            }
            if let plan = SteamClientLoaderPlan.make(
                executable: exeURL, installDir: installDir,
                mode: mode, injectsOverlay: injectsOverlay, staysOpen: staysOpen
            ) {
                return try prepare(exeURL, plan).path
            }

            // A launcher that starts the game's wrapped exe itself: send that
            // start through the loader (see ColdClientApplicator+Launcher).
            // The hook is 64-bit, so it only goes into a 64-bit launcher.
            guard mode != .off,
                  PortableExecutable(contentsOf: exeURL)?.is64Bit == true,
                  let game = ColdClientApplicator.wrappedGame(beside: exeURL),
                  let gamePlan = SteamClientLoaderPlan.make(
                      executable: game, installDir: installDir,
                      mode: mode, injectsOverlay: injectsOverlay, staysOpen: staysOpen
                  ) else { return exe }
            guard let helpers = WindowsHelpers.directory else {
                Log.install.error("\(exeURL.lastPathComponent, privacy: .public) starts a SteamStub-wrapped game, but BEER's Windows helpers aren't installed (run scripts/build_windows_helpers.sh).")
                return exe
            }
            return try ColdClientApplicator.prepareLauncher(
                exeURL, game: game, gameLoader: prepare(game, gamePlan), installDir: installDir, helpers: helpers
            ).path
        }.value
    }
}
