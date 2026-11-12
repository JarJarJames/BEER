import Foundation

extension GameDetailViewModel {
    func dlcRowState(bottle: Bottle) -> DLCRowState? {
        if let owned = dlcStore.ownedCount(for: game.appID) {
            guard owned > 0 else { return nil }   // owns none — hide the row
            return .installed(owned: owned, installed: bottle.effectiveInstalledDLC.count)
        }
        switch dlcStore.state(for: game.appID) {
        case .loading: return .loading
        case .failed: return .failed
        case .idle, .loaded:
            // Not looked yet. Offer the check rather than rendering nothing —
            // a silent empty row is how a broken lookup hid the first time.
            return isSteamConnected ? .unchecked : nil
        }
    }

    /// Discovery costs a Steam logon, so this runs once per game per session
    /// (DLCStore caches and coalesces) and only for installed games.
    func loadDLC(force: Bool) async {
        guard !game.effectiveIsNonSteam, isSteamConnected, let auth = cloudAuth.account else { return }
        guard installedBottle != nil else { return }
        await dlcStore.load(appID: game.appID, auth: auth, force: force)
    }

    func reloadDLC() {
        Task { [self] in await loadDLC(force: true) }
    }

    /// Run a paused DLC download again. DepotDownloader keeps what it already
    /// has, so this carries on rather than starting over.
    func resumeDLC(_ dlcAppID: Int) {
        guard let bottle = installedBottle, let installDir = bottle.resolvedInstallDirectory,
              let auth = cloudAuth.account else { return }
        Task { [self] in
            await loadDLC(force: false)
            guard case .loaded(let found) = dlcStore.state(for: appID),
                  let dlc = found.first(where: { $0.appID == dlcAppID }) else { return }
            await dlcStore.install(
                dlc, bottle: bottle, installDir: installDir, auth: auth,
                controller: depotCtl, downloads: downloads, bottles: bottles
            )
        }
    }
}
