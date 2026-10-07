import AchievementUI
import Dispatch
import Foundation

// Watches a running game's local Goldberg (gbe_fork) achievement save file
// for new unlocks and syncs them to the real Steam account.
//
// gbe_fork uses the filename `achievements.json` twice, for two different
// things: the static schema BEER writes into `steam_settings/` (see
// GoldbergApplicator), and a separate per-user save-state COPY the running
// game/emulator maintains under `GSE Saves/<appid>/achievements.json`,
// recording each achievement's `earned`/`earned_time`. This watches the
// second one — confirmed by the `earned`/`earned_time` strings actually
// present in the installed gbe_fork binary, since there is no separately
// documented filename for it.
//
// Detection is a live file watch (unlike cloud saves, which only diff a
// before/after fingerprint around the whole play session) so an unlock can
// surface as a toast while the game is still running, matching GameNative's
// Android behaviour. This is new to BEER — there is no other file-watching
// code elsewhere in the app — so it is kept self-contained here rather than
// generalized into a shared utility prematurely.
@MainActor
final class AchievementWatcher {
    private let appID: Int
    private let steamID64: String
    private let account: String
    private let refreshToken: String
    private let unlockFileURL: URL
    private let onUnlock: @MainActor ([AchievementDisplayInfo]) -> Void

    private var displayByName: [String: AchievementDisplayInfo] = [:]
    private var knownUnlocked: Set<String> = []

    private var source: DispatchSourceFileSystemObject?
    private var watchedDescriptor: Int32 = -1
    private var debounceTask: Task<Void, Never>?

    init(
        bottle: Bottle,
        appID: Int,
        installDir: URL,
        steamID64: String,
        account: String,
        refreshToken: String,
        onUnlock: @escaping @MainActor ([AchievementDisplayInfo]) -> Void
    ) {
        self.appID = appID
        self.steamID64 = steamID64
        self.account = account
        self.refreshToken = refreshToken
        self.unlockFileURL = Self.saveStateFile(bottle: bottle, appID: appID)
        self.onUnlock = onUnlock
        for info in GoldbergApplicator.readAchievementsSchema(installDir: installDir) {
            displayByName[info.name] = info
        }
    }

    static func saveStateFile(bottle: Bottle, appID: Int) -> URL {
        // The Wine username is pinned to "crossover" everywhere in BEER (see
        // CLAUDE.md) so this path is stable across bottles/Wine switches.
        AppPaths.prefixURL(for: bottle)
            .appendingPathComponent("drive_c/users/crossover/AppData/Roaming/GSE Saves", isDirectory: true)
            .appendingPathComponent(String(appID), isDirectory: true)
            .appendingPathComponent("achievements.json", isDirectory: false)
    }

    /// Begin watching. Seeds `knownUnlocked` from whatever is already on disk
    /// so a relaunch never reports achievements the player already has as
    /// "new".
    func start() {
        knownUnlocked = Set(Self.parseEarned(at: unlockFileURL).keys)
        watchParentDirectory()
    }

    func stop() {
        debounceTask?.cancel()
        debounceTask = nil
        source?.cancel()
        source = nil
    }

    /// One last check right after the game exits, so an unlock that landed in
    /// the last debounce window before the process died isn't lost.
    func finalCheck() async {
        await checkForNewUnlocks()
    }

    // MARK: - Watching

    /// Watches the *directory*, not the file: gbe_fork may not have created
    /// the save file yet when the game launches, and a DispatchSource on a
    /// path that doesn't exist never fires. The directory always exists once
    /// created here, so this reliably sees the file appear or change.
    private func watchParentDirectory() {
        let dir = unlockFileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        watchedDescriptor = fd

        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend, .rename], queue: .main)
        src.setEventHandler { [weak self] in self?.scheduleCheck() }
        src.setCancelHandler { [weak self] in
            if let fd = self?.watchedDescriptor, fd >= 0 { close(fd) }
        }
        src.resume()
        source = src
    }

    /// Debounced so a save file written in several small chunks only triggers
    /// one check, shortly after it goes quiet.
    private func scheduleCheck() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.checkForNewUnlocks()
        }
    }

    private func checkForNewUnlocks() async {
        let earned = Self.parseEarned(at: unlockFileURL)
        let newNames = earned.keys.filter { !knownUnlocked.contains($0) }
        guard !newNames.isEmpty else { return }
        knownUnlocked.formUnion(newNames)

        onUnlock(newNames.compactMap { displayByName[$0] })

        do {
            let result = try await CloudSyncClient().pushAchievementUnlocks(
                appID: appID, steamID64: steamID64, unlockedNames: newNames,
                account: account, refreshToken: refreshToken
            )
            if !result.ok {
                AchievementSyncQueue.recordPending(appID: appID, names: newNames)
            }
        } catch {
            AchievementSyncQueue.recordPending(appID: appID, names: newNames)
        }
    }

    /// Parse gbe_fork's per-user achievements save file: an array of
    /// `{"name": "...", "earned": true, "earned_time": 169...}`. Returns
    /// name -> earned_time for every entry with `earned == true`.
    nonisolated static func parseEarned(at url: URL) -> [String: Int] {
        guard let data = try? Data(contentsOf: url),
              let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [:] }
        var result: [String: Int] = [:]
        for entry in entries {
            guard let name = entry["name"] as? String, entry["earned"] as? Bool == true else { continue }
            result[name] = (entry["earned_time"] as? NSNumber)?.intValue ?? 0
        }
        return result
    }
}
