import Combine
import Foundation

/// State and actions behind the DLC manager sheet: what the account owns, what
/// is already installed, and installing or disabling individual DLC.
@MainActor
final class DLCManagerViewModel: ObservableObject {
    let game: SteamLibraryGame
    let installDir: URL
    private let bottle: Bottle
    private let dlcStore: DLCStore
    private let bottles: BottleStore
    private let depotCtl: DepotDownloaderController
    private let downloads: DownloadsStore
    private let cloudAuth: SteamAuthStore

    @Published private(set) var isInstallingAll = false
    private var storeChanges: Set<AnyCancellable> = []

    init(game: SteamLibraryGame, bottle: Bottle, installDir: URL, dependencies: GameDetailDependencies) {
        self.game = game
        self.bottle = bottle
        self.installDir = installDir
        dlcStore = dependencies.dlcStore
        bottles = dependencies.bottles
        depotCtl = dependencies.depotCtl
        downloads = dependencies.downloads
        cloudAuth = dependencies.cloudAuth

        for publisher in [dlcStore.objectWillChange, bottles.objectWillChange, depotCtl.objectWillChange,
                          downloads.objectWillChange, cloudAuth.objectWillChange] {
            publisher
                .sink { [weak self] _ in self?.objectWillChange.send() }
                .store(in: &storeChanges)
        }
    }

    private var liveBottle: Bottle { bottles.live(bottle) }

    var loadState: DLCStore.LoadState { dlcStore.state(for: game.appID) }
    var owned: [CloudSyncClient.DLCInfo] { loadState.owned }
    var message: StatusMessage? { dlcStore.message }

    /// `isInstalling` drops to false between items of a batch; gate on the batch
    /// flag too so buttons don't flicker back to enabled mid-run.
    var isBusy: Bool { depotCtl.isBusy || isInstallingAll }

    /// Computed once per body pass: `effectiveInstalledDLC` sorts on every
    /// access, so it must not be recomputed per row.
    var installedIDs: Set<Int> { Set(liveBottle.effectiveInstalledDLC.map(\.appID)) }

    func activeDownload(for dlc: CloudSyncClient.DLCInfo) -> DownloadsStore.Entry? {
        downloads.entry(for: dlc.appID).flatMap { $0.isActive ? $0 : nil }
    }

    func loadIfNeeded() async {
        guard let auth = cloudAuth.account else { return }
        await dlcStore.load(appID: game.appID, auth: auth)
    }

    func reload() {
        guard let auth = cloudAuth.account else { return }
        Task { await dlcStore.load(appID: game.appID, auth: auth, force: true) }
    }

    func install(_ dlc: CloudSyncClient.DLCInfo) {
        guard let auth = cloudAuth.account else { return }
        Task { await installOne(dlc, auth: auth) }
    }

    func installAll(_ queue: [CloudSyncClient.DLCInfo]) {
        guard let auth = cloudAuth.account else { return }
        isInstallingAll = true
        Task { [self] in
            defer { isInstallingAll = false }
            // One auth session for the batch: each DLC still gets its own
            // DepotDownloader run, but they no longer re-mint the credential
            // cache — and re-authenticating per item is what Steam throttles.
            try? await depotCtl.withAuthSession(auth: auth) {
                // Serially: parallel runs would fight over the install dir.
                for dlc in queue {
                    await installOne(dlc, auth: auth)
                    if dlcStore.message?.isError == true { break }
                }
            }
        }
    }

    private func installOne(_ dlc: CloudSyncClient.DLCInfo, auth: SteamCloudAccount) async {
        await dlcStore.install(
            dlc, bottle: liveBottle, installDir: installDir, auth: auth,
            controller: depotCtl, downloads: downloads, bottles: bottles
        )
    }

    func disable(_ dlc: CloudSyncClient.DLCInfo) {
        guard let record = liveBottle.effectiveInstalledDLC.first(where: { $0.appID == dlc.appID }) else { return }
        Task { [self] in
            await dlcStore.disable(record, bottle: liveBottle, installDir: installDir, bottles: bottles)
        }
    }
}
