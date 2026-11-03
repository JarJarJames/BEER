import AppKit
import SwiftUI

// Force the app to the foreground and grab keyboard focus on launch. Without
// this, a SwiftUI app launched via `swift run` (and sometimes even via the
// .app bundle on macOS 14+) loads in the background and text fields never
// see key events.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Game shortcuts open `beer://` links. Taking the URL event here, before
    /// SwiftUI sees it, keeps it from opening a new window for each link
    /// (two windows when the link is what launched the app).
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLEvent(_:replyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc private func handleURLEvent(_ event: NSAppleEventDescriptor, replyEvent: NSAppleEventDescriptor) {
        guard let text = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: text) else { return }
        // Apple events arrive on the main thread.
        MainActor.assumeIsolated {
            GameLinkRouter.shared.open(url)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

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
