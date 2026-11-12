import SwiftUI

struct MainShellView: View {
    @EnvironmentObject private var library: SteamLibraryStore
    @EnvironmentObject private var store: BottleStore
    @EnvironmentObject private var cloudAuth: SteamAuthStore
    @EnvironmentObject private var presence: SteamPresenceStore
    @EnvironmentObject private var drives: InstallVolumeMonitor
    @EnvironmentObject private var mover: GameMover
    @StateObject private var foundGames = FoundGamesStore()
    @StateObject private var depotController = DepotDownloaderController()
    @StateObject private var downloads = DownloadsStore()
    @StateObject private var goldberg = GoldbergInstaller()
    @StateObject private var cloudSync = CloudSyncEngine()
    @EnvironmentObject private var graphicsTranslator: GraphicsTranslatorInstaller
    @StateObject private var windowsDependencies = WindowsDependencyInstaller()
    @StateObject private var dlcStore = DLCStore()
    @State private var filter: LibraryFilter = .all
    @State private var selectedGameAppID: Int?

    var body: some View {
        LibraryPane(selectedGameAppID: $selectedGameAppID, filter: $filter)
        .environmentObject(foundGames)
        .environmentObject(depotController)
        .environmentObject(downloads)
        .environmentObject(goldberg)
        .environmentObject(cloudSync)
        .environmentObject(windowsDependencies)
        .environmentObject(dlcStore)
        .frame(minWidth: MainShellLayout.detailMinWidth, maxWidth: .infinity,
               minHeight: MainShellLayout.detailMinHeight, maxHeight: .infinity)
        .navigationTitle(MainShellStrings.appName)
        .toolbar {
            // The trailing corner. Nothing goes in the middle: a centered
            // item pulls the items after it in beside it. The All Games /
            // Installed switch is in the library's own bar instead.
            ToolbarItem(placement: .automatic) {
                DownloadsToolbarButton()
                    .environmentObject(depotController)
                    .environmentObject(downloads)
            }
            ToolbarItem(placement: .automatic) {
                SteamAccountMenu()
            }
        }
        // On the next turn of the run loop: when a shortcut launches BEER
        // the link is waiting before the first frame, and opening the game
        // page mid-layout sends the window's toolbar into a layout loop
        // (crash). A game page shows whatever the filter is.
        .onReceive(GameLinkRouter.shared.$requestedAppID.receive(on: DispatchQueue.main)) { appID in
            guard let appID else { return }
            GameLinkRouter.shared.requestedAppID = nil
            selectedGameAppID = appID
        }
        .task {
            depotController.load()
            goldberg.refresh()
            graphicsTranslator.refresh()
        }
        // A drive plugged in, ejected or renamed: games on it follow, a move
        // it interrupted is finished or undone, and games on it that aren't in
        // BEER are offered. Also runs once when the shell appears.
        .onReceive(drives.$drives) { _ in
            Task { await drivesChanged() }
        }
        // Downloads paused before BEER last quit. The bottles load after
        // this view appears, and a row already showing is left alone.
        .onReceive(store.$bottles) { downloads.restorePaused(from: $0) }
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
