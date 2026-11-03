import AppKit
import SwiftUI

/// Put behind a log's lines, inside its ScrollView, to keep the newest line
/// in view until the player scrolls up (see `LogFollow`).
///
/// Watches the AppKit scroll view directly: on macOS 14 SwiftUI doesn't say
/// when a scroll view moves, and a position read inside it only updated when
/// the end of the log came in or out of layout, so scrolling back down to the
/// end never turned following back on.
struct LogFollower: NSViewRepresentable {
    func makeNSView(context: Context) -> LogFollowerView { LogFollowerView() }
    func updateNSView(_ nsView: LogFollowerView, context: Context) {}
}

final class LogFollowerView: NSView {
    private let follow = LogFollow()
    private var observers: [NSObjectProtocol] = []

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        guard window != nil, let scroll = enclosingScrollView, let document = scroll.documentView else { return }

        scroll.contentView.postsBoundsChangedNotifications = true
        document.postsFrameChangedNotifications = true
        // Posted on the main thread, and handled there without a queue so a
        // scroll is read before anything else moves it.
        observers = [
            NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: nil
            ) { [weak self] _ in MainActor.assumeIsolated { self?.scrolled() } },
            NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification, object: document, queue: nil
            ) { [weak self] _ in MainActor.assumeIsolated { self?.grew() } }
        ]
        // Opening the log shows its end.
        _ = follow.contentGrew()
        scrollToEndSoon()
    }

    private func scrolled() {
        guard let scroll = enclosingScrollView, let document = scroll.documentView else { return }
        let shown = scroll.documentVisibleRect
        let distance = document.isFlipped ? document.bounds.maxY - shown.maxY : shown.minY - document.bounds.minY
        follow.scrolled(distanceFromEnd: distance)
    }

    private func grew() {
        if follow.contentGrew() { scrollToEndSoon() }
    }

    /// On the next turn of the run loop: the frame change arrives mid-layout,
    /// and scrolling from inside a layout pass is how layout loops start.
    private func scrollToEndSoon() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let document = enclosingScrollView?.documentView else { return }
            let end = document.isFlipped ? document.bounds.maxY - 1 : document.bounds.minY
            document.scrollToVisible(NSRect(x: document.bounds.minX, y: end, width: 1, height: 1))
            follow.caughtUp()
        }
    }
}
