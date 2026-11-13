import Foundation

/// BEER's one Steam logon.
///
/// A single CloudSync `session` process stays logged on while BEER runs, and
/// every helper command goes to it as a request instead of logging on for
/// itself. Before this, a launch alone logged on three or four times (status,
/// library, update check, achievement retries), and every cloud sync, install
/// check or icon fetch added another. Every extra session on the account is
/// another chance to collide with the user's own Steam clients, and a burst of
/// them gets the account rate-limited.
///
/// Only two things still log on separately: QR sign-in (which connects without
/// logging on) and DepotDownloader, a separate program.
final class SteamSessionHost: @unchecked Sendable {
    // MARK: - One per helper

    // Both guarded by `registryLock`.
    private static let registryLock = NSLock()
    nonisolated(unsafe) private static var hosts: [String: SteamSessionHost] = [:]
    /// The log starts fresh once per app run; a restarted session appends.
    nonisolated(unsafe) private static var hasLoggedThisRun = false

    /// The session for this helper and sign-in, started on first use. A new
    /// token (after a fresh QR sign-in) replaces the old session.
    static func shared(binary: URL, account: String, refreshToken: String, isTest: Bool) -> SteamSessionHost {
        let (host, replaced) = registryLock.withLock { () -> (SteamSessionHost, SteamSessionHost?) in
            if let existing = hosts[binary.path],
               existing.account == account, existing.refreshToken == refreshToken {
                return (existing, nil)
            }
            let fresh = SteamSessionHost(binary: binary, account: account, refreshToken: refreshToken, isTest: isTest)
            let old = hosts.updateValue(fresh, forKey: binary.path)
            return (fresh, old)
        }
        if let replaced { Task { await replaced.end() } }
        return host
    }

    /// End the session for `binary`, if one is running: on sign-out.
    static func end(binary: URL) async {
        let host = registryLock.withLock { hosts.removeValue(forKey: binary.path) }
        await host?.end()
    }

    // MARK: - Session

    private let binary: URL
    private let account: String
    private let refreshToken: String
    /// Tests run a fake helper: nothing is logged to, or recorded in, the
    /// user's own Application Support.
    private let isTest: Bool

    private let lock = NSLock()
    private var process: SpawnedProcess?
    /// Counts processes, so a late exit report from one can't touch the next.
    private var generation = 0
    /// Ended or replaced by a new sign-in: never starts again, so a session
    /// with an old token can't come back.
    private var retired = false
    private var nextID = 1
    private var pending: [Int: Request] = [:]
    /// The logon failure that ended the last process, replayed to requests
    /// instead of logging on again: re-trying a refused token or a rate limit
    /// only makes it worse.
    private var refusal: (reply: [String: Any], until: Date)?
    /// Status lines to re-send when the session restarts.
    private var presenceState: String?
    private var presenceListener: (@Sendable ([String: Any]) -> Void)?

    private struct Request {
        let generation: Int
        let onObject: @Sendable ([String: Any]) -> Void
        let finished: CheckedContinuation<Void, Never>
    }

    private init(binary: URL, account: String, refreshToken: String, isTest: Bool) {
        self.binary = binary
        self.account = account
        self.refreshToken = refreshToken
        self.isTest = isTest
    }

    var isRunning: Bool { lock.withLock { process?.isRunning ?? false } }

    /// Run one helper command (`["enumerate", "--appid", "440"]`) on the
    /// session. `onObject` gets each line it answers with, and the call returns
    /// once it has finished. Starts the session if it isn't running.
    ///
    /// The helper's stderr is shared by everything the session does, so it
    /// goes to `play-session.log`, not to the request: a request's failure
    /// comes back as its own `{"error": …}`.
    func request(
        _ args: [String],
        onObject: @escaping @Sendable ([String: Any]) -> Void
    ) async throws {
        _ = try Self.requestLine(args, id: 0) // a malformed call fails before anything starts
        if let refused = activeRefusal() {
            onObject(refused)
            return
        }
        let process = try ensureStarted()
        await withCheckedContinuation { (finished: CheckedContinuation<Void, Never>) in
            let id: Int? = lock.withLock {
                // The session may have ended since it was started above; its
                // end already failed everything it knew about.
                guard self.process === process else { return nil }
                defer { nextID += 1 }
                pending[nextID] = Request(generation: generation, onObject: onObject, finished: finished)
                return nextID
            }
            guard let id, let line = try? Self.requestLine(args, id: id) else {
                onObject(["error": "BEER's Steam session ended unexpectedly."])
                finished.resume()
                return
            }
            process.send(line)
        }
    }

    /// Send a status or play command (`state Online`, `play 440`, `stop`) and
    /// hand everything the session reports outside a request to `listener`.
    func sendPresence(_ command: String) throws {
        guard activeRefusal() == nil else {
            if command.hasPrefix("state ") { lock.withLock { presenceState = command } }
            return
        }
        // A session started here replays the saved status itself, so the
        // command is remembered only after it's sent: otherwise a status that
        // starts the session goes out twice.
        try ensureStarted().send(command)
        if command.hasPrefix("state ") { lock.withLock { presenceState = command } }
    }

    func listen(_ listener: @escaping @Sendable ([String: Any]) -> Void) {
        lock.withLock { presenceListener = listener }
    }

    func end() async {
        let ending = lock.withLock { () -> SpawnedProcess? in
            retired = true
            return process
        }
        await ending?.end()
    }

    // MARK: - Process

    private func activeRefusal() -> [String: Any]? {
        lock.withLock {
            guard let refusal, refusal.until > Date() else { return nil }
            return refusal.reply
        }
    }

    private func ensureStarted() throws -> SpawnedProcess {
        try lock.withLock {
            if let process, process.isRunning { return process }
            guard !retired else { throw CloudSyncClientError.helper("BEER's Steam session was signed out.") }
            generation += 1
            let started = try spawn(generation: generation)
            process = started
            if let presenceState { started.send(presenceState) }
            return started
        }
    }

    /// Called with `lock` held.
    private func spawn(generation: Int) throws -> SpawnedProcess {
        let tokenFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("gn-session-\(UUID().uuidString).tok")
        try refreshToken.write(to: tokenFile, atomically: true, encoding: .utf8)
        // The helper reads its token once, before it logs on, so its first
        // byte of output proves the file is no longer needed.
        let tokenCleanup = OnceBox { try? FileManager.default.removeItem(at: tokenFile) }

        var args = ["session", "--account", account, "--token-file", tokenFile.path]
        if !isTest {
            args += ["--device-file", AppPaths.steamDeviceIDURL.path]
            let restarted = Self.registryLock.withLock { () -> Bool in
                defer { Self.hasLoggedThisRun = true }
                return Self.hasLoggedThisRun
            }
            if restarted { PlaySessionLog.append("=== session restarted ===") } else { PlaySessionLog.start() }
        }
        let leftover = LineBox()
        let fatal = ResultSlot()
        do {
            let started = try ShellRunner.spawn(
                executable: binary.path,
                arguments: args,
                environment: ["DOTNET_CLI_TELEMETRY_OPTOUT": "1", "DOTNET_NOLOGO": "1"],
                outputHandler: { [weak self] chunk in
                    tokenCleanup.run()
                    for line in leftover.feed(chunk) { self?.route(line, fatal: fatal) }
                },
                onExit: { [weak self] in
                    tokenCleanup.run()
                    for line in leftover.flush() { self?.route(line, fatal: fatal) }
                    self?.processEnded(generation: generation, fatal: fatal.value)
                }
            )
            if !isTest { PlaySessionRegistry.record(pid: started.processIdentifier) }
            return started
        } catch {
            tokenCleanup.run()
            throw error
        }
    }

    private func route(_ line: String, fatal: ResultSlot) {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            if !isTest { PlaySessionLog.append(line) }
            return
        }
        guard let id = (obj["id"] as? NSNumber)?.intValue else {
            // Session-level: status and play reports, or the logon failing.
            if !isTest { PlaySessionLog.append(line) }
            if obj["error"] != nil { fatal.value = obj }
            lock.withLock { presenceListener }?(obj)
            return
        }
        if obj["done"] != nil {
            lock.withLock { pending.removeValue(forKey: id) }?.finished.resume()
        } else {
            lock.withLock { pending[id] }?.onObject(obj)
        }
    }

    /// The session ended: every request still waiting gets the reason, and a
    /// refused logon is remembered so the next request doesn't retry it.
    private func processEnded(generation ended: Int, fatal: [String: Any]?) {
        let (waiting, process) = lock.withLock { () -> ([Request], SpawnedProcess?) in
            let waiting = pending.filter { $0.value.generation == ended }
            waiting.keys.forEach { pending.removeValue(forKey: $0) }
            if let fatal, (fatal["auth_failed"] as? Bool) == true {
                // Only a new sign-in, which makes a new host, can fix this.
                refusal = (fatal, .distantFuture)
            } else if let fatal, (fatal["rate_limited"] as? Bool) == true {
                refusal = (fatal, Date().addingTimeInterval(120))
            }
            guard generation == ended else { return (Array(waiting.values), nil) }
            defer { self.process = nil }
            return (Array(waiting.values), self.process)
        }
        if !isTest, let process { PlaySessionLog.append("helper \(process.exitDescription)") }
        let reason = fatal ?? ["error": "BEER's Steam session ended unexpectedly."]
        for request in waiting {
            request.onObject(reason)
            request.finished.resume()
        }
    }

    // MARK: - Protocol

    /// `["enumerate", "--appid", "440"]` → `{"id":1,"cmd":"enumerate","args":{"appid":"440"}}`.
    static func requestLine(_ args: [String], id: Int) throws -> String {
        guard let cmd = args.first, !cmd.hasPrefix("--") else {
            throw CloudSyncClientError.badOutput("no command to send to the Steam session")
        }
        var named: [String: String] = [:]
        var i = 1
        while i < args.count {
            guard args[i].hasPrefix("--") else { i += 1; continue }
            let key = String(args[i].dropFirst(2))
            if i + 1 < args.count, !args[i + 1].hasPrefix("--") {
                named[key] = args[i + 1]
                i += 2
            } else {
                named[key] = "true"
                i += 1
            }
        }
        let request: [String: Any] = ["id": id, "cmd": cmd, "args": named]
        let data = try JSONSerialization.data(withJSONObject: request, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }
}

/// The last session-level error the helper printed.
private final class ResultSlot: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String: Any]?
    var value: [String: Any]? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
