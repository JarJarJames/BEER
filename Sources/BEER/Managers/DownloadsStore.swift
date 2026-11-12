import Foundation

// Tracks active and recent game installs. The Downloads pane reads from
// here; the game detail view reads its own entry to show install progress
// inline. Lives in memory only — finished installs persist via the
// SteamLibraryStore + BottleStore, and a paused game download via its
// bottle's `pausedDownload` (see `restorePaused`).
@MainActor
final class DownloadsStore: ObservableObject {
    @Published private(set) var entries: [Entry] = []

    var active: [Entry] { entries.filter(\.isActive) }
    /// Running or paused: the Downloads pane's top section.
    var inProgress: [Entry] { entries.filter(\.isInProgress) }
    var recent: [Entry] { entries.filter { !$0.isInProgress }.sorted { $0.startedAt > $1.startedAt } }

    /// How far along the running downloads are together, for the top bar.
    /// Nil when nothing is downloading.
    var overallFraction: Double? {
        let running = active
        guard !running.isEmpty else { return nil }
        return running.map(\.fraction).reduce(0, +) / Double(running.count)
    }

    func entry(for appID: Int) -> Entry? {
        entries.first { $0.id == appID }
    }

    func start(appID: Int, name: String, bottleID: UUID, parentAppID: Int? = nil) {
        if let idx = entries.firstIndex(where: { $0.id == appID }) {
            // A resumed download checks what's on disk first and climbs back
            // from 0; the bar holds where it was paused until it passes that.
            if !entries[idx].isPaused { entries[idx].fraction = 0 }
            entries[idx].status = .running("Connecting…")
            entries[idx].startedAt = Date()
            entries[idx].logTail = []
        } else {
            entries.insert(
                Entry(id: appID, name: name, bottleID: bottleID,
                      parentAppID: parentAppID,
                      status: .running("Connecting…"),
                      fraction: 0, downloadedBytes: nil, totalBytes: nil,
                      logTail: [], startedAt: Date()),
                at: 0
            )
        }
    }

    /// The DepotDownloader event handler for `appID`. Both install paths — a
    /// game and a DLC — funnel their output through this one adapter, so
    /// neither can quietly drop a case (the DLC path used to discard every log
    /// line, leaving failures with nothing to show).
    func consume(appID: Int, completionPhase: String = "Finalizing…") -> @MainActor (DepotDownloaderEvent) -> Void {
        { [weak self] event in
            guard let self else { return }
            switch event {
            case .log(let line):
                self.append(appID: appID, log: line)
            case .status(let phase):
                self.setStatus(appID: appID, phase: phase)
            case .progress(let fraction):
                self.setProgress(appID: appID, fraction: fraction, downloaded: nil, total: nil)
            case .downloadComplete:
                self.setStatus(appID: appID, phase: completionPhase)
            }
        }
    }

    func append(appID: Int, log: String) {
        guard let idx = entries.firstIndex(where: { $0.id == appID }) else { return }
        entries[idx].logTail.append(log)
        if entries[idx].logTail.count > 80 { entries[idx].logTail.removeFirst() }
    }

    /// Ignored once the entry is pausing, paused or done: DepotDownloader's
    /// last lines can arrive after Pause and would otherwise undo it.
    func setStatus(appID: Int, phase: String) {
        guard let idx = entries.firstIndex(where: { $0.id == appID }) else { return }
        switch entries[idx].status {
        case .queued, .running: entries[idx].status = .running(phase)
        default: return
        }
    }

    /// Only moves the bar forward; `start` is what sets it back to 0.
    func setProgress(appID: Int, fraction: Double, downloaded: Int64?, total: Int64?) {
        guard let idx = entries.firstIndex(where: { $0.id == appID }) else { return }
        entries[idx].fraction = max(entries[idx].fraction, fraction)
        if let downloaded { entries[idx].downloadedBytes = downloaded }
        if let total, total > 0 { entries[idx].totalBytes = total }
    }

    func complete(appID: Int) {
        guard let idx = entries.firstIndex(where: { $0.id == appID }) else { return }
        entries[idx].status = .completed
        entries[idx].fraction = 1
    }

    func markPausing(appID: Int) {
        guard let idx = entries.firstIndex(where: { $0.id == appID }) else { return }
        entries[idx].status = .pausing
    }

    /// DepotDownloader has exited; the progress bar stays where it stopped.
    func pause(appID: Int) {
        guard let idx = entries.firstIndex(where: { $0.id == appID }) else { return }
        entries[idx].status = .paused
    }

    /// Rows for game downloads paused before BEER last quit. A game that
    /// already has a row (one started since) keeps it.
    func restorePaused(from bottles: [Bottle]) {
        for bottle in bottles {
            guard let appID = bottle.steamAppID, let paused = bottle.pausedDownload,
                  entry(for: appID) == nil else { continue }
            entries.append(
                Entry(id: appID, name: bottle.steamGameName ?? bottle.name, bottleID: bottle.id,
                      status: .paused, fraction: paused.fraction,
                      downloadedBytes: nil, totalBytes: nil,
                      logTail: [], startedAt: paused.pausedAt)
            )
        }
    }

    func fail(appID: Int, reason: String) {
        guard let idx = entries.firstIndex(where: { $0.id == appID }) else { return }
        entries[idx].status = .failed(reason)
    }

    func remove(appID: Int) {
        entries.removeAll { $0.id == appID }
    }
}
