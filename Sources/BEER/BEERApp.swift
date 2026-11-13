import AppKit
import SwiftUI

@main
struct BEERApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = BottleStore()
    @StateObject private var detector = ToolchainDetector()
    @StateObject private var runtimeInstaller = RuntimeInstaller()
    @StateObject private var library = SteamLibraryStore()
    @StateObject private var depotDownloader = DepotDownloaderInstaller()
    @StateObject private var cloudAuth = SteamAuthStore()
    @StateObject private var presence = SteamPresenceStore()
    @StateObject private var drives = InstallVolumeMonitor()
    @StateObject private var mover = GameMover()
    /// Here rather than in the main window: the Settings window's Runtimes
    /// tab needs it too.
    @StateObject private var graphicsTranslator = GraphicsTranslatorInstaller()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(detector)
                .environmentObject(runtimeInstaller)
                .environmentObject(library)
                .environmentObject(depotDownloader)
                .environmentObject(cloudAuth)
                .environmentObject(presence)
                .environmentObject(drives)
                .environmentObject(mover)
                .environmentObject(graphicsTranslator)
                .preferredColorScheme(.dark)
                .frame(minWidth: 1100, minHeight: 720)
                .task {
                    // Starts listening for achievement unlocks so the
                    // floating toast window (separate from this one, so it
                    // stays visible over the game) is armed before anything
                    // could post to it.
                    AchievementOverlayWindow.shared.activate()
                    await store.load()
                    // Games on a drive renamed while BEER was closed follow
                    // it, and folders from before markers get one.
                    store.volumes = drives.current
                    drives.start()
                    await store.followRenamedDrives()
                    await store.renameFoldersWineCannotOpen()
                    store.writeMissingFolderMarkers()
                    await detector.refresh()
                    depotDownloader.refresh()
                    library.load()
                    library.relinkInstalledGames(bottles: store.bottles)
                    cloudAuth.load()
                    presence.load()
                    // If a previous run died mid-game, stop any helper still
                    // telling Steam we're playing.
                    await PlaySessionRegistry.sweepOrphans()
                    // Older builds kept every save backup forever; offer once
                    // to apply the retention limit to what's already there.
                    await CloudSaveBackupCleanup.offerIfNeeded()
                    // Retry any achievement unlocks that couldn't reach Steam
                    // last time (offline, expired session, etc).
                    if let account = cloudAuth.account, !cloudAuth.sessionExpired {
                        await AchievementSyncQueue.retryAll(
                            steamID64: account.steamID64,
                            account: account.accountName,
                            refreshToken: account.refreshToken
                        )
                    }
                }
                // While a game (or any Wine command) runs, library art keeps
                // as little memory as it can, leaving it to the game.
                .onChange(of: store.activeBottleIDs.isEmpty, initial: true) { _, idle in
                    GameArtStore.shared.setGameRunning(!idle)
                }
                // A runtime downloaded or moved while BEER is open: bottles
                // whose runtime's files moved follow them.
                .onChange(of: detector.candidates) {
                    Task { await store.relinkMovedRuntimes() }
                }
        }
        .windowStyle(.titleBar)

        Settings {
            SettingsView()
                .environmentObject(detector)
                .environmentObject(runtimeInstaller)
                .environmentObject(graphicsTranslator)
                .preferredColorScheme(.dark)
        }
    }
}
