import Foundation

extension GameDetailViewModel {
    /// What Play hands to Wine, Discord and the achievement watcher: the parts
    /// of a launch no test can run. The update prompt, the save pull before
    /// play and the push after stay in the view model. Tests swap in a
    /// session that runs nothing.
    struct GameSession {
        /// The prefix, Steam's launch config, the client loader and the
        /// graphics translator: the bottle as it stands after, and what to run.
        var setUpWine: @MainActor (GameDetailViewModel, Bottle) async throws -> (Bottle, String)
        /// Redistributables, controllers and display mode, just before the game.
        var prepareGame: @MainActor (BottleStore, Bottle) async throws -> Bottle
        /// Runs the game until its Wine session ends. The exit code, or nil if
        /// it never ran.
        var runGame: @MainActor (BottleStore, Bottle, _ executable: String) async -> Int32?
        var showOnDiscord: @MainActor (SteamLibraryGame) -> Void
        var clearFromDiscord: @MainActor (_ appID: Int) -> Void
        /// Starts watching for achievement unlocks, to sync to `account`.
        var watchAchievements: @MainActor (Bottle, _ appID: Int, _ installDir: URL, SteamCloudAccount) -> AchievementWatcher?

        static var live: GameSession {
            GameSession(
                setUpWine: { model, bottle in try await model.setUpWine(for: bottle) },
                prepareGame: { bottles, bottle in try await bottles.prepareGameSession(bottle) },
                runGame: { bottles, bottle, executable in
                    await bottles.runGameSession(
                        bottle, executable: executable, arguments: bottle.effectiveGameLaunchArguments
                    )
                },
                showOnDiscord: { DiscordPresence.shared.beginPlaying($0) },
                clearFromDiscord: { DiscordPresence.shared.endPlaying(appID: $0) },
                watchAchievements: { bottle, appID, installDir, account in
                    let watcher = AchievementWatcher(
                        bottle: bottle, appID: appID, installDir: installDir,
                        steamID64: account.steamID64, account: account.accountName,
                        refreshToken: account.refreshToken,
                        onUnlock: { AchievementToastCenter.shared.post($0) }
                    )
                    watcher.start()
                    return watcher
                }
            )
        }
    }
}
