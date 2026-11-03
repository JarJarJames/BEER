import Foundation

/// Whether a log panel keeps its newest line in view. It follows from the
/// start, stops when the player scrolls up to read, and follows again once
/// they scroll back to the end.
@MainActor
final class LogFollow {
    private(set) var isFollowing = true
    /// New lines are in but the panel hasn't scrolled to them yet. Scroll
    /// reports in between are the panel catching up, not the player.
    private var catchingUp = false

    /// The panel scrolled and its end is now `distanceFromEnd` below what's
    /// shown.
    func scrolled(distanceFromEnd: CGFloat) {
        guard !catchingUp else { return }
        isFollowing = distanceFromEnd <= LogPanelLayout.atEndTolerance
    }

    /// The log got longer. Returns whether to scroll to its end; call
    /// `caughtUp()` once that's done.
    func contentGrew() -> Bool {
        if isFollowing { catchingUp = true }
        return isFollowing
    }

    func caughtUp() {
        catchingUp = false
    }
}
