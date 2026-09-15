import Foundation

// Discovery + install state for a game's DLC.
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
// Discovery results are cached per app for the session: every lookup costs a
// Steam logon, and Steam throttles accounts that log on too often.
@MainActor
final class DLCStore: ObservableObject {

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    struct InstallProgress: Equatable {
        var fraction: Double
        var phase: String
    }

    @Published private(set) var state: LoadState = .idle
    /// DLC for the app most recently loaded, owned ones first.
    @Published private(set) var entries: [CloudSyncClient.DLCInfo] = []
    @Published private(set) var progress: [Int: InstallProgress] = [:]
    @Published var message: String?
    @Published var messageIsError: Bool = false

    /// The app `entries` and `state` currently describe.
    @Published private(set) var loadedAppID: Int?

    private var cache: [Int: [CloudSyncClient.DLCInfo]] = [:]
    private let client = CloudSyncClient()

    var owned: [CloudSyncClient.DLCInfo] { entries.filter(\.owned) }
    var isInstalling: Bool { !progress.isEmpty }

    /// Owned DLC already known for `appID` without contacting Steam. Lets the
    /// detail view decide whether to show the DLC row before any fetch.
    func cachedOwnedCount(for appID: Int) -> Int? {
        cache[appID]?.filter(\.owned).count
    }

    // MARK: - Discovery

    func load(appID: Int, auth: SteamCloudAccount, force: Bool = false) async {
        if !force, let cached = cache[appID] {
            entries = cached
            loadedAppID = appID
            state = .loaded
            return
        }
        if loadedAppID != appID { entries = [] }
        loadedAppID = appID
        state = .loading
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
            cache[appID] = sorted
            // A different game may have been opened while Steam answered.
            guard loadedAppID == appID else { return }
            entries = sorted
            state = .loaded
        } catch {
            guard loadedAppID == appID else { return }
            state = .failed(error.localizedDescription)
        }
    }

    /// Drop a cached result so the next load re-queries Steam — used after the
    /// user buys DLC and wants it to show up without restarting the app.
    func invalidate(appID: Int) {
        cache[appID] = nil
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
        bottles: BottleStore
    ) async {
        guard progress[dlc.appID] == nil else { return }
        progress[dlc.appID] = InstallProgress(fraction: 0, phase: "Connecting…")
        message = nil
        defer { progress[dlc.appID] = nil }

        do {
            if dlc.hasDepots {
                try await controller.installDLC(
                    appID: dlc.appID,
                    installDir: installDir,
                    auth: auth
                ) { [weak self] event in
                    guard let self else { return }
                    switch event {
                    case .status(let phase):
                        self.progress[dlc.appID]?.phase = phase
                    case .progress(let fraction):
                        self.progress[dlc.appID]?.fraction = fraction
                    case .downloadComplete:
                        self.progress[dlc.appID]?.fraction = 1
                        self.progress[dlc.appID]?.phase = "Finishing…"
                    case .log:
                        break
                    }
                }
            }

            try await record(dlc, bottle: bottle, installDir: installDir, bottles: bottles)

            message = dlc.hasDepots
                ? "Installed \(dlc.name)."
                : "Enabled \(dlc.name). It has no files to download — only the entitlement was needed."
            messageIsError = false
        } catch {
            message = error.localizedDescription
            messageIsError = true
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
        var updated = bottle
        updated.installedDLC = bottle.effectiveInstalledDLC.filter { $0.appID != dlc.appID }
        do {
            try GoldbergApplicator.updateDLC(installDir: installDir, dlc: updated.effectiveInstalledDLC)
            await bottles.update(updated)
            message = "Disabled \(dlc.name). Its files are still on disk."
            messageIsError = false
        } catch {
            message = error.localizedDescription
            messageIsError = true
        }
    }

    /// Persist the DLC on the bottle and rewrite the emulator's `[app::dlcs]`
    /// block. Both together, so the on-disk config and the bottle never drift.
    private func record(
        _ dlc: CloudSyncClient.DLCInfo,
        bottle: Bottle,
        installDir: URL,
        bottles: BottleStore
    ) async throws {
        // Re-read the bottle: a DLC install is slow and the record may have
        // been updated by an earlier DLC in the same batch.
        let live = bottles.bottles.first { $0.id == bottle.id } ?? bottle
        var updated = live
        var list = live.effectiveInstalledDLC.filter { $0.appID != dlc.appID }
        list.append(InstalledDLC(
            appID: dlc.appID,
            name: dlc.name,
            hasContent: dlc.hasDepots,
            installedAt: Date()
        ))
        updated.installedDLC = list.sorted { $0.appID < $1.appID }
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
