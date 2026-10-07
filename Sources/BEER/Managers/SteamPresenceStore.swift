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
