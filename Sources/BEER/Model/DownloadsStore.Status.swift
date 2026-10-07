import Foundation

extension DownloadsStore {
    enum Status: Equatable {
        case queued
        case running(String)        // human-readable phase: "Downloading…", "Verifying…", etc.
        case completed
        case failed(String)
    }
}
