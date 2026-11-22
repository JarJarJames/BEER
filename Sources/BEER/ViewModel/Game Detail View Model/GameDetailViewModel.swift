import Foundation

/// State and actions behind the game detail screen: install, launch, Steam
/// Cloud sync, the Steam emulator patch, and DLC. The views stay declarative;
/// anything that touches a store or the disk lives here, split by concern
/// across the `GameDetailViewModel+*.swift` files.
@MainActor @Observable
final class GameDetailViewModel {
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
    let drives: InstallVolumeMonitor
    let mover: GameMover

    /// The sheet that's up, if any. Opening one replaces whatever was up.
    var sheet: GameDetailSheet?
    /// The confirmation or alert that's up, if any.
    var dialog: GameDetailDialog?
    /// An install waiting on sign-in: the install sheet opens once the
    /// sign-in sheet closes signed in.
    var shouldResumeInstallAfterCloudConnect: Bool = false
    var cloudSyncMessage: String?
    var cloudSyncIsError: Bool = false
    var saveBackups: [CloudSaveSnapshot] = []
    /// Shown inside the backups sheet: why a restore couldn't start or failed.
    var saveBackupsError: String?
    /// Kept here rather than read in `body`, which redraws on every store tick.
    var pendingRestore: PendingSaveRestore?
    /// The install sheet's free space for the chosen place; nil while it's looked up.
    var installSpaceReport: InstallSpaceReport?
    /// Steam's size for the game; nil while it's asked.
    var installSize: InstallSize?
    /// The DLC (app IDs) unticked in the install sheet.
    var skippedDLC: Set<Int> = []
    /// The places the install sheet offers, and the one chosen.
    var installOptions: [InstallTargetOption] = []
    var installTarget: InstallTarget?
    /// Shown under the install sheet's list: why the place is fixed.
    var installNote: String?
    var moveOptions: [InstallTargetOption] = []
    var moveTarget: InstallTarget?
    /// What the game takes up now; nil while it's measured.
    var moveSourceBytes: Int64?
    /// The move result, shown in the Location row.
    var moveMessage: String?
    var moveIsError: Bool = false
    @ObservationIgnored var installSpaceCheck = InstallSpaceCheck()
    /// The runtime a new install gets. Tests swap this out.
    @ObservationIgnored var preferredRuntime: @MainActor () -> RuntimeCandidate?
    var artworkError: String?
    /// The installed game's folder size, once measured for the Size stat.
    var installedBytes: Int64?
    var patchStatusMessage: String?
    var patchStatusIsError: Bool = false
    var isPatching: Bool = false
    /// Bumped after every Apply/Restore so the patch-status row re-reads
    /// the install dir from disk.
    var patchProbeTick: Int = 0
    /// Cached result of the install-directory probe. `PatchStatus.probe(at:)`
    /// walks the game's whole install tree, so it must never run from `body` —
    /// every published change anywhere (a download progress tick, say) would
    /// re-walk it. Refreshed only when the tick changes or the bottle does.
    var cachedPatchStatus: PatchStatus?
    /// Synchronous re-entry guard for the Install button. Prevents the
    /// 20-second wineboot phase from being kicked off multiple times if the
    /// user clicks Install rapidly.
    var isStartingInstall: Bool = false

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
        drives = dependencies.drives
        mover = dependencies.mover
        preferredRuntime = { [detector = dependencies.detector] in detector.preferredGameRuntime }
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

    /// Where the installed game's files are right now.
    var installLocation: InstallLocation? {
        installedBottle.map(bottles.installLocation(of:))
    }

    var download: DownloadsStore.Entry? {
        downloads.entry(for: appID)
    }

    /// The progress panel's Pause: nil unless DepotDownloader is running for
    /// this game, since bottle setup and emulator patching can't be stopped.
    var pauseDownload: (() -> Void)? {
        guard depotCtl.pausableIDs.contains(appID) else { return nil }
        return { [depotCtl, downloads, appID] in depotCtl.pause(appID, in: downloads) }
    }

    var isSteamConnected: Bool {
        cloudAuth.account != nil && !cloudAuth.sessionExpired
    }
}
