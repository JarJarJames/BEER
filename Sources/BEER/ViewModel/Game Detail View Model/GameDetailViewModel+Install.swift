import Foundation

extension GameDetailViewModel {
    func startInstallOrLogin() {
        startInstall()
    }

    var preferredDefaultRuntime: RuntimeCandidate? { detector.preferredGameRuntime }

    func startInstall() {
        guard !game.effectiveIsNonSteam else { return }   // nothing to download
        // Synchronous re-entry guard: a second click while the first is
        // still doing wineboot must be a no-op, not a fresh bottle.
        guard !isStartingInstall else { return }
        guard let runtime = preferredDefaultRuntime else { return }
        guard let steamAccount = cloudAuth.account, !cloudAuth.sessionExpired else {
            shouldResumeInstallAfterCloudConnect = true
            isShowingCloudConnect = true
            return
        }
        isStartingInstall = true

        Task { @MainActor [self] in
            defer { isStartingInstall = false }

            // Fire the Downloads entry FIRST so the UI shows something
            // immediately. The bottleID is patched in below.
            downloads.start(appID: game.appID, name: game.name, bottleID: UUID())
            downloads.setStatus(appID: game.appID, phase: "Initializing bottle…")

            // Resolve the bottle for this Steam appID:
            //   - Reuse any bottle already claimed for this appID (skips wineboot)
            //   - Otherwise create a fresh bottle + claim it immediately
            // After this point the bottle is tagged with steamAppID +
            // gameInstallStatus = .installing, so a future retry can find it.
            let bottle: Bottle
            if let existing = bottles.findBottle(forAppID: game.appID) {
                bottle = existing
                downloads.append(appID: game.appID, log: "Reusing existing bottle for this game (skipping wineboot).")
                // Defensive: clean up any other orphans for this appID.
                await bottles.cleanupOrphans(forAppID: game.appID, keep: existing.id)
            } else {
                let fresh = await bottles.createBottle(name: game.name, runtime: runtime, graphicsBackend: .automatic)
                await bottles.claimForSteamApp(fresh, appID: game.appID, gameName: game.name)
                bottle = fresh
            }
            let bottleID = bottle.id
            library.markInstalled(appID: game.appID, bottleID: bottleID)

            do {
                let result = try await depotCtl.installGame(
                    appID: game.appID,
                    gameName: game.name,
                    bottle: bottle,
                    auth: steamAccount,
                    events: downloads.consume(appID: game.appID)
                )

                // Apply the Steam emulator (GBE_Fork) so the game launches
                // without a running Steam process. Lazily install the
                // emulator on first use, then patch this game's install.
                downloads.setStatus(appID: game.appID, phase: "Installing Steam emulator…")
                if !goldberg.isInstalled {
                    await goldberg.install()
                }
                if goldberg.isInstalled {
                    downloads.setStatus(appID: game.appID, phase: "Patching with Steam emulator…")
                    do {
                        let achievementFetch = await fetchAchievementSchema(appID: game.appID)
                        let report = try GoldbergApplicator.apply(
                            installDir: result.installDirectory,
                            appID: game.appID,
                            account: cloudAuth.account?.accountName,
                            steamID64: cloudAuth.account?.steamID64,
                            dlc: bottles.live(bottle).effectiveInstalledDLC,
                            achievements: achievementFetch.achievements,
                            using: goldberg
                        )
                        downloads.append(
                            appID: game.appID,
                            log: "Goldberg: patched \(report.patched.count) DLLs (already-patched: \(report.alreadyPatched), settings: \(report.settingsDirs.count)). \(achievementFetch.note)"
                        )
                    } catch {
                        // Patch failure isn't fatal — the user can still
                        // launch, just may need a Steam process. Surface as
                        // a warning in the log.
                        downloads.append(appID: game.appID, log: "Goldberg patch warning: \(error.localizedDescription)")
                    }
                } else if let err = goldberg.lastError {
                    downloads.append(appID: game.appID, log: "Goldberg installer warning: \(err)")
                }

                let launchExeHost = result.launchExecutableHostPath.path
                if let refreshed = bottles.bottles.first(where: { $0.id == bottleID }) {
                    await bottles.recordGameInstall(
                        refreshed,
                        appID: game.appID,
                        gameName: game.name,
                        launchExecutable: launchExeHost,
                        launchArguments: nil,
                        installDirectory: result.installDirectory.path
                    )
                }
                downloads.complete(appID: game.appID)
            } catch DepotDownloaderError.sessionExpired {
                cloudAuth.sessionExpired = true
                shouldResumeInstallAfterCloudConnect = true
                downloads.fail(appID: game.appID, reason: "Steam sign-in expired. Reconnect to resume the download.")
                isShowingCloudConnect = true
            } catch let err as DepotDownloaderError {
                downloads.fail(appID: game.appID, reason: err.errorDescription ?? "Install failed")
            } catch {
                downloads.fail(appID: game.appID, reason: error.localizedDescription)
            }
        }
    }

    func cancelInstall(reason: String) {
        // We don't have process-kill plumbing yet; mark the UI state and
        // remove the bottle. The running DepotDownloader will eventually
        // exit on its own (it'll fail when its install dir disappears).
        downloads.fail(appID: game.appID, reason: reason)
        if let bottle = installedBottle {
            Task { [self] in
                await bottles.delete(bottle)
                library.markUninstalled(appID: game.appID)
                downloads.remove(appID: game.appID)
            }
        }
    }

    /// Uninstalling a non-Steam game deletes the folder it was brought in as,
    /// so it asks first. A Steam game can be downloaded again, so it doesn't.
    func requestUninstall() {
        if game.effectiveIsNonSteam {
            confirmRemoveNonSteamGame = true
        } else {
            uninstall()
        }
    }

    func uninstall() {
        let appID = game.appID
        let isNonSteam = game.effectiveIsNonSteam
        let bottle = installedBottle
        Task { [self] in
            if let bottle { await bottles.delete(bottle) }
            if isNonSteam {
                library.removeNonSteamGame(appID: appID)
            } else {
                library.markUninstalled(appID: appID)
            }
            downloads.remove(appID: appID)
        }
    }
}
