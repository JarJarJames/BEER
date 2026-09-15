import Foundation
import SwiftUI

// BEER's live Steam session.
//
// One helper process, logged on for as long as the app is open, owns everything
// that has to be asserted to Steam in real time: the account's online status,
// which game is running, and the play time that comes back when it stops.
//
// It is deliberately *one* session. Steam resolves both persona state and
// games-played as last-writer-wins across an account's logons, so a second
// session opened just for gameplay would fight this one — and a session that
// never sets its persona online is ignored outright, which is why a game
// launched by BEER used to leave no trace on Steam at all.

/// The four states Steam's own status menu offers.
enum SteamPersonaState: String, Codable, CaseIterable, Identifiable {
    case online = "Online"
    case away = "Away"
    case invisible = "Invisible"
    case offline = "Offline"

    var id: String { rawValue }
    var label: String { rawValue }

    /// The explanatory line Steam shows under the non-obvious options.
    var caption: String? {
        switch self {
        case .invisible: return "Appear offline, but you can still chat"
        case .offline: return "Sign out of Friends & Chat"
        default: return nil
        }
    }

    var tint: Color {
        switch self {
        case .online: return .green
        case .away: return .yellow
        case .invisible, .offline: return .secondary
        }
    }
}

/// Steam's own view of the signed-in account, pushed by the live session.
struct SteamPersona: Equatable {
    var name: String
    var state: SteamPersonaState
    var avatarHash: String?
    /// The app Steam currently believes this account is playing, if any.
    var currentAppID: Int?

    /// Steam serves a zeroed hash for accounts with no custom avatar.
    var avatarURL: URL? {
        guard let hash = avatarHash, !hash.isEmpty,
              hash.contains(where: { $0 != "0" }) else { return nil }
        return URL(string: "https://avatars.steamstatic.com/\(hash)_full.jpg")
    }
}

@MainActor
final class SteamPresenceStore: ObservableObject {
    /// Nil until Steam has told us who we are.
    @Published private(set) var persona: SteamPersona?
    @Published private(set) var isConnected = false
    /// The status the user picked. Applied on every (re)connect, so it survives
    /// restarts and outlives any one session.
    @Published private(set) var desiredState: SteamPersonaState = .online
    @Published var lastError: String?

    private let client = CloudSyncClient()
    private var process: SpawnedProcess?
    private let inbox = PresenceInbox()

    // MARK: - Lifecycle

    func load() {
        guard let data = try? Data(contentsOf: AppPaths.presenceStateURL),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return }
        desiredState = stored.desiredState
    }

    /// Bring the session up. Safe to call repeatedly; a live session is kept.
    func start(auth: SteamAuthStore) async {
        guard process == nil, let account = auth.account, !auth.sessionExpired else { return }

        do {
            let handle = try client.startPresence(
                steamID64: account.steamID64,
                account: account.accountName,
                refreshToken: account.refreshToken,
                onLine: { [inbox] obj in inbox.accept(obj) }
            )
            process = handle
            isConnected = true
            // A fresh logon's persona is Offline and Steam will not broadcast a
            // game for an offline persona, so this has to go out first.
            handle.send("state \(desiredState.rawValue)")
            pump()
        } catch {
            lastError = "Couldn't connect to Steam: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
        }
    }

    func stop() async {
        guard let process else { return }
        self.process = nil
        isConnected = false
        persona = nil
        await process.end()
        PlaySessionRegistry.clear()
    }

    // MARK: - Commands

    func setState(_ state: SteamPersonaState) {
        desiredState = state
        persist()
        process?.send("state \(state.rawValue)")
    }

    func beginPlaying(appID: Int) {
        process?.send("play \(appID)")
        setCurrentApp(appID)
    }

    /// Stop announcing, and hand back the app's new total once Steam has
    /// credited the session. Nil if there is no session, or Steam had not
    /// caught up within the timeout.
    func stopPlaying(appID: Int) async -> Int? {
        guard let process else { return nil }
        inbox.clearPlaytime()
        process.send("stop")

        let deadline = Date().addingTimeInterval(15)
        while inbox.playtime == nil, Date() < deadline {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        // Reflect the stop straight away. The announcement is already
        // retracted, and Steam only pushes a persona update when something it
        // considers changed — waiting on one risks the UI claiming a game is
        // still running long after it closed.
        setCurrentApp(nil)

        guard let report = inbox.playtime, report.appID == appID else { return nil }
        return report.minutes
    }

    private func setCurrentApp(_ appID: Int?) {
        guard var current = persona else { return }
        current.currentAppID = appID
        persona = current
    }

    // MARK: - Incoming

    /// Drain what the helper has reported. The output handler runs off the main
    /// actor, so it parks messages in a lock-guarded inbox and this moves them
    /// onto published state.
    private func pump() {
        Task { [weak self] in
            while let self, let process = self.process {
                if let update = self.inbox.takePersona() { self.apply(update) }
                if let failure = self.inbox.takeError() { self.lastError = failure }

                // The helper exiting on its own means Steam refused or dropped
                // the session. Reflect that instead of leaving the UI claiming
                // a status nobody is asserting — and don't respawn in a loop,
                // which against a rejected token would hammer Steam's logon
                // rate limit.
                if !process.isRunning {
                    self.process = nil
                    self.isConnected = false
                    self.persona = nil
                    PlaySessionRegistry.clear()
                    break
                }
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }
    }

    private func apply(_ update: PresenceInbox.PersonaUpdate) {
        persona = SteamPersona(
            name: update.name,
            state: SteamPersonaState(rawValue: update.state) ?? desiredState,
            avatarHash: update.avatarHash,
            currentAppID: update.appID == 0 ? nil : update.appID
        )
    }

    private func persist() {
        try? AppPaths.ensureBaseDirectories()
        guard let data = try? JSONEncoder().encode(Stored(desiredState: desiredState)) else { return }
        try? data.write(to: AppPaths.presenceStateURL, options: .atomic)
    }

    private struct Stored: Codable { let desiredState: SteamPersonaState }
}

/// Lock-guarded drop box between the helper's output handler (off the main
/// actor) and the store (on it).
final class PresenceInbox: @unchecked Sendable {
    struct PersonaUpdate { let name: String; let state: String; let avatarHash: String?; let appID: Int }
    struct PlaytimeReport { let appID: Int; let minutes: Int }

    private let lock = NSLock()
    private var _persona: PersonaUpdate?
    private var _error: String?
    private var _playtime: PlaytimeReport?

    func accept(_ obj: [String: Any]) {
        lock.lock(); defer { lock.unlock() }
        if let name = obj["persona_name"] as? String {
            _persona = PersonaUpdate(
                name: name,
                state: (obj["persona_state"] as? String) ?? "Online",
                avatarHash: obj["avatar_hash"] as? String,
                appID: (obj["presence_appid"] as? NSNumber)?.intValue ?? 0
            )
        }
        if let stopped = (obj["stopped"] as? NSNumber)?.intValue {
            _playtime = PlaytimeReport(
                appID: stopped,
                minutes: (obj["playtime_forever"] as? NSNumber)?.intValue ?? -1
            )
        }
        if let err = obj["error"] as? String { _error = err }
    }

    var playtime: PlaytimeReport? { lock.lock(); defer { lock.unlock() }; return _playtime }
    func clearPlaytime() { lock.lock(); _playtime = nil; lock.unlock() }

    func takePersona() -> PersonaUpdate? {
        lock.lock(); defer { lock.unlock() }
        defer { _persona = nil }
        return _persona
    }

    func takeError() -> String? {
        lock.lock(); defer { lock.unlock() }
        defer { _error = nil }
        return _error
    }
}

/// Remembers the PID of the live presence helper so a BEER that died without
/// unwinding can clean it up next launch.
///
/// Belt-and-braces: the helper already exits when BEER's end of its stdin pipe
/// closes, which covers even a force quit. This catches the remainder — a
/// helper wedged on a dead socket, say.
enum PlaySessionRegistry {
    private struct Record: Codable { let pid: Int32 }

    static func record(pid: Int32) {
        try? AppPaths.ensureBaseDirectories()
        guard let data = try? JSONEncoder().encode(Record(pid: pid)) else { return }
        try? data.write(to: AppPaths.playSessionStateURL, options: .atomic)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: AppPaths.playSessionStateURL)
    }

    /// Stop a helper left behind by a previous run. Confirms the PID still
    /// belongs to a CloudSync process before signalling it — PIDs get recycled,
    /// and killing an unrelated process would be far worse than leaving a stale
    /// status behind.
    static func sweepOrphans() async {
        guard let data = try? Data(contentsOf: AppPaths.playSessionStateURL),
              let record = try? JSONDecoder().decode(Record.self, from: data) else { return }
        clear()

        guard let result = try? await ShellRunner.run(
            executable: "/bin/ps",
            arguments: ["-p", "\(record.pid)", "-o", "comm="],
            environment: [:],
            outputHandler: { _ in }
        ), result.exitCode == 0, result.output.contains("CloudSync") else { return }

        kill(record.pid, SIGTERM)
    }
}

/// Everything the presence helper prints, captured to a file.
///
/// The session outlives every call that talks to it, so its output has nowhere
/// else to go — and without this a presence or play-time problem leaves no
/// trace at all to debug from.
enum PlaySessionLog {
    private static let lock = NSLock()

    static func start() {
        lock.withLock {
            try? AppPaths.ensureBaseDirectories()
            let header = "=== presence session — \(Date()) ===\n"
            try? header.write(to: AppPaths.playSessionLogURL, atomically: true, encoding: .utf8)
        }
    }

    static func append(_ text: String) {
        lock.withLock {
            let stamped = text
                .split(separator: "\n", omittingEmptySubsequences: true)
                .map { "\(Date().formatted(date: .omitted, time: .standard))  \($0)\n" }
                .joined()
            guard !stamped.isEmpty, let data = stamped.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: AppPaths.playSessionLogURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? stamped.write(to: AppPaths.playSessionLogURL, atomically: true, encoding: .utf8)
            }
        }
    }
}
