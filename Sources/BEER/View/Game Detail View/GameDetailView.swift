import SwiftUI

/// Entry point for the game detail screen. Collects the stores from the
/// environment and hands them to `GameDetailScreen`, which owns the view model.
struct GameDetailView: View {
    let game: SteamLibraryGame
    let onBack: () -> Void

    @Environment(SteamLibraryStore.self) private var library
    @Environment(BottleStore.self) private var bottles
    @Environment(ToolchainDetector.self) private var detector
    @Environment(DepotDownloaderController.self) private var depotCtl
    @Environment(DownloadsStore.self) private var downloads
    @Environment(GoldbergInstaller.self) private var goldberg
    @Environment(SteamAuthStore.self) private var cloudAuth
    @Environment(CloudSyncEngine.self) private var cloudSync
    @Environment(SteamPresenceStore.self) private var presence
    @Environment(GraphicsTranslatorInstaller.self) private var graphicsTranslator
    @Environment(DLCStore.self) private var dlcStore
    @Environment(InstallVolumeMonitor.self) private var drives
    @Environment(GameMover.self) private var mover

    var body: some View {
        GameDetailScreen(
            game: game,
            onBack: onBack,
            dependencies: GameDetailDependencies(
                library: library, bottles: bottles, detector: detector,
                depotCtl: depotCtl, downloads: downloads, goldberg: goldberg,
                cloudAuth: cloudAuth, cloudSync: cloudSync, presence: presence,
                graphicsTranslator: graphicsTranslator, dlcStore: dlcStore,
                drives: drives, mover: mover
            )
        )
    }
}
