import Foundation

/// Why a Play click stopped before or while the game started. Its description
/// is what the launch status shows.
enum LaunchError: LocalizedError, Equatable {
    /// wineboot didn't finish setting up the prefix.
    case wineSetupFailed
    case noExecutable
    case clientLoader(String)
    case graphicsTranslator(name: String, detail: String)
    /// The bottle's runtime is gone; the message names it.
    case runtimeMissing(String)
    /// The game's command never ran.
    case gameDidNotStart
    /// The session ended with an error and no window ever showed.
    case closedBeforeWindow(exitCode: Int32)

    var errorDescription: String? {
        switch self {
        case .wineSetupFailed: return LaunchStatusStrings.wineSetupFailed
        case .noExecutable: return LaunchStatusStrings.noExecutable
        case .clientLoader(let detail): return LaunchStatusStrings.clientLoaderFailed(detail)
        case .graphicsTranslator(let name, let detail): return LaunchStatusStrings.graphicsSetupFailed(name, detail: detail)
        case .runtimeMissing(let message): return message
        case .gameDidNotStart: return LaunchStatusStrings.gameDidNotStart
        case .closedBeforeWindow(let exitCode): return LaunchStatusStrings.closedBeforeWindow(exitCode: exitCode)
        }
    }
}
