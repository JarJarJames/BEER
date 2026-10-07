import AppKit
import SwiftUI
import Combine
import AchievementUI

/// A tiny event bus for "an achievement just unlocked" toasts. One shared
/// instance so any `AchievementWatcher` (there is one per running game) can
/// post to it without needing a view hierarchy reference.
@MainActor
final class AchievementToastCenter: ObservableObject {
    static let shared = AchievementToastCenter()

    @Published private(set) var current: AchievementDisplayInfo?
    private var queue: [AchievementDisplayInfo] = []
    private var dismissTask: Task<Void, Never>?

    func post(_ achievements: [AchievementDisplayInfo]) {
        queue.append(contentsOf: achievements)
        advanceIfNeeded()
    }

    private func advanceIfNeeded() {
        guard current == nil, !queue.isEmpty else { return }
        current = queue.removeFirst()
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            guard !Task.isCancelled else { return }
            self?.current = nil
            self?.advanceIfNeeded()
        }
    }
}

/// Shows achievement toasts in their own borderless, always-on-top window,
/// separate from BEER's main window.
///
/// A toast mounted inside BEER's own SwiftUI view hierarchy is invisible
/// exactly when it matters: while playing, the game's Wine window has focus
/// and covers BEER entirely. Steam's own achievement popups work the same
/// way — a floating overlay window, not something drawn inside a specific
/// app window — so this does the same: a transparent `NSWindow` at
/// `.floating` level, click-through (`ignoresMouseEvents`), pinned to the
/// screen's top-right corner, shown/hidden by observing
/// `AchievementToastCenter` directly rather than living in any view tree.
@MainActor
final class AchievementOverlayWindow {
    static let shared = AchievementOverlayWindow()

    private var window: NSWindow?
    private var cancellable: AnyCancellable?

    private init() {
        cancellable = AchievementToastCenter.shared.$current
            .receive(on: RunLoop.main)
            .sink { [weak self] achievement in
                if let achievement {
                    self?.show(achievement)
                } else {
                    self?.hide()
                }
            }
    }

    /// No-op beyond triggering `shared`'s lazy init — call once at app
    /// launch so the subscription above is actually listening.
    func activate() {}

    private func show(_ achievement: AchievementDisplayInfo) {
        let panel = window ?? makeWindow()
        window = panel
        panel.contentView = NSHostingView(rootView: AchievementToastContent(achievement: achievement))
        panel.setContentSize(NSSize(width: 320, height: 64))
        position(panel)
        panel.orderFrontRegardless()
        playUnlockSound()
    }

    /// A fresh `NSSound` per play, not one reused instance — reusing one
    /// instance across rapid unlocks (several achievements landing in the
    /// same debounce window) makes overlapping plays cut each other off.
    private func playUnlockSound() {
        guard let url = Bundle.module.url(forResource: "achievement-unlock", withExtension: "mp3"),
              let sound = NSSound(contentsOf: url, byReference: false)
        else { return }
        sound.play()
    }

    private func hide() {
        window?.orderOut(nil)
    }

    private func makeWindow() -> NSWindow {
        let panel = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 64),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        // .floating sits above normal app windows, including a game's Wine
        // window, without needing to be the key/active app. It won't cross
        // into a genuine macOS fullscreen Space — games that use that
        // (rather than the borderless/windowed modes this app otherwise
        // uses) won't show the toast, which is a known limit of a
        // window-level overlay rather than a rendering hook into the game.
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        return panel
    }

    private func position(_ panel: NSWindow) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let origin = CGPoint(x: visible.maxX - size.width - 24, y: visible.maxY - size.height - 24)
        panel.setFrameOrigin(origin)
    }
}
