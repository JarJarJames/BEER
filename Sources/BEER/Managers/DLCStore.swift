import Foundation

// Discovery of a game's DLC, and the bookkeeping for turning one on.
//
// Two things have to happen for a game to see its DLC, and neither is part of
// the base install:
//
//   1. The content has to be on disk. DLC are separate Steam apps with their
//      own depots, so `DepotDownloader -app <base>` never fetches them. Each
//      one is pulled with its own run, into the existing install directory.
//   2. The emulator has to report the entitlement. GBE_Fork answers
//      GetDLCCount() from `[app::dlcs]` in configs.app.ini, so a DLC that is on
//      disk but not declared still enumerates as absent.
//
// Download *progress* is deliberately not tracked here — a DLC install is an
// install, so it goes through DownloadsStore like any other and shows up in the
// Downloads pane. This store owns discovery only.
//
// Discovery results are cached per app for the session: every lookup costs a
// Steam logon, and Steam throttles accounts that log on too often.
@MainActor
final class DLCStore: ObservableObject {

    /// Discovery state per app. Keyed rather than "current app + a copy of its
    /// rows", so a slow reply for one game can't land on another's view.
    @Published private(set) var states: [Int: LoadState] = [:]
    @Published var message: StatusMessage?

    private let client = CloudSyncClient()
    private var inFlight: [Int: Task<Void, Never>] = [:]

    func state(for appID: Int) -> LoadState { states[appID] ?? .idle }

    /// Owned DLC count, or nil if we haven't successfully looked yet. The game
    /// detail row uses nil to mean "not checked", not "none".
    func ownedCount(for appID: Int) -> Int? {
        guard case .loaded(let found) = state(for: appID) else { return nil }
        return found.filter(\.owned).count
    }

    // MARK: - Discovery

    func load(appID: Int, auth: SteamCloudAccount, force: Bool = false) async {
        if force { states[appID] = nil }
        if case .loaded = state(for: appID) { return }

        // Coalesce: the detail row and the manager sheet both ask, and each
        // miss would otherwise spawn its own helper process and Steam logon.
        if let existing = inFlight[appID] {
            await existing.value
            return
        }

        states[appID] = .loading
        let task = Task { [client] in
            do {
                let found = try await client.dlc(
                    appID: appID,
                    account: auth.accountName,
                    refreshToken: auth.refreshToken
                )
                let sorted = found.sorted {
                    if $0.owned != $1.owned { return $0.owned }
                    return $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
                states[appID] = .loaded(sorted)
            } catch {
                states[appID] = .failed(error.localizedDescription)
            }
        }
        inFlight[appID] = task
        await task.value
        inFlight[appID] = nil
    }

    // MARK: - Install

    /// Download `dlc` into the game's existing install and declare it to the
    /// emulator. The base game is never re-downloaded.
    func install(
        _ dlc: CloudSyncClient.DLCInfo,
        bottle: Bottle,
        installDir: URL,
        auth: SteamCloudAccount,
        controller: DepotDownloaderController,
        downloads: DownloadsStore,
        bottles: BottleStore
    ) async {
        guard downloads.entry(for: dlc.appID)?.isActive != true else { return }
        message = nil

        do {
            if dlc.hasDepots {
                downloads.start(appID: dlc.appID, name: dlc.name,
                                bottleID: bottle.id, parentAppID: bottle.steamAppID)
                try await controller.installDLC(
                    appID: dlc.appID,
                    installDir: installDir,
                    auth: auth,
                    events: downloads.consume(appID: dlc.appID)
                )
            }

            try await changeDLC(of: bottle, installDir: installDir, bottles: bottles) { list in
                list.filter { $0.appID != dlc.appID }
                    + [InstalledDLC(appID: dlc.appID, name: dlc.name, installedAt: Date())]
            }

            if dlc.hasDepots { downloads.complete(appID: dlc.appID) }
            message = .success(dlc.hasDepots
                ? "Installed \(dlc.name)."
                : "Enabled \(dlc.name). It has no files to download — only the entitlement was needed.")
        } catch {
            if dlc.hasDepots { downloads.fail(appID: dlc.appID, reason: error.localizedDescription) }
            message = .failure(error.localizedDescription)
        }
    }

    /// Stop telling the game it owns `dlc`. Downloaded files are deliberately
    /// left in place: we have no record of which files came from which depot,
    /// so deleting by guesswork could take the base game with it.
    func disable(
        _ dlc: InstalledDLC,
        bottle: Bottle,
        installDir: URL,
        bottles: BottleStore
    ) async {
        do {
            try await changeDLC(of: bottle, installDir: installDir, bottles: bottles) { list in
                list.filter { $0.appID != dlc.appID }
            }
            message = .success("Disabled \(dlc.name). Its files are still on disk.")
        } catch {
            message = .failure(error.localizedDescription)
        }
    }

    /// Transform the bottle's DLC list, reproject the emulator's `[app::dlcs]`
    /// block from it, and persist — always in that order, so the bottle and the
    /// on-disk config can't drift apart.
    private func changeDLC(
        of bottle: Bottle,
        installDir: URL,
        bottles: BottleStore,
        _ transform: ([InstalledDLC]) -> [InstalledDLC]
    ) async throws {
        // Re-read: an install is slow, and a batch updates this between items.
        var updated = bottles.live(bottle)
        updated.installedDLC = transform(updated.effectiveInstalledDLC)
            .sorted { $0.appID < $1.appID }
        if updated.gameInstallDirectory == nil {
            updated.gameInstallDirectory = installDir.path
        }

        // Only meaningful once the emulator is applied; updateDLC walks the
        // steam_settings folders the patcher created, so an unpatched install
        // updates nothing and the config lands on the next Apply.
        try GoldbergApplicator.updateDLC(installDir: installDir, dlc: updated.effectiveInstalledDLC)
        await bottles.update(updated)
    }
}
