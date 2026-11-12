import Foundation

extension GameDetailViewModel {
    func startInstallOrLogin() {
        requestInstall()
    }

    var preferredDefaultRuntime: RuntimeCandidate? { detector.preferredGameRuntime }

    /// Show the install sheet: the game's size, where it can go and each
    /// place's free space, with Install turned off when it won't fit. Nothing
    /// downloads until confirmed.
    func requestInstall() {
        guard !game.effectiveIsNonSteam, !isStartingInstall, preferredDefaultRuntime != nil else { return }
        // Ask before the sheet: a download Wine can't run is wasted.
        guard bottles.requireRosetta() else { return }
        guard let steamAccount = cloudAuth.account, !cloudAuth.sessionExpired else {
            shouldResumeInstallAfterCloudConnect = true
            isShowingCloudConnect = true
            return
        }
        installSpaceReport = nil
        installSize = nil
        // A resumed download leaves out what was left out before.
        skippedDLC = Set(bottles.findBottle(forAppID: game.appID)?.skippedDLC?.map(\.appID) ?? [])
        prepareInstallTargets()
        isShowingInstallSheet = true

        Task { [self] in
            let size = await installSpaceCheck.size(appIDs: [game.appID], account: steamAccount)
            guard isShowingInstallSheet else { return }
            installSize = size
            await assessInstallTarget()
        }
    }

    func confirmInstall() {
        guard let target = installTarget else { return }
        let checked = installSpaceReport?.verdict
        let leftOut = installSize?.dlc.filter { skippedDLC.contains($0.appID) } ?? []
        let depots = installSize?.depots(leavingOut: leftOut)
        isShowingInstallSheet = false
        if bottles.findBottle(forAppID: game.appID) == nil {
            UserDefaults.standard.set(target.volume?.uuid, forKey: InstallPreferences.lastDriveKey)
        }
        // Without the depot list nothing can be left out, so none is recorded.
        startInstall(to: target, checked: checked, leavingOut: depots == nil ? [] : leftOut, depots: depots)
    }

    /// Tick or untick a DLC in the install sheet, and re-check the space.
    func setDLC(_ appID: Int, included: Bool) {
        if included { skippedDLC.remove(appID) } else { skippedDLC.insert(appID) }
        installSpaceReport = nil
        Task { await assessInstallTarget() }
    }

    /// `checked` is the install sheet's answer, so the size isn't asked for
    /// twice; without it the check runs here. A game that already has a bottle
    /// goes where its files already are, whatever `target` says. `depots`, when
    /// given, is exactly what to download: everything but the `leftOut` DLC.
    func startInstall(
        to target: InstallTarget, checked: InstallSpace? = nil,
        leavingOut leftOut: [InstallableDLC] = [], depots: [Int]? = nil
    ) {
        guard !game.effectiveIsNonSteam else { return }   // nothing to download
        // Synchronous re-entry guard: a second click while the first is
        // still doing wineboot must be a no-op, not a fresh bottle.
        guard !isStartingInstall else { return }
        guard let runtime = preferredDefaultRuntime else { return }
        guard bottles.requireRosetta() else { return }
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
            downloads.setStatus(appID: game.appID, phase: "Checking free space…")

            // Before any bottle exists, so a refused install leaves nothing behind.
            let space: InstallSpace
            if let checked {
                space = checked
            } else {
                let (destination, partial) = installDestination(for: target)
                space = await installSpaceCheck.run(
                    appIDs: [game.appID], account: steamAccount,
                    destination: destination, partialDownload: partial
                )
            }
            switch space {
            case .fits:
                break
            case .unchecked(let note):
                downloads.append(appID: game.appID, log: note)
            case .short(let shortfall):
                downloads.remove(appID: game.appID)
                diskSpaceShortfall = shortfall
                return
            }

            // The drive may have been unplugged since the sheet showed it.
            let existing = bottles.findBottle(forAppID: game.appID)
            let mountedDrive: InstallVolume?
            if let existing {
                mountedDrive = fixedTarget(for: existing)?.volume
                if let drive = existing.gameDrive, mountedDrive == nil {
                    downloads.fail(appID: game.appID, reason: InstallDriveStrings.resumeDriveMissing(drive.name))
                    return
                }
            } else if let volume = target.volume {
                guard let mounted = volume.uuid.flatMap(VolumeCatalog.system.drive(withUUID:)) else {
                    downloads.fail(appID: game.appID, reason: InstallDriveStrings.driveNotConnected(volume.name))
                    return
                }
                mountedDrive = mounted
            } else {
                mountedDrive = nil
            }
            downloads.setStatus(appID: game.appID, phase: "Initializing bottle…")

            // Resolve the bottle for this Steam appID:
            //   - Reuse any bottle already claimed for this appID (skips wineboot
            //     unless its first one never finished)
            //   - Otherwise create a fresh bottle + claim it immediately
            // After this point the bottle is tagged with steamAppID +
            // gameInstallStatus = .installing and knows where its files go,
            // so a future retry can find both.
            let bottle: Bottle
            let installDir: URL
            let drive: GameDrive?
            if let existing {
                bottle = existing
                installDir = existing.downloadDirectory(gameName: game.name)
                drive = existing.gameDrive
                downloads.append(appID: game.appID, log: "Reusing existing bottle for this game.")
                await bottles.initializeIfNeeded(existing)
                // Defensive: clean up any other orphans for this appID.
                await bottles.cleanupOrphans(forAppID: game.appID, keep: existing.id)
            } else {
                let fresh = await bottles.createBottle(name: game.name, runtime: runtime, graphicsBackend: .automatic)
                drive = mountedDrive?.link
                installDir = mountedDrive.map {
                    GameFolders.freeFolder(for: game.name,
                                           in: AppPaths.driveGamesDirectory(onDriveAt: $0.root))
                } ?? AppPaths.gameInstallDirectory(for: fresh, gameName: game.name)
                await bottles.claimForSteamApp(fresh, appID: game.appID, gameName: game.name,
                                               installDirectory: installDir, drive: drive)
                bottle = fresh
            }
            let bottleID = bottle.id
            library.markInstalled(appID: game.appID, bottleID: bottleID)
            var chosen = bottles.live(bottle)
            chosen.skippedDLC = leftOut.isEmpty ? nil : leftOut
            chosen.pausedDownload = nil
            await bottles.update(chosen)

            do {
                let result = try await depotCtl.installGame(
                    appID: game.appID,
                    gameName: game.name,
                    installDir: installDir,
                    auth: steamAccount,
                    depots: depots,
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

                // Run what Steam's Play button would run. The file-size guess
                // is only the fallback: it picks Isaac's Mod Uploader, say.
                var launchExe = result.launchExecutableHostPath
                var steamArguments: String?
                var launchConfigChecked = false
                do {
                    let entries = try await steamLaunchEntries()
                    launchConfigChecked = true
                    if let target = SteamLaunchResolver.resolve(entries, in: result.installDirectory) {
                        launchExe = target.executable
                        steamArguments = target.arguments
                        downloads.append(appID: game.appID, log: "Launch executable from Steam: \(launchExe.lastPathComponent)")
                    } else {
                        downloads.append(appID: game.appID, log: "Steam lists no Windows launch option in this install; using \(launchExe.lastPathComponent).")
                    }
                } catch {
                    let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    downloads.append(appID: game.appID, log: "Couldn't read Steam's launch options (\(msg)); using \(launchExe.lastPathComponent).")
                }

                if let refreshed = bottles.bottles.first(where: { $0.id == bottleID }) {
                    await bottles.recordGameInstall(
                        refreshed,
                        appID: game.appID,
                        gameName: game.name,
                        launchExecutable: launchExe.path,
                        // Arguments the user set before a reinstall win.
                        launchArguments: refreshed.gameLaunchArguments == nil ? steamArguments : nil,
                        installDirectory: result.installDirectory.path,
                        drive: drive,
                        steamLaunchConfigChecked: launchConfigChecked
                    )
                    attempt("Write game folder marker", log: Log.install) {
                        try GameFolderMarkerFile.write(
                            GameFolderMarkerFile.marker(for: bottles.live(refreshed), installDir: result.installDirectory),
                            in: result.installDirectory
                        )
                    }
                }
                // DepotDownloader just brought every depot up to date, and
                // left its record in the folder for the next check.
                library.applyUpdateCheck([game.appID: .current])
                await createShortcutsChosenAtInstall(appID: game.appID)
                downloads.complete(appID: game.appID)
            } catch DepotDownloaderError.paused {
                // Recorded on the bottle so it still shows as paused after a quit.
                var paused = bottles.live(bottle)
                paused.pausedDownload = PausedDownload(
                    fraction: downloads.entry(for: game.appID)?.fraction ?? 0, pausedAt: Date())
                await bottles.update(paused)
                downloads.pause(appID: game.appID)
            } catch DepotDownloaderError.sessionExpired {
                cloudAuth.sessionExpired = true
                shouldResumeInstallAfterCloudConnect = true
                downloads.fail(appID: game.appID, reason: "Steam sign-in expired. Reconnect to resume the download.")
                isShowingCloudConnect = true
            } catch _ where drive.map({ !GameFolders.isConnected($0, volumes: .system) }) ?? false {
                // Whatever DepotDownloader said, the cause is the drive. What
                // came down is on it; Resume continues from there.
                downloads.fail(appID: game.appID, reason: InstallDriveStrings.downloadPaused(drive?.name ?? ""))
            } catch let err as DepotDownloaderError {
                downloads.fail(appID: game.appID, reason: err.errorDescription ?? "Install failed")
            } catch {
                downloads.fail(appID: game.appID, reason: error.localizedDescription)
            }
        }
    }

    /// Carry on with a paused download: same folder, same DLC left out, no
    /// install sheet. Falls back to the sheet whenever it can't tell exactly
    /// what the first download fetched, or the drive it's on is unplugged.
    func resumeInstall() {
        guard !isStartingInstall, let existing = bottles.findBottle(forAppID: game.appID),
              let target = fixedTarget(for: existing),
              let account = cloudAuth.account, !cloudAuth.sessionExpired else {
            requestInstall()
            return
        }
        let leftOut = existing.skippedDLC ?? []
        // Nothing left out: DepotDownloader picks the depots itself, as it did.
        guard !leftOut.isEmpty else {
            startInstall(to: target)
            return
        }
        isStartingInstall = true
        Task { [self] in
            // One size lookup serves both the depot list and the space check.
            let size = await installSpaceCheck.size(appIDs: [game.appID], account: account)
            let (destination, partial) = installDestination(for: target)
            let space = await installSpaceCheck.assess(
                size.leavingOut(Set(leftOut.map(\.appID))), destination: destination, partialDownload: partial)
            isStartingInstall = false
            // Without the depot list the skipped DLC would come down too.
            guard let depots = size.depots(leavingOut: leftOut) else {
                requestInstall()
                return
            }
            startInstall(to: target, checked: space.verdict, leavingOut: leftOut, depots: depots)
        }
    }

    /// Resume from the Downloads list (see `GameLinkRouter.resume`), when the
    /// entry is this game's own download or one of its DLC.
    func resumeIfRequested(_ id: Int?) {
        guard let id, id == appID || downloads.entry(for: id)?.parentAppID == appID else { return }
        GameLinkRouter.shared.pendingResumeID = nil
        if id == appID { resumeInstall() } else { resumeDLC(id) }
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
    /// Either asks when its drive isn't connected: the files stay there.
    func requestUninstall() {
        if installLocation?.missingDriveName != nil {
            confirmRemoveWithDriveMissing = true
        } else if game.effectiveIsNonSteam {
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
            GameShortcutStore.shared.removeShortcuts(appID: appID)
            if isNonSteam {
                library.removeNonSteamGame(appID: appID)
            } else {
                library.markUninstalled(appID: appID)
            }
            downloads.remove(appID: appID)
        }
    }
}
