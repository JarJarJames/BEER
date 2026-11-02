import AppKit
import Foundation

extension GameDetailViewModel {
    /// The game is running or a sync is under way: saves are in use, so
    /// they can't be restored.
    func savesAreBusy(_ bottle: Bottle) -> Bool {
        cloudSync.isSyncing || bottles.activeBottleIDs.contains(bottle.id)
    }

    func showSaveBackups() {
        saveBackupsError = nil
        reloadSaveBackups()
        isShowingSaveBackups = true
    }

    func reloadSaveBackups() {
        saveBackups = cloudSync.saveBackups(appID: game.appID)
        refreshPendingRestore()
    }

    func refreshPendingRestore() {
        pendingRestore = cloudSync.pendingRestore(appID: game.appID)
    }

    func revealBackup(_ snapshot: CloudSaveSnapshot) {
        NSWorkspace.shared.activateFileViewerSelecting([snapshot.url])
    }

    /// Work out what restoring `snapshot` would do, then ask.
    func prepareRestore(_ snapshot: CloudSaveSnapshot, bottle: Bottle) {
        saveBackupsError = nil
        Task { [self] in
            do {
                let userHome = try cloudSync.resolveWineUserHome(for: bottle)
                let installDir = bottle.gameInstallDirectory.map { URL(fileURLWithPath: $0) }
                restorePlanToConfirm = try await Task.detached {
                    try CloudSyncEngine.restorePlan(for: snapshot, userHome: userHome, installDir: installDir)
                }.value
            } catch {
                saveBackupsError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    func restore(_ plan: SaveRestorePlan, bottle: Bottle) {
        restorePlanToConfirm = nil
        guard !savesAreBusy(bottle) else {
            saveBackupsError = SaveRestoreStrings.busy
            return
        }
        do {
            try cloudSync.restore(plan, appID: game.appID)
            cloudSyncIsError = false
            cloudSyncMessage = SaveRestoreStrings.restored(plan.snapshot.date)
            isShowingSaveBackups = false
        } catch {
            saveBackupsError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        reloadSaveBackups()
    }

    // MARK: - Settling a restore with Steam Cloud

    /// The player picked a side in the conflict prompt. Settle it, then carry
    /// on with what they were doing when the sync stopped.
    func resolveRestoreConflict(_ prompt: RestoreConflictPrompt, keepRestored: Bool) {
        restoreConflictPrompt = nil
        Task { [self] in
            cloudSyncMessage = nil
            if keepRestored {
                do {
                    let report = try await cloudSync.keepRestoredSaves(bottle: prompt.bottle, appID: game.appID, auth: cloudAuth)
                    refreshPendingRestore()
                    cloudSyncIsError = !report.failures.isEmpty
                    cloudSyncMessage = SaveRestoreStrings.keptRestored(report)
                    // A partial upload leaves the restore pending; running the
                    // sync again would only stop on it once more.
                    guard report.failures.isEmpty else { return }
                } catch {
                    refreshPendingRestore()
                    showCloudError(error)
                    return
                }
            } else {
                cloudSync.useSteamSavesOverRestore(appID: game.appID)
                refreshPendingRestore()
            }
            switch prompt.retry {
            case .sync(let pull, let push): syncSaves(for: prompt.bottle, pull: pull, push: push)
            case .launch: launch(prompt.bottle)
            }
        }
    }

    /// Show a cloud failure in the Steam Cloud row. An expired sign-in also
    /// opens the reconnect sheet, since the player asked for this.
    func showCloudError(_ error: Error) {
        cloudSyncIsError = true
        if case CloudSyncClientError.authExpired = error {
            cloudAuth.sessionExpired = true
            cloudSyncMessage = "Steam sign-in expired — reconnect to finish syncing."
            isShowingCloudConnect = true
        } else {
            cloudSyncMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
