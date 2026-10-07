import Foundation

extension GameDetailViewModel {
    /// Pull and/or push saves. `syncSaves(pull:true, push:true)` is the default
    /// two-way sync; the menu offers one-direction variants.
    func syncSaves(for bottle: Bottle, pull: Bool, push: Bool) {
        Task { [self] in
            cloudSyncMessage = nil
            do {
                let report: CloudSyncReport
                if pull && push {
                    report = try await cloudSync.sync(bottle: bottle, appID: game.appID, auth: cloudAuth)
                } else if push {
                    report = try await cloudSync.push(bottle: bottle, appID: game.appID, auth: cloudAuth)
                } else {
                    report = try await cloudSync.pull(bottle: bottle, appID: game.appID, auth: cloudAuth)
                }
                cloudSyncIsError = !report.failures.isEmpty
                var parts: [String] = []
                if pull { parts.append("\(report.downloaded) pulled") }
                if push { parts.append("\(report.uploaded) pushed") }
                parts.append("\(report.skipped) up-to-date")
                if !report.failures.isEmpty { parts.append("\(report.failures.count) failed") }
                cloudSyncMessage = parts.joined(separator: ", ") + "."
            } catch CloudSyncClientError.authExpired {
                // Token went stale — flag it and pop the QR reconnect right away,
                // since the user explicitly asked to sync.
                cloudAuth.sessionExpired = true
                cloudSyncIsError = true
                cloudSyncMessage = "Steam sign-in expired — reconnect to finish syncing."
                isShowingCloudConnect = true
            } catch let err as SteamAuthError {
                cloudSyncIsError = true
                cloudSyncMessage = err.errorDescription
            } catch let err as CloudSyncClientError {
                cloudSyncIsError = true
                cloudSyncMessage = err.errorDescription
            } catch let err as CloudSyncError {
                cloudSyncIsError = true
                cloudSyncMessage = err.errorDescription
            } catch {
                cloudSyncIsError = true
                cloudSyncMessage = error.localizedDescription
            }
        }
    }

    func clearLocalSaves(for bottle: Bottle) {
        Task { [self] in
            cloudSyncMessage = nil
            do {
                let backup = try await cloudSync.backupAndClearLocalSaves(bottle: bottle, appID: game.appID, auth: cloudAuth)
                cloudSyncIsError = false
                cloudSyncMessage = "Local saves cleared. Backed up to \(backup.lastPathComponent). Use “Pull from cloud” to restore from Steam."
            } catch {
                cloudAuth.noteCloudError(error)
                cloudSyncIsError = true
                cloudSyncMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    /// Called when the QR sheet finishes connecting. Resumes a paused install.
    func cloudDidConnect() {
        cloudSyncMessage = "Connected to Steam Cloud as \(cloudAuth.account?.accountName ?? "?")."
        cloudSyncIsError = false
        if shouldResumeInstallAfterCloudConnect {
            shouldResumeInstallAfterCloudConnect = false
            startInstall()
        }
    }

    func signOutOfSteamCloud() {
        cloudAuth.signOut()
        cloudSyncMessage = "Disconnected from Steam Cloud."
        cloudSyncIsError = false
    }
}
