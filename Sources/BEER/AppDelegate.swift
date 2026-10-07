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
