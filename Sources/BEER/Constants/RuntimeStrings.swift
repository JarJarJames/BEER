import Foundation

/// User-facing text that points to the Runtimes tab in Settings.
enum RuntimeStrings {
    static let openRuntimes = "Open Runtimes…"
    static let noRuntime = "No Wine runtime available."
    static func downloadRuntime(size: String) -> String { "Download GPTK (\(size))" }
    static func downloaded(_ progress: ByteProgress) -> String {
        progress.expected > 0
            ? "\(progress.received.fileSizeString) of \(progress.expected.fileSizeString)"
            : progress.received.fileSizeString
    }
    static func runtimeMissing(_ runtime: String) -> String {
        "This game's Wine runtime (\(runtime)) is missing."
    }
    static func runtimeMissingError(_ game: String, runtime: String) -> String {
        "Can't start \(game): its Wine runtime (\(runtime)) is missing. Pick another runtime on the game's page."
    }
    static func runtimeRelinked(_ runtime: String) -> String {
        "The runtime's files moved; now using \(runtime) from its new place."
    }
    static func useRuntime(_ runtime: String) -> String { "Use \(runtime)" }
    static let runtimeRowCaption = "Changing the runtime swaps the Wine build this game runs on. Install other Wine or GPTK versions in Settings → Runtimes."
}
