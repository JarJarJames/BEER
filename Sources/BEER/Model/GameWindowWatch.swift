import Foundation

/// How `BottleStore` watches for a starting game's first window. Tests swap in
/// a fake check and shorter times.
struct GameWindowWatch {
    /// Whether the bottle with this prefix has a window on screen.
    var isShown: @MainActor (URL) -> Bool
    var pollInterval: Duration
    /// When the status adds the "Wine can be slow" hint.
    var slowAfter: Duration

    static var live: GameWindowWatch {
        GameWindowWatch(
            isShown: { WineWindowProbe.hasWindow(inPrefix: $0) },
            pollInterval: LaunchStatusLimits.windowPollInterval,
            slowAfter: LaunchStatusLimits.slowStartAfter
        )
    }
}
