import Foundation

/// A game download stopped with Pause, as its bottle remembers it.
struct PausedDownload: Codable, Hashable {
    /// How far along it was, for the Downloads row after a relaunch.
    var fraction: Double
    var pausedAt: Date
}
