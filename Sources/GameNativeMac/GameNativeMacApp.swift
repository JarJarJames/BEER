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
struct GameNativeMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = BottleStore()
    @StateObject private var detector = ToolchainDetector()
    @StateObject private var runtimeInstaller = RuntimeInstaller()
    @StateObject private var library = SteamLibraryStore()
    @StateObject private var depotDownloader = DepotDownloaderInstaller()
    @StateObject private var depotCtl = DepotDownloaderController()
    @StateObject private var downloads = DownloadsStore()
    @StateObject private var goldberg = GoldbergInstaller()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(detector)
                .environmentObject(runtimeInstaller)
                .environmentObject(library)
                .environmentObject(depotDownloader)
                .environmentObject(depotCtl)
                .environmentObject(downloads)
                .environmentObject(goldberg)
                .preferredColorScheme(.dark)
                .frame(minWidth: 1100, minHeight: 720)
                .task {
                    await store.load()
                    await detector.refresh()
                    depotDownloader.refresh()
                    library.load()
                    depotCtl.load()
                    goldberg.refresh()
                }
        }
        .windowStyle(.titleBar)
    }
}
