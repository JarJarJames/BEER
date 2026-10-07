import AchievementUI
import Dispatch
import Foundation

/// Achievement unlocks that failed to reach Steam (offline, session issue),
/// persisted so they can be retried later instead of silently lost. Mirrors
/// GameNative Android's `pending_achievement_sync.txt`.
enum AchievementSyncQueue {
    private static var fileURL: URL {
        AppPaths.applicationSupport.appendingPathComponent("achievement-pending-sync.json")
    }

    private struct Pending: Codable { var appID: Int; var names: [String] }

    static func recordPending(appID: Int, names: [String]) {
        var all = load()
        if let idx = all.firstIndex(where: { $0.appID == appID }) {
            all[idx].names = Array(Set(all[idx].names).union(names))
        } else {
            all.append(Pending(appID: appID, names: names))
        }
        save(all)
    }

    /// Retry every pending sync. Best-effort: whatever still fails stays
    /// queued for the next opportunity (e.g. the next successful launch).
    static func retryAll(steamID64: String, account: String, refreshToken: String) async {
        var remaining = load()
        guard !remaining.isEmpty else { return }
        let client = CloudSyncClient()
        for pending in load() {
            do {
                let result = try await client.pushAchievementUnlocks(
                    appID: pending.appID, steamID64: steamID64, unlockedNames: pending.names,
                    account: account, refreshToken: refreshToken
                )
                if result.ok {
                    remaining.removeAll { $0.appID == pending.appID }
                }
            } catch {
                continue
            }
        }
        save(remaining)
    }

    private static func load() -> [Pending] {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Pending].self, from: data)
        else { return [] }
        return decoded
    }

    private static func save(_ pending: [Pending]) {
        guard let data = try? JSONEncoder().encode(pending) else { return }
        try? FileManager.default.createDirectory(at: AppPaths.applicationSupport, withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
