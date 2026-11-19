import Foundation

extension BottleStore {
    /// What a Play click runs, in order. `runLaunch` publishes the bottle's
    /// launch phase around each step; tests pass fakes.
    struct LaunchSteps {
        /// The prefix, Steam's launch config, the client loader and the
        /// graphics translator. Throwing stops the launch on the error.
        var setUpWine: @MainActor () async throws -> Void
        /// The pre-launch save pull, or nil when there's nothing to sync (a
        /// non-Steam game, or Steam not connected). False stops the launch
        /// without an error: a prompt has taken over.
        var syncSaves: (@MainActor () async -> Bool)?
        /// Redistributables, controllers and display mode, just before the game.
        var prepareGame: @MainActor () async throws -> Void
        /// Runs the game until its Wine session ends. The game command's exit
        /// code, or nil if it never ran.
        var runGame: @MainActor () async -> Int32?
        /// After the session: presence, play time, achievements, the save push.
        /// Runs only if `runGame` did.
        var afterPlay: @MainActor () async -> Void
    }
}
