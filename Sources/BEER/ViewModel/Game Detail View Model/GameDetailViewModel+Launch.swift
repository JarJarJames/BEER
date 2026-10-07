import Foundation

extension GameDetailViewModel {
    func launch(_ bottle: Bottle) {
        guard let exe = bottle.gameLaunchExecutable else { return }
        Task { [self] in
            // Ensure the selected graphics translator (DXVK/DXMT) is downloaded
            // and its DLLs are in the prefix before launch. No-op for D3DMetal /
            // WineD3D / automatic.
            let backend = bottle.effectiveGraphicsBackend
            if GraphicsTranslator.from(backend) != nil {
                do {
                    try await graphicsTranslator.apply(backend, to: bottle)
                } catch {
                    cloudSyncIsError = true
                    cloudSyncMessage = "Couldn't set up \(backend.label): \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
                    return
                }
            }
            // A non-Steam game has no cloud, presence, or achievements to sync.
            guard !game.effectiveIsNonSteam else {
                await bottles.launchGameExecutable(
                    bottle,
                    executable: exe,
                    arguments: bottle.effectiveGameLaunchArguments
                )
                return
            }

            // Auto cloud sync: pull the latest saves down before play, and push
            // whatever changed back up after the game exits. Best-effort — a
            // sync hiccup must never block launching the game. Backups are taken
            // inside the engine before anything is overwritten.
            // Only auto-sync if the session is actually usable. If it's already
            // flagged expired, skip silently and let the Cloud row's Reconnect
            // prompt handle it — don't nag mid-launch.
            let cloudUsable = cloudAuth.account != nil && !cloudAuth.sessionExpired
            if cloudUsable {
                cloudSyncMessage = nil
                do {
                    let r = try await cloudSync.pull(bottle: bottle, appID: game.appID, auth: cloudAuth)
                    cloudSyncIsError = !r.failures.isEmpty
                    cloudSyncMessage = "Pulled \(r.downloaded) save\(r.downloaded == 1 ? "" : "s") before launch."
                } catch CloudSyncClientError.authExpired {
                    cloudAuth.sessionExpired = true
                    cloudSyncIsError = true
                    cloudSyncMessage = "Steam sign-in expired — launching anyway. Reconnect from the Steam Cloud row to sync."
                } catch {
                    cloudSyncIsError = true
                    cloudSyncMessage = "Pre-launch cloud pull failed: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription). Launching anyway."
                }
            }

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
            if cloudUsable, let account = cloudAuth.account,
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

            await bottles.launchGameExecutable(
                bottle,
                executable: exe,
                arguments: bottle.effectiveGameLaunchArguments
            )

            // `launchGameExecutable` returns once the whole Wine session is
            // idle, so by here play is genuinely over. Stopping hands back the
            // new total, re-read on the session we already hold.
            if let minutes = await presence.stopPlaying(appID: game.appID) {
                library.recordPlaytime(appID: game.appID, minutes: minutes)
            }

            // One last check for anything unlocked in the final moments of
            // play, then stop watching — the game isn't running anymore.
            await achievementWatcher?.finalCheck()
            achievementWatcher?.stop()

            // Re-check: the token may have expired during the pull above.
            let savesAfter = cloudSync.localSaveFingerprint(appID: game.appID)
            let savesUnchanged = savesBefore != nil && savesAfter == savesBefore

            if savesUnchanged {
                cloudSyncIsError = false
                cloudSyncMessage = "No save changes to upload."
            } else if cloudAuth.account != nil && !cloudAuth.sessionExpired {
                do {
                    let r = try await cloudSync.push(bottle: bottle, appID: game.appID, auth: cloudAuth)
                    cloudSyncIsError = !r.failures.isEmpty
                    cloudSyncMessage = "Pushed \(r.uploaded) save\(r.uploaded == 1 ? "" : "s") to cloud after play."
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
}
