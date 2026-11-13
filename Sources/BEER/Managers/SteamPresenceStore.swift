import Foundation
import SwiftUI

// What BEER asserts to Steam in real time — the status the user picked, which
// game is running, and the play time that comes back when it stops — on
// BEER's one Steam session (`SteamSessionHost`), the same logon every other
// Steam call uses.

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
    private var session: SteamSessionHost?
    private let inbox = PresenceInbox()

    // MARK: - Lifecycle

    func load() {
        guard let data = try? Data(contentsOf: AppPaths.presenceStateURL),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return }
        desiredState = stored.desiredState
    }

    /// Bring the session up. Safe to call repeatedly; a live session is kept.
    func start(auth: SteamAuthStore) async {
        guard session == nil, let account = auth.account, !auth.sessionExpired else { return }

        do {
            let shared = try client.session(account: account.accountName, refreshToken: account.refreshToken)
            shared.listen { [inbox] obj in inbox.accept(obj) }
            session = shared
            // The session stays out of Friends until it's told a status, and
            // Steam won't show a game for a session that isn't in Friends.
            try shared.sendPresence("state \(desiredState.rawValue)")
            isConnected = true
            pump()
        } catch {
            lastError = "Couldn't connect to Steam: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
        }
    }

    /// End the session: on sign-out.
    func stop() async {
        guard session != nil else { return }
        session = nil
        isConnected = false
        persona = nil
        await client.endSession()
        PlaySessionRegistry.clear()
    }

    // MARK: - Commands

    func setState(_ state: SteamPersonaState) {
        desiredState = state
        persist()
        try? session?.sendPresence("state \(state.rawValue)")
    }

    func beginPlaying(appID: Int) {
        try? session?.sendPresence("play \(appID)")
        setCurrentApp(appID)
    }

    /// Stop announcing, and hand back the app's new total once Steam has
    /// credited the session. Nil if there is no session, or Steam had not
    /// caught up within the timeout.
    func stopPlaying(appID: Int) async -> Int? {
        guard let session else { return nil }
        inbox.clearPlaytime()
        try? session.sendPresence("stop")

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
            while let self, let session = self.session {
                if let update = self.inbox.takePersona() { self.apply(update) }
                if let failure = self.inbox.takeError() { self.lastError = failure }

                // The session ending means Steam refused or dropped it. Reflect
                // that instead of leaving the UI claiming a status nobody is
                // asserting. Nothing here restarts it: the next thing that needs
                // Steam (a play, a sync, a refresh) does, once, and a refused
                // token or a rate limit is never retried in a loop.
                let running = session.isRunning
                if running != self.isConnected {
                    self.isConnected = running
                    if running {
                        if self.lastError == Self.lostSession { self.lastError = nil }
                    } else {
                        // Unless the helper said why, the account bar would keep
                        // looking fine while games go unannounced and uncounted.
                        if self.lastError == nil { self.lastError = Self.lostSession }
                        self.persona = nil
                        PlaySessionRegistry.clear()
                    }
                }
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }
    }

    private static let lostSession =
        "Lost the Steam session, so play time isn't being counted. BEER reconnects the next time it needs Steam."

    private func apply(_ update: PresenceInbox.PersonaUpdate) {
        persona = SteamPersona(
            name: update.name,
            state: SteamPersonaState(rawValue: update.state) ?? persona?.state ?? desiredState,
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
