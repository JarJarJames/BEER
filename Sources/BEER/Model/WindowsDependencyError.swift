import Foundation

enum WindowsDependencyError: LocalizedError {
    case bottleBusy
    case unofficialSource(String)
    case downloadFailed(String)
    case checksumMismatch(file: String, expected: String, actual: String)
    case installerFailed(file: String, exitCode: Int32?)
    case notDetectedAfterInstall(String)

    var errorDescription: String? {
        switch self {
        case .bottleBusy:
            "This bottle is busy. Quit the game (or Stop Processes) before installing dependencies."
        case .unofficialSource(let host):
            "Refusing to download from \(host): only Microsoft's own servers are allowed."
        case .downloadFailed(let file):
            "Downloading \(file) from Microsoft failed."
        case .checksumMismatch(let file, let expected, let actual):
            "\(file) failed its SHA-256 check (expected \(expected), got \(actual)). It was deleted and not run."
        case .installerFailed(let file, let exitCode):
            exitCode.map { "\(file) exited with code \($0). The bottle's log has the installer output." }
                ?? "\(file) could not be started in this bottle."
        case .notDetectedAfterInstall(let title):
            "\(title) reported success, but its DLLs aren't in the bottle. The bottle's log has the installer output."
        }
    }
}
