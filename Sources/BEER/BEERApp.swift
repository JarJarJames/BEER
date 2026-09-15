import AppKit
import SwiftUI

// Force the app to the foreground and grab keyboard focus on launch. Without
// this, a SwiftUI app launched via `swift run` (and sometimes even via the
// .app bundle on macOS 14+) loads in the background and text fields never
// see key events.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            for window in NSApp.windows {
                window.makeKeyAndOrderFront(nil)
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct BEERApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = BottleStore()
    @StateObject private var detector = ToolchainDetector()
    @StateObject private var runtimeInstaller = RuntimeInstaller()
    @StateObject private var library = SteamLibraryStore()
    @StateObject private var depotDownloader = DepotDownloaderInstaller()
    @StateObject private var cloudAuth = SteamAuthStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(detector)
                .environmentObject(runtimeInstaller)
                .environmentObject(library)
                .environmentObject(depotDownloader)
                .environmentObject(cloudAuth)
                .preferredColorScheme(.dark)
                .frame(minWidth: 1100, minHeight: 720)
                .task {
                    await store.load()
                    await detector.refresh()
                    depotDownloader.refresh()
                    library.load()
                    cloudAuth.load()
                    // If a previous run died mid-game, stop any helper still
                    // telling Steam we're playing.
                    await PlaySessionRegistry.sweepOrphans()
                }
        }
        .windowStyle(.titleBar)
    }
}
