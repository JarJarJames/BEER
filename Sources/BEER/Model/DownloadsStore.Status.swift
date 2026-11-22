import Foundation

extension DownloadsStore {
    enum Status: Equatable {
        case queued
        case running(String)        // human-readable phase: "Downloading…", "Verifying…", etc.
        case pausing                // Pause pressed; DepotDownloader hasn't exited yet
        case cancelling             // Cancel pressed; its files go once DepotDownloader has exited
        case paused
        case completed
        case failed(String)
    }
}
