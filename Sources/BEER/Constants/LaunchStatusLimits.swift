import Foundation

/// Timing for the launch status while a game starts.
enum LaunchStatusLimits {
    /// How often to look for the game's window. Each look reads the process
    /// list once; a second is quick enough to feel immediate.
    static let windowPollInterval: Duration = .seconds(1)
    /// With no window after this long, the status adds that Wine can be slow
    /// and points at the log.
    static let slowStartAfter: Duration = .seconds(60)
}
