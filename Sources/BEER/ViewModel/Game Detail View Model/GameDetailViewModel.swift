import Combine
import Foundation

/// State and actions behind the game detail screen: install, launch, Steam
/// Cloud sync, the Steam emulator patch, and DLC. The views stay declarative;
/// anything that touches a store or the disk lives here, split by concern
/// across the `GameDetailViewModel+*.swift` files.
@MainActor
final class GameDetailViewModel: ObservableObject {
    let appID: Int
    let dependencies: GameDetailDependencies
    private let initialGame: SteamLibraryGame

    let library: SteamLibraryStore
    let bottles: BottleStore
    let detector: ToolchainDetector
    let depotCtl: DepotDownloaderController
    let downloads: DownloadsStore
    let goldberg: GoldbergInstaller
    let cloudAuth: SteamAuthStore
    let cloudSync: CloudSyncEngine
    let presence: SteamPresenceStore
    let graphicsTranslator: GraphicsTranslatorInstaller
    let dlcStore: DLCStore

    @Published var isShowingCloudConnect: Bool = false
    @Published var isShowingDLCManager: Bool = false
    @Published var shouldResumeInstallAfterCloudConnect: Bool = false
    @Published var cloudSyncMessage: String?
    @Published var cloudSyncIsError: Bool = false
    @Published var confirmClearBottle: Bottle?
    @Published var patchStatusMessage: String?
    @Published var patchStatusIsError: Bool = false
    @Published var isPatching: Bool = false
    /// Bumped after every Apply/Restore so the patch-status row re-reads
    /// the install dir from disk.
    @Published var patchProbeTick: Int = 0
    /// Cached result of the install-directory probe. `PatchStatus.probe(at:)`
    /// walks the game's whole install tree, so it must never run from `body` —
    /// every published change anywhere (a download progress tick, say) would
    /// re-walk it. Refreshed only when the tick changes or the bottle does.
    @Published var cachedPatchStatus: PatchStatus?
    /// Synchronous re-entry guard for the Install button. Prevents the
    /// 20-second wineboot phase from being kicked off multiple times if the
    /// user clicks Install rapidly.
    @Published var isStartingInstall: Bool = false

    private var storeChanges: Set<AnyCancellable> = []

    init(game: SteamLibraryGame, dependencies: GameDetailDependencies) {
        appID = game.appID
        self.dependencies = dependencies
        initialGame = game
        library = dependencies.library
        bottles = dependencies.bottles
        detector = dependencies.detector
        depotCtl = dependencies.depotCtl
        downloads = dependencies.downloads
        goldberg = dependencies.goldberg
        cloudAuth = dependencies.cloudAuth
        cloudSync = dependencies.cloudSync
        presence = dependencies.presence
        graphicsTranslator = dependencies.graphicsTranslator
        dlcStore = dependencies.dlcStore

        // The screen reads store state through this object, so a change in any
        // store has to redraw it — the same reach the view had when it observed
        // each store directly.
        for publisher in dependencies.changePublishers {
            publisher
                .sink { [weak self] _ in self?.objectWillChange.send() }
                .store(in: &storeChanges)
        }
    }

    /// The library's current copy of this game; the snapshot the screen was
    /// opened with if it has since disappeared.
    var game: SteamLibraryGame {
        library.games.first { $0.appID == appID } ?? initialGame
    }

    var installedBottle: Bottle? {
        guard let id = game.installedBottleID else { return nil }
        return bottles.bottles.first { $0.id == id }
    }

    var download: DownloadsStore.Entry? {
        downloads.entry(for: appID)
    }

    var isSteamConnected: Bool {
        cloudAuth.account != nil && !cloudAuth.sessionExpired
    }
}
