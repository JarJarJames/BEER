import Foundation

extension GameDetailViewModel {
    /// Steam has a newer build, so Play asks whether to update first.
    var offersUpdateBeforePlay: Bool {
        !game.effectiveIsNonSteam && game.effectiveUpdateAvailable
    }

    /// The Play prompt's Update First: the same download as Reinstall / Validate,
    /// which only fetches what changed.
    func updateInsteadOfPlaying() {
        dialog = nil
        startInstallOrLogin()
    }

    func playWithoutUpdating() {
        guard case .updateBeforePlay(let bottle) = dialog else { return }
        dialog = nil
        launch(bottle, skippingUpdatePrompt: true)
    }

    /// A non-Steam game has no cloud to pull from, and an expired or missing
    /// session is left for the Cloud row's Reconnect prompt rather than
    /// nagging mid-launch.
    nonisolated static func pullsSavesBeforePlay(isNonSteam: Bool, isSteamConnected: Bool) -> Bool {
        !isNonSteam && isSteamConnected
    }

    /// `skippingUpdatePrompt` is for a launch the player already chose to make
    /// on an out-of-date game.
    func launch(_ installedBottle: Bottle, skippingUpdatePrompt: Bool = false) {
        guard installedBottle.gameLaunchExecutable != nil, !mover.isMoving(installedBottle.id) else { return }
        // A shortcut can ask while a launch is already under way.
        guard bottles.launchPhase(for: installedBottle.id)?.isInProgress != true else { return }
        // A shortcut can ask while the drive is unplugged; the page says why.
        switch bottles.installLocation(of: installedBottle) {
        case .available:
            break
        case .driveMissing(let name):
            cloudSyncIsError = true
            cloudSyncMessage = InstallDriveStrings.driveMissingDetail(name)
            return
        case .missing:
            cloudSyncIsError = true
            cloudSyncMessage = InstallDriveStrings.filesMissing
            return
        }
        // Before the save pull: saves from a newer build may not load in this one.
        if !skippingUpdatePrompt, offersUpdateBeforePlay {
            dialog = .updateBeforePlay(installedBottle)
            return
        }
        // Before the save pull and Discord, which would be for nothing.
        guard bottles.requireRosetta() else { return }

        let pullsSaves = Self.pullsSavesBeforePlay(isNonSteam: game.effectiveIsNonSteam,
                                                   isSteamConnected: isSteamConnected)
        let steps = launchSteps(for: installedBottle, pullsSaves: pullsSaves)
        Task { [self] in
            await bottles.runLaunch(installedBottle, steps: steps)
        }
    }

    /// What one launch's steps hand on to the next.
    @MainActor
    private final class LaunchState {
        var bottle: Bottle
        var exe = ""
        var tracking: PlayTracking?

        init(bottle: Bottle) { self.bottle = bottle }
    }

    private func launchSteps(for installedBottle: Bottle, pullsSaves: Bool) -> BottleStore.LaunchSteps {
        let state = LaunchState(bottle: installedBottle)
        var syncSaves: (@MainActor () async -> Bool)?
        if pullsSaves {
            syncSaves = { [self] in await pullSavesBeforePlay(state.bottle, retrying: installedBottle) }
        }
        return BottleStore.LaunchSteps(
            setUpWine: { [self] in
                (state.bottle, state.exe) = try await setUpWine(for: installedBottle)
            },
            syncSaves: syncSaves,
            prepareGame: { [self] in
                state.bottle = try await bottles.prepareGameSession(state.bottle)
            },
            runGame: { [self] in
                state.tracking = beginPlay(state.bottle, watchesAchievements: pullsSaves)
                return await bottles.runGameSession(
                    state.bottle, executable: state.exe, arguments: state.bottle.effectiveGameLaunchArguments
                )
            },
            afterPlay: { [self] in
                await endPlay(state.bottle, tracking: state.tracking)
            }
        )
    }

    /// The prefix, Steam's launch config, the client loader, and the selected
    /// graphics translator. The bottle as it stands after, and what to run.
    private func setUpWine(for installedBottle: Bottle) async throws -> (Bottle, String) {
        // Before the save pull, which needs the prefix's user folder.
        guard await bottles.initializeIfNeeded(installedBottle) else { throw LaunchError.wineSetupFailed }
        if !game.effectiveIsNonSteam {
            await adoptSteamLaunchConfigIfNeeded(installedBottle)
        }
        let bottle = bottles.live(installedBottle)
        guard let gameExe = bottle.gameLaunchExecutable else { throw LaunchError.noExecutable }
        let exe: String
        do {
            exe = try await steamClientLoaderExecutable(for: gameExe, in: bottle)
        } catch {
            throw LaunchError.clientLoader((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }

        // Ensure the selected graphics translator (DXVK/DXMT) is downloaded
        // and its DLLs are in the prefix before launch. No-op for D3DMetal /
        // WineD3D / automatic.
        let backend = bottle.effectiveGraphicsBackend
        if GraphicsTranslator.from(backend) != nil {
            do {
                try await graphicsTranslator.apply(backend, to: bottle)
            } catch {
                throw LaunchError.graphicsTranslator(
                    name: backend.label,
                    detail: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                )
            }
        }
        return (bottle, exe)
    }

    /// Auto cloud sync: pull the latest saves down before play. Best-effort — a
    /// sync hiccup must never block launching the game. Backups are taken
    /// inside the engine before anything is overwritten. False when the
    /// player has to choose between two sets of saves first.
    private func pullSavesBeforePlay(_ bottle: Bottle, retrying installedBottle: Bottle) async -> Bool {
        cloudSyncMessage = nil
        do {
            let r = try await cloudSync.pull(bottle: bottle, appID: game.appID, auth: cloudAuth)
            cloudSyncIsError = !r.failures.isEmpty
            cloudSyncMessage = "Pulled \(r.downloaded) save\(r.downloaded == 1 ? "" : "s") before launch."
        } catch CloudSyncError.restoreConflict(let conflict) {
            // Playing on either set of saves before choosing would
            // make the choice for the player. Ask, then launch.
            sheet = .restoreConflict(RestoreConflictPrompt(conflict: conflict, bottle: installedBottle, retry: .launch))
            return false
        } catch CloudSyncClientError.authExpired {
            cloudAuth.sessionExpired = true
            cloudSyncIsError = true
            cloudSyncMessage = "Steam sign-in expired — launching anyway. Reconnect from the Steam Cloud row to sync."
        } catch {
            cloudSyncIsError = true
            cloudSyncMessage = "Pre-launch cloud pull failed: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription). Launching anyway."
        }
        return true
    }

    /// What `beginPlay` started, for `endPlay` to finish.
    struct PlayTracking {
        let savesBefore: String?
        let achievementWatcher: AchievementWatcher?
    }

    /// Announce the game and start watching it, just before it runs. A
    /// non-Steam game has no cloud, presence, or achievements to sync. It
    /// still shows on Discord, which doesn't need Steam.
    ///
    /// `watchesAchievements` is whether Steam was connected at the click, so a
    /// session that expired during the pull still watches and queues unlocks.
    private func beginPlay(_ bottle: Bottle, watchesAchievements: Bool) -> PlayTracking? {
        DiscordPresence.shared.beginPlaying(game)
        guard !game.effectiveIsNonSteam else { return nil }

        // Signature of the saves as they stand going in. If the game
        // writes nothing — which is what a crash on startup looks like —
        // the post-play push has nothing to do, and skipping it skips a
        // Steam logon. A crash-loop otherwise burns logons until Steam
        // starts refusing them and the whole integration falls over.
        let savesBefore = cloudSync.localSaveFingerprint(appID: game.appID)

        // Announce the game on the app's live Steam session. One session
        // is shared for everything — status, presence, play time — because
        // Steam resolves games-played last-writer-wins across an account's
        // logons, so a second session opened just for this would fight it.
        presence.beginPlaying(appID: game.appID)

        // Watch for local achievement unlocks (from the Goldberg/gbe_fork
        // shim) while the game runs, and sync any to the real account.
        // Best-effort and non-fatal: no install dir or no signed-in
        // account just means no watcher, not a blocked launch.
        var achievementWatcher: AchievementWatcher?
        if watchesAchievements, let account = cloudAuth.account,
           let installDir = bottle.resolvedInstallDirectory {
            let watcher = AchievementWatcher(
                bottle: bottle, appID: game.appID, installDir: installDir,
                steamID64: account.steamID64, account: account.accountName,
                refreshToken: account.refreshToken,
                onUnlock: { AchievementToastCenter.shared.post($0) }
            )
            watcher.start()
            achievementWatcher = watcher
        }
        return PlayTracking(savesBefore: savesBefore, achievementWatcher: achievementWatcher)
    }

    /// `runGameSession` returns once the whole Wine session is idle, so by
    /// here play is genuinely over.
    private func endPlay(_ bottle: Bottle, tracking: PlayTracking?) async {
        DiscordPresence.shared.endPlaying(appID: game.appID)
        guard let tracking else { return }

        // Stopping hands back the new total, re-read on the session we
        // already hold.
        if let minutes = await presence.stopPlaying(appID: game.appID) {
            library.recordPlaytime(appID: game.appID, minutes: minutes)
        }

        // One last check for anything unlocked in the final moments of
        // play, then stop watching — the game isn't running anymore.
        await tracking.achievementWatcher?.finalCheck()
        tracking.achievementWatcher?.stop()

        // Re-check: the token may have expired during the pull above.
        let savesAfter = cloudSync.localSaveFingerprint(appID: game.appID)
        let savesUnchanged = tracking.savesBefore != nil && savesAfter == tracking.savesBefore

        if savesUnchanged {
            cloudSyncIsError = false
            cloudSyncMessage = "No save changes to upload."
        } else if cloudAuth.account != nil && !cloudAuth.sessionExpired {
            do {
                let r = try await cloudSync.push(bottle: bottle, appID: game.appID, auth: cloudAuth)
                cloudSyncIsError = !r.failures.isEmpty
                cloudSyncMessage = "Pushed \(r.uploaded) save\(r.uploaded == 1 ? "" : "s") to cloud after play."
            } catch CloudSyncError.restoreConflict {
                cloudSyncIsError = true
                cloudSyncMessage = SaveRestoreStrings.postPlayBlocked
            } catch CloudSyncClientError.authExpired {
                cloudAuth.sessionExpired = true
                cloudSyncIsError = true
                cloudSyncMessage = "Steam sign-in expired before your saves could upload. Your progress is safe locally and backed up — reconnect, then Push to cloud."
            } catch {
                cloudSyncIsError = true
                cloudSyncMessage = "Post-play cloud push failed: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription). Your saves are safe locally and backed up."
            }
        }
    }
}
