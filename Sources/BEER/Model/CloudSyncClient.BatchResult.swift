import Foundation

extension CloudSyncClient {
    /// What one batch produced: the per-file outcomes, plus whatever the helper
    /// said on stderr. Those notes used to be dropped on the floor, which is how
    /// a downloader that silently wrote the wrong bytes still read as a clean
    /// sync — they now land in the app's sync log.
    struct BatchResult { let ops: [BatchOp]; let notes: [String] }
}
