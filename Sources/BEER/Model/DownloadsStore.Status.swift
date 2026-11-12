import Foundation

extension DownloadsStore {
    enum Status: Equatable {
        case queued
        case running(String)        // human-readable phase: "Downloading…", "Verifying…", etc.
        case pausing                // Pause pressed; DepotDownloader hasn't exited yet
        case paused
        case completed
        case failed(String)
    }
}
