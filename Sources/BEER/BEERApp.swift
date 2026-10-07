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
                .preferredColorScheme(.dark)
                .frame(minWidth: 1100, minHeight: 720)
                .task {
                    // Starts listening for achievement unlocks so the
                    // floating toast window (separate from this one, so it
                    // stays visible over the game) is armed before anything
                    // could post to it.
                    AchievementOverlayWindow.shared.activate()
                    await store.load()
                    await detector.refresh()
                    depotDownloader.refresh()
                    library.load()
                    cloudAuth.load()
                    presence.load()
                    // If a previous run died mid-game, stop any helper still
                    // telling Steam we're playing.
                    await PlaySessionRegistry.sweepOrphans()
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
        }
        .windowStyle(.titleBar)
    }
}
