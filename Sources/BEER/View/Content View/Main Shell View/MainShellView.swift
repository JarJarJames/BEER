import SwiftUI

struct MainShellView: View {
    @Environment(SteamLibraryStore.self) private var library
    @Environment(BottleStore.self) private var store
    @Environment(SteamAuthStore.self) private var cloudAuth
    @Environment(SteamPresenceStore.self) private var presence
    @Environment(InstallVolumeMonitor.self) private var drives
    @Environment(GameMover.self) private var mover
    @Environment(GraphicsTranslatorInstaller.self) private var graphicsTranslator
    @State private var foundGames = FoundGamesStore()
    @State private var depotController = DepotDownloaderController()
    @State private var downloads = DownloadsStore()
    @State private var goldberg = GoldbergInstaller()
    @State private var cloudSync = CloudSyncEngine()
    @State private var windowsDependencies = WindowsDependencyInstaller()
    @State private var dlcStore = DLCStore()
    @State private var filter: LibraryFilter = .all
    @State private var selectedGameAppID: Int?

    var body: some View {
        LibraryPane(selectedGameAppID: $selectedGameAppID, filter: $filter)
        .environment(foundGames)
        .environment(depotController)
        .environment(downloads)
        .environment(goldberg)
        .environment(cloudSync)
        .environment(windowsDependencies)
        .environment(dlcStore)
        .frame(minWidth: MainShellLayout.detailMinWidth, maxWidth: .infinity,
               minHeight: MainShellLayout.detailMinHeight, maxHeight: .infinity)
        .navigationTitle(MainShellStrings.windowTitle())
        .toolbar {
            // The trailing corner. Nothing goes in the middle: a centered
            // item pulls the items after it in beside it. The All Games /
            // Installed switch is in the library's own bar instead.
            ToolbarItem(placement: .automatic) {
                DownloadsToolbarButton()
                    .environment(depotController)
                    .environment(downloads)
            }
            ToolbarItem(placement: .automatic) {
                SteamAccountMenu()
            }
        }
        // On the next turn of the run loop: when a shortcut launches BEER
        // the link is waiting before the first frame, and opening the game
        // page mid-layout sends the window's toolbar into a layout loop
        // (crash). A game page shows whatever the filter is.
        .onChange(of: GameLinkRouter.shared.requestedAppID, initial: true) { _, appID in
            Task {
                guard let appID else { return }
                GameLinkRouter.shared.requestedAppID = nil
                selectedGameAppID = appID
            }
        }
        .task {
            depotController.load()
            goldberg.refresh()
            graphicsTranslator.refresh()
        }
        // A drive plugged in, ejected or renamed: games on it follow, a move
        // it interrupted is finished or undone, and games on it that aren't in
        // BEER are offered. Also runs once when the shell appears.
        .onChange(of: drives.drives, initial: true) {
            Task { await drivesChanged() }
        }
        // Downloads paused before BEER last quit. The bottles load after
        // this view appears, and a row already showing is left alone.
        .onChange(of: store.bottles, initial: true) { _, bottles in downloads.restorePaused(from: bottles) }
        .onChange(of: store.bottles.count) { _, _ in
            Task { await foundGames.scan(drives: drives.drives, bottles: store.bottles, library: library.games) }
        }
        .onChange(of: library.games.count) { _, _ in
            Task { await foundGames.scan(drives: drives.drives, bottles: store.bottles, library: library.games) }
        }
    }

    private func drivesChanged() async {
        await store.followRenamedDrives()
        await store.renameFoldersWineCannotOpen()
        store.writeMissingFolderMarkers()
        await mover.finishInterruptedMoves(bottles: store) { bottle, folder in
            guard let appID = bottle.steamAppID else { return }
            try cloudSync.backUpSaves(inside: folder, appID: appID)
        }
        await foundGames.scan(drives: drives.drives, bottles: store.bottles, library: library.games)
    }
}
