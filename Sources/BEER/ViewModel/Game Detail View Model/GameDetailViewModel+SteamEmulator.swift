import Foundation

extension GameDetailViewModel {
    /// Changes whenever the cached probe needs redoing: a different bottle, or
    /// an Apply/Restore/DLC write bumping the tick.
    var patchStatusProbeID: String {
        "\(installedBottle?.id.uuidString ?? "none")-\(patchProbeTick)"
    }

    func refreshPatchStatus() async {
        guard let bottle = installedBottle, !game.effectiveIsNonSteam else {
            cachedPatchStatus = nil
            return
        }
        // Off the main actor: this walks the game's entire install tree.
        let probed = await Task.detached { [dir = bottle.resolvedInstallDirectory] in
            PatchStatus.probe(at: dir)
        }.value
        cachedPatchStatus = probed
    }

    /// Real achievement definitions for `appID`. Always best-effort: a
    /// patch/install must succeed even when Steam can't be reached to seed
    /// achievements, since games work fine under the emulator either way —
    /// but `note` says exactly what happened, so a silent empty result isn't
    /// indistinguishable from "this game has no Steam achievements".
    func fetchAchievementSchema(appID: Int) async -> AchievementFetchOutcome {
        guard let account = cloudAuth.account, !cloudAuth.sessionExpired else {
            return AchievementFetchOutcome(achievements: [], note: "Achievements not seeded (not signed in to Steam Cloud).")
        }
        do {
            let schema = try await CloudSyncClient().achievementSchema(
                appID: appID, steamID64: account.steamID64,
                account: account.accountName, refreshToken: account.refreshToken
            )
            if schema.achievements.isEmpty {
                return AchievementFetchOutcome(achievements: [], note: "Steam reports no achievements for this game.")
            }
            return AchievementFetchOutcome(achievements: schema.achievements, note: "Seeded \(schema.achievements.count) achievement\(schema.achievements.count == 1 ? "" : "s") from Steam.")
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return AchievementFetchOutcome(achievements: [], note: "Achievements not seeded: \(msg)")
        }
    }

    /// Manually mark the next not-yet-earned achievement "earned" in the
    /// local gbe_fork save file — a real, user-triggered click, not a
    /// background write. Exercises the exact same watcher/toast/Steam-sync
    /// pipeline a real in-game unlock would, so the toast UX can be tuned
    /// and the live sync path re-tested on demand without needing to
    /// actually complete an achievement's real condition in-game.
    func triggerTestAchievementUnlock(for bottle: Bottle) {
        guard let installDir = bottle.resolvedInstallDirectory else {
            patchStatusMessage = "Could not locate the game's install directory."
            patchStatusIsError = true
            return
        }
        let schema = GoldbergApplicator.readAchievementsSchema(installDir: installDir)
        guard !schema.isEmpty else {
            patchStatusMessage = "No local achievement schema yet — click Apply first."
            patchStatusIsError = true
            return
        }

        let saveURL = AchievementWatcher.saveStateFile(bottle: bottle, appID: game.appID)
        var earned = AchievementWatcher.parseEarned(at: saveURL)
        guard let next = schema.first(where: { earned[$0.name] == nil }) else {
            patchStatusMessage = "Every local achievement is already marked earned — restore/clear the save file to test again."
            patchStatusIsError = false
            return
        }

        earned[next.name] = Int(Date().timeIntervalSince1970)
        let entries = earned.map { ["name": $0.key, "earned": true, "earned_time": $0.value] as [String: Any] }
        do {
            try FileManager.default.createDirectory(at: saveURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: entries, options: .prettyPrinted)
            try data.write(to: saveURL, options: .atomic)
            patchStatusMessage = "Test-unlocked \"\(next.displayName)\" locally. If the game is running, watch for the toast (~5s)."
            patchStatusIsError = false
        } catch {
            patchStatusMessage = "Couldn't write test unlock: \(error.localizedDescription)"
            patchStatusIsError = true
        }
    }

    /// Clears the LOCAL test-unlock state only, so "Test: unlock next
    /// achievement" has something left to unlock again. Does not touch the
    /// real Steam account — an achievement genuinely unlocked there stays
    /// unlocked; this only forgets what BEER has already marked earned in
    /// the local gbe_fork save file, for repeat local/toast/sync testing.
    func resetLocalTestAchievements(for bottle: Bottle) {
        let saveURL = AchievementWatcher.saveStateFile(bottle: bottle, appID: game.appID)
        try? FileManager.default.removeItem(at: saveURL)
        patchStatusMessage = "Cleared local test-achievement state — click \"Test: unlock next achievement\" to start over. Your real Steam unlocks are untouched."
        patchStatusIsError = false
    }

    func applyGoldbergPatch(to bottle: Bottle) {
        guard let installDir = bottle.resolvedInstallDirectory else {
            patchStatusMessage = "Could not locate the game's install directory."
            patchStatusIsError = true
            return
        }
        isPatching = true
        patchStatusMessage = nil
        Task { [self] in
            defer { isPatching = false }
            if !goldberg.isInstalled {
                await goldberg.install()
            }
            guard goldberg.isInstalled else {
                patchStatusMessage = goldberg.lastError ?? "Could not install the Steam emulator."
                patchStatusIsError = true
                return
            }
            do {
                // Best-effort: a schema fetch failure must not block getting
                // the emulator itself patched in — the game still runs fine
                // without achievement support, it just won't unlock any.
                let achievementFetch = await fetchAchievementSchema(appID: game.appID)
                let report = try GoldbergApplicator.apply(
                    installDir: installDir,
                    appID: game.appID,
                    account: cloudAuth.account?.accountName,
                    steamID64: cloudAuth.account?.steamID64,
                    // Re-declare the enabled DLC; a bare reapply would
                    // otherwise drop the [app::dlcs] block and the game would
                    // stop seeing DLC it already has on disk.
                    dlc: bottles.live(bottle).effectiveInstalledDLC,
                    achievements: achievementFetch.achievements,
                    using: goldberg
                )
                // Make sure the bottle has the install dir recorded for future ops.
                if bottle.gameInstallDirectory == nil {
                    var updated = bottle
                    updated.gameInstallDirectory = installDir.path
                    await bottles.update(updated)
                }
                let total = report.patched.count + report.alreadyPatched
                patchStatusMessage = "Steam emulator applied to \(total) DLL\(total == 1 ? "" : "s"). \(achievementFetch.note)"
                patchStatusIsError = false
            } catch {
                patchStatusMessage = error.localizedDescription
                patchStatusIsError = true
            }
            patchProbeTick &+= 1
        }
    }

    func restoreOriginalDLLs(for bottle: Bottle) {
        guard let installDir = bottle.resolvedInstallDirectory else {
            patchStatusMessage = "Could not locate the game's install directory."
            patchStatusIsError = true
            return
        }
        do {
            let n = try GoldbergApplicator.restore(installDir: installDir)
            patchStatusMessage = n > 0
                ? "Restored \(n) original DLL\(n == 1 ? "" : "s")."
                : "No backed-up originals to restore."
            patchStatusIsError = false
        } catch {
            patchStatusMessage = error.localizedDescription
            patchStatusIsError = true
        }
        patchProbeTick &+= 1
    }
}
