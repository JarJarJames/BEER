import SwiftUI

/// Entry point for the game detail screen. Collects the stores from the
/// environment and hands them to `GameDetailScreen`, which owns the view model.
struct GameDetailView: View {
    let game: SteamLibraryGame
    let onBack: () -> Void

    @EnvironmentObject private var library: SteamLibraryStore
    @EnvironmentObject private var bottles: BottleStore
    @EnvironmentObject private var detector: ToolchainDetector
    @EnvironmentObject private var depotCtl: DepotDownloaderController
    @EnvironmentObject private var downloads: DownloadsStore
    @EnvironmentObject private var goldberg: GoldbergInstaller
    @EnvironmentObject private var cloudAuth: SteamAuthStore
    @EnvironmentObject private var cloudSync: CloudSyncEngine
    @EnvironmentObject private var presence: SteamPresenceStore
    @EnvironmentObject private var graphicsTranslator: GraphicsTranslatorInstaller
    @EnvironmentObject private var dlcStore: DLCStore

    var body: some View {
        GameDetailScreen(
            game: game,
            onBack: onBack,
            dependencies: GameDetailDependencies(
                library: library, bottles: bottles, detector: detector,
                depotCtl: depotCtl, downloads: downloads, goldberg: goldberg,
                cloudAuth: cloudAuth, cloudSync: cloudSync, presence: presence,
                graphicsTranslator: graphicsTranslator, dlcStore: dlcStore
            )
        )
    }
}
