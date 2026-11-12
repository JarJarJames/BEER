import Foundation

/// How long Pause waits for DepotDownloader to exit before forcing it.
enum DownloadPauseLimits {
    /// Seconds between SIGTERM and SIGKILL. A forced stop loses nothing: on
    /// resume DepotDownloader checks the files on disk and fetches the rest.
    static let stopGraceSeconds: TimeInterval = 5
}
