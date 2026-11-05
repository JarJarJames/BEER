import AppKit
import SwiftUI

/// Put behind a ScrollView's content to keep its scroll bar floating over the
/// content, as it does with a trackpad, even while a mouse is connected.
///
/// A mouse makes macOS give the scroll bar its own strip, narrowing the
/// content whenever the bar shows. The game page's height follows its width
/// (the banner scales with it), so near the height where the bar appears,
/// showing it made the page short enough to hide it again, and back, forever:
/// the app froze. A floating bar never changes the width.
struct OverlayScrollers: NSViewRepresentable {
    func makeNSView(context: Context) -> OverlayScrollersView { OverlayScrollersView() }
    func updateNSView(_ nsView: OverlayScrollersView, context: Context) { nsView.apply() }
}

final class OverlayScrollersView: NSView {
    private var observer: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        guard window != nil else { return }
        // AppKit puts every scroll view back to the system style when a mouse
        // is plugged in or the setting changes, so float it again after.
        observer = NotificationCenter.default.addObserver(
            forName: NSScroller.preferredScrollerStyleDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.apply() } }
        apply()
    }

    override func layout() {
        super.layout()
        apply()
    }

    func apply() {
        guard let scroll = enclosingScrollView, scroll.scrollerStyle != .overlay else { return }
        scroll.scrollerStyle = .overlay
    }
}
