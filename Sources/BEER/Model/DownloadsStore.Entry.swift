import Foundation

extension DownloadsStore {
    struct Entry: Identifiable, Equatable {
        let id: Int        // appID — a DLC has its own, distinct from its game's
        var name: String
        var bottleID: UUID
        /// The game this belongs to, when the entry is a DLC. nil for a game.
        var parentAppID: Int?
        var status: Status
        var fraction: Double          // 0...1
        var downloadedBytes: Int64?
        var totalBytes: Int64?
        var logTail: [String]         // last N lines for inline display
        var startedAt: Date

        var isActive: Bool {
            switch status {
            case .queued, .running: return true
            default: return false
            }
        }

        var phaseText: String {
            switch status {
            case .queued: return "Queued"
            case .running(let phase): return phase
            case .completed: return "Installed"
            case .failed(let reason): return reason
            }
        }
    }
}
