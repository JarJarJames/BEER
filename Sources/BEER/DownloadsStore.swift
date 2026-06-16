import Foundation

// Tracks active and recent game installs. The Downloads pane reads from
// here; the game detail view reads its own entry to show install progress
// inline. Lives in memory only — finished installs persist via the
// SteamLibraryStore + BottleStore.
@MainActor
final class DownloadsStore: ObservableObject {
    enum Status: Equatable {
        case queued
        case running(String)        // human-readable phase: "Downloading…", "Verifying…", etc.
        case completed
        case failed(String)
    }

    struct Entry: Identifiable, Equatable {
        let id: Int        // appID
        var name: String
        var bottleID: UUID
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

    @Published private(set) var entries: [Entry] = []

    var active: [Entry] { entries.filter(\.isActive) }
    var recent: [Entry] { entries.filter { !$0.isActive }.sorted { $0.startedAt > $1.startedAt } }

    func entry(for appID: Int) -> Entry? {
        entries.first { $0.id == appID }
    }

    func start(appID: Int, name: String, bottleID: UUID) {
        if let idx = entries.firstIndex(where: { $0.id == appID }) {
            entries[idx].status = .running("Connecting…")
            entries[idx].fraction = 0
            entries[idx].startedAt = Date()
            entries[idx].logTail = []
        } else {
            entries.insert(
                Entry(id: appID, name: name, bottleID: bottleID,
                      status: .running("Connecting…"),
                      fraction: 0, downloadedBytes: nil, totalBytes: nil,
                      logTail: [], startedAt: Date()),
                at: 0
            )
        }
    }

    func append(appID: Int, log: String) {
        guard let idx = entries.firstIndex(where: { $0.id == appID }) else { return }
        entries[idx].logTail.append(log)
        if entries[idx].logTail.count > 80 { entries[idx].logTail.removeFirst() }
    }

    func setStatus(appID: Int, phase: String) {
        guard let idx = entries.firstIndex(where: { $0.id == appID }) else { return }
        entries[idx].status = .running(phase)
    }

    func setProgress(appID: Int, fraction: Double, downloaded: Int64?, total: Int64?) {
        guard let idx = entries.firstIndex(where: { $0.id == appID }) else { return }
        entries[idx].fraction = fraction
        if let downloaded { entries[idx].downloadedBytes = downloaded }
        if let total, total > 0 { entries[idx].totalBytes = total }
    }

    func complete(appID: Int) {
        guard let idx = entries.firstIndex(where: { $0.id == appID }) else { return }
        entries[idx].status = .completed
        entries[idx].fraction = 1
    }

    func fail(appID: Int, reason: String) {
        guard let idx = entries.firstIndex(where: { $0.id == appID }) else { return }
        entries[idx].status = .failed(reason)
    }

    func remove(appID: Int) {
        entries.removeAll { $0.id == appID }
    }
}
