import Foundation

extension BottleStore {
    func launchPhase(for bottleID: Bottle.ID) -> LaunchPhase? {
        launchPhases[bottleID]
    }

    /// Run a Play click's steps, publishing which one the bottle is on. Ends
    /// with no phase once the game's session is over, or on the error of the
    /// step that failed, so Play never just quietly comes back.
    ///
    /// `activeBottleIDs` only covers each Wine command while it runs; the
    /// phase covers the whole launch, including the steps between commands.
    func runLaunch(_ bottle: Bottle, steps: LaunchSteps) async {
        let id = bottle.id
        launchPhases[id] = .settingUpWine
        do {
            try await steps.setUpWine()
            if let syncSaves = steps.syncSaves {
                launchPhases[id] = .syncingSaves
                guard await syncSaves() else {
                    launchPhases[id] = nil
                    return
                }
            }
            launchPhases[id] = .startingGame(isSlow: false)
            try await steps.prepareGame()
        } catch {
            launchPhases[id] = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            return
        }

        // Watch only while the game itself runs: a redistributable's installer
        // window during `prepareGame` isn't the game.
        let prefix = AppPaths.prefixURL(for: bottle)
        let watch = Task { [weak self] in await self?.watchForGameWindow(id, prefix: prefix) }
        let exitCode = await steps.runGame()
        watch.cancel()
        await watch.value

        launchPhases[id] = Self.phaseAfterSession(exitCode: exitCode, sawWindow: launchPhases[id] == .playing)
        await steps.afterPlay()
    }

    /// No phase for a session that ran, or that showed a window and ended
    /// however it ended. A failure for a game that never ran, or that quit
    /// with an error before any window, which is what a crash on start looks
    /// like. A clean exit with no window stays quiet: a launcher can exit 0
    /// having started the game somewhere BEER can't see.
    static func phaseAfterSession(exitCode: Int32?, sawWindow: Bool) -> LaunchPhase? {
        guard let exitCode else { return .failed(LaunchError.gameDidNotStart.errorDescription ?? "") }
        if !sawWindow, exitCode != 0 {
            return .failed(LaunchError.closedBeforeWindow(exitCode: exitCode).errorDescription ?? "")
        }
        return nil
    }

    /// Until cancelled: flips the phase to `.playing` once the bottle has a
    /// window, and marks the start slow if that takes too long.
    func watchForGameWindow(_ bottleID: Bottle.ID, prefix: URL) async {
        let watch = gameWindowWatch
        let clock = ContinuousClock()
        let start = clock.now
        while !Task.isCancelled {
            if watch.isShown(prefix) {
                launchPhases[bottleID] = .playing
                return
            }
            if clock.now - start >= watch.slowAfter, launchPhases[bottleID] == .startingGame(isSlow: false) {
                launchPhases[bottleID] = .startingGame(isSlow: true)
            }
            // Throws only when cancelled, which the loop condition handles.
            try? await Task.sleep(for: watch.pollInterval)
        }
    }
}
