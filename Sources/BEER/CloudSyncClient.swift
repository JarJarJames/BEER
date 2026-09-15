import Foundation

// Swift wrapper around the native `CloudSync` helper (Tools/CloudSync, built on
// SteamKit2). The helper speaks the real Steam *client* cloud protocol — the
// same one the Steam app uses — so it can both download AND upload cloud saves,
// authenticating with the user's own refresh token (no Publisher key needed).
//
// The helper prints one JSON object per line on stdout; human/log noise goes to
// stderr. ShellRunner merges both streams, so we parse line-by-line and act on
// whichever lines decode to a recognized JSON shape — anything that isn't JSON
// (the helper's "connected; logging on…" notes) is ignored.

struct CloudRemoteFile: Equatable {
    /// Steam's own cloud key for the file, e.g. "%WinSavedGames%/kingdomcome/…".
    let filename: String
    let size: Int
    let timestamp: Date
    let sha: String
}

enum CloudSyncClientError: LocalizedError {
    case helperMissing
    case helper(String)
    case authExpired
    case rateLimited
    case badOutput(String)

    var errorDescription: String? {
        switch self {
        case .helperMissing:
            return "The CloudSync helper isn't installed. Build it with Tools/CloudSync (see scripts/build_cloudsync.sh)."
        case .helper(let msg):
            return "Steam Cloud error: \(msg)"
        case .authExpired:
            return "Your Steam sign-in expired or was revoked. Reconnect to keep syncing — your local saves are untouched."
        case .rateLimited:
            return "Steam is temporarily rate-limiting sign-ins for your account (too many recent logins). Wait a few minutes, then try again — don't re-sign-in, that only extends the cooldown. Your saves are safe."
        case .badOutput(let detail):
            return "Couldn't understand the CloudSync helper's output: \(detail.prefix(200)). The helper may be out of date; rebuild BEER so the app and helper versions match."
        }
    }
}

struct CloudSyncClient {

    // MARK: - Locating the helper binary

    /// Find the helper executable. Checked in order:
    ///   1. Next to / near the running app executable. The helper bundled with
    ///      this app build must win over a potentially stale standalone copy.
    ///   2. The dev build output, relative to the current working directory
    ///      (so `swift run` from the repo root just works).
    ///   3. App Support install dir (where scripts/build_cloudsync.sh puts it).
    static func locateBinary() -> URL? {
        let fm = FileManager.default
        var candidates: [URL] = []

        let exeDir = URL(fileURLWithPath: CommandLine.arguments.first ?? "")
            .deletingLastPathComponent()
        candidates.append(exeDir.appendingPathComponent("CloudSync"))
        candidates.append(exeDir.appendingPathComponent("CloudSync/CloudSync"))

        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
        for sub in ["Tools/CloudSync/bin/Release/net9.0/CloudSync",
                    "Tools/CloudSync/bin/Release/net8.0/CloudSync"] {
            candidates.append(cwd.appendingPathComponent(sub))
        }
        candidates.append(AppPaths.cloudSyncExecutableURL)

        return candidates.first { fm.isExecutableFile(atPath: $0.path) }
    }

    private func binaryOrThrow() throws -> URL {
        guard let url = Self.locateBinary() else { throw CloudSyncClientError.helperMissing }
        return url
    }

    // MARK: - Auth

    struct AuthResult { let account: String; let refreshToken: String }

    /// Make BEER's existing SteamClient token available to DepotDownloader for
    /// one process invocation. The returned cache URL contains a credential and
    /// must be removed by the caller immediately after DepotDownloader exits.
    func prepareDepotDownloaderAuth(
        executable: URL,
        account: String,
        refreshToken: String
    ) async throws -> URL {
        let obj = try await runOnce(
            args: ["prepare-depot-auth", "--depot-executable", executable.resolvingSymlinksInPath().path],
            account: account,
            refreshToken: refreshToken
        )
        guard obj["prepared"] as? Bool == true,
              let path = obj["config_path"] as? String
        else {
            throw CloudSyncClientError.badOutput("DepotDownloader auth bridge did not return a cache path")
        }
        return URL(fileURLWithPath: path)
    }

    /// Run the QR sign-in. `onChallenge` is called with each challenge URL
    /// (Steam rotates it every ~30s, so the UI should re-render the QR each
    /// time). Returns the account name + a SteamClient-audience refresh token.
    func authenticate(onChallenge: @escaping @Sendable (String) -> Void) async throws -> AuthResult {
        let binary = try binaryOrThrow()
        let captured = ResultBox()

        _ = try await runStreaming(binary: binary, args: ["auth"]) { obj in
            if let url = obj["challenge_url"] as? String {
                onChallenge(url)
            } else if obj["authenticated"] != nil,
                      let account = obj["account"] as? String,
                      let token = obj["refresh_token"] as? String {
                captured.set(AuthResult(account: account, refreshToken: token))
            } else if let err = obj["error"] as? String {
                captured.setError(err)
            }
        }

        if let err = captured.error { throw CloudSyncClientError.helper(err) }
        guard let result = captured.auth else {
            throw CloudSyncClientError.badOutput("auth finished without a token")
        }
        return result
    }

    // MARK: - Library

    struct OwnedGameInfo {
        let appID: Int
        let name: String
        let iconURL: String?
        let lastPlayed: Date?
        /// Total minutes Steam has recorded for this app, across every device.
        /// BEER contributes to this itself via `beginPlaySession` — see
        /// `PlaySession` below.
        let playtimeMinutes: Int?
    }

    /// Fetch the signed-in account's owned games via the authenticated client
    /// session (IPlayerService.GetOwnedGames over the Steam network) — no Web
    /// API key required.
    func ownedGames(steamID64: String, account: String, refreshToken: String) async throws -> [OwnedGameInfo] {
        let raw = try await runOnceArray(
            "games", args: ["ownedgames", "--steamid", steamID64],
            account: account, refreshToken: refreshToken
        )
        return raw.compactMap { g in
            guard let appid = (g["appid"] as? NSNumber)?.intValue else { return nil }
            let name = (g["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "App \(appid)"
            let icon = (g["img_icon_url"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let rt = (g["rtime_last_played"] as? NSNumber)?.doubleValue ?? 0
            let minutes = (g["playtime_forever"] as? NSNumber)?.intValue ?? 0
            return OwnedGameInfo(
                appID: appid,
                name: name,
                iconURL: icon.map { "https://media.steampowered.com/steamcommunity/public/images/apps/\(appid)/\($0).jpg" },
                lastPlayed: rt > 0 ? Date(timeIntervalSince1970: rt) : nil,
                playtimeMinutes: minutes > 0 ? minutes : nil
            )
        }
    }

    // MARK: - Play session

    /// Announce `appID` to Steam as running, and keep announcing until the
    /// returned session is ended.
    ///
    /// Steam credits play time to whichever logged-on client session claims to
    /// be playing — the real Steam client holds no special privilege — so this
    /// is what puts hours from a Wine-launched game onto the same counter as
    /// hours played on a PC or a handheld.
    ///
    /// The helper holds one logon for the whole play session, so call this
    /// *between* the pre-launch pull and the post-play push, never alongside
    /// either: concurrent logons on one account fight over which session owns
    /// the in-game presence.
    func beginPlaySession(
        appID: Int, steamID64: String, account: String, refreshToken: String
    ) async throws -> SteamPlaySession {
        let binary = try binaryOrThrow()
        let tokenFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("gn-play-\(UUID().uuidString).tok")
        try refreshToken.write(to: tokenFile, atomically: true, encoding: .utf8)

        let state = ResultBox()
        let leftover = LineBox()
        PlaySessionLog.start(appID: appID)
        let process: SpawnedProcess
        do {
            process = try ShellRunner.spawn(
                executable: binary.path,
                arguments: [
                    "playing", "--appid", "\(appID)", "--steamid", steamID64,
                    "--account", account, "--token-file", tokenFile.path,
                ],
                environment: ["DOTNET_CLI_TELEMETRY_OPTOUT": "1", "DOTNET_NOLOGO": "1"],
                outputHandler: { chunk in
                    PlaySessionLog.append(chunk)
                    for line in leftover.feed(chunk) {
                        guard let data = line.data(using: .utf8),
                              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                        else { continue }
                        if let err = obj["error"] as? String {
                            state.setError(err,
                                           authFailed: (obj["auth_failed"] as? Bool) ?? false,
                                           rateLimited: (obj["rate_limited"] as? Bool) ?? false)
                        } else {
                            state.setDict(obj)
                        }
                    }
                }
            )
        } catch {
            try? FileManager.default.removeItem(at: tokenFile)
            throw error
        }
        PlaySessionRegistry.record(pid: process.processIdentifier)

        // Wait for the logon to land — but never hold the game's launch
        // hostage to it. Past the deadline we let the game start anyway and
        // leave the helper to keep trying; late is better than not at all.
        let deadline = Date().addingTimeInterval(30)
        while state.dict == nil, state.error == nil, process.isRunning, Date() < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        // The helper reads this file once, before it logs on, so by now it is
        // consumed. It has to go either way: unlike a normal command's token
        // file, nothing else deletes it for the life of a play session.
        try? FileManager.default.removeItem(at: tokenFile)

        let session = SteamPlaySession(appID: appID, process: process, state: state)
        if let err = state.error {
            await session.end()
            if state.rateLimited { throw CloudSyncClientError.rateLimited }
            if state.authFailed { throw CloudSyncClientError.authExpired }
            throw CloudSyncClientError.helper(err)
        }
        if state.dict == nil, !process.isRunning {
            await session.end()
            throw CloudSyncClientError.helper("the play-session helper exited before it signed in")
        }
        return session
    }

    // MARK: - DLC

    struct DLCInfo: Identifiable, Equatable {
        var id: Int { appID }
        let appID: Int
        let name: String
        let owned: Bool
        /// False for licence-only DLC (season passes, artbooks) that carry no
        /// downloadable depot — there is nothing to install for those, only an
        /// entitlement to declare to the Steam emulator.
        let hasDepots: Bool
    }

    /// Every DLC Steam lists for `appID`, each flagged with whether this
    /// account owns it. Steam has no owned-DLC endpoint, so the helper derives
    /// ownership from the account's package licences (see `Dlc` in Program.cs).
    func dlc(appID: Int, account: String, refreshToken: String) async throws -> [DLCInfo] {
        let raw = try await runOnceArray(
            "dlc", args: ["dlc", "--appid", String(appID)],
            account: account, refreshToken: refreshToken
        )
        return raw.compactMap { d in
            guard let appid = (d["appid"] as? NSNumber)?.intValue else { return nil }
            return DLCInfo(
                appID: appid,
                name: (d["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "DLC \(appid)",
                owned: d["owned"] as? Bool ?? false,
                hasDepots: d["has_depots"] as? Bool ?? false
            )
        }
    }

    // MARK: - Cloud operations

    func enumerate(appID: Int, account: String, refreshToken: String) async throws -> [CloudRemoteFile] {
        let raw = try await runOnceArray(
            "files", args: ["enumerate", "--appid", String(appID)],
            account: account, refreshToken: refreshToken
        )
        return raw.compactMap { f in
            guard let filename = f["filename"] as? String else { return nil }
            let size = (f["size"] as? NSNumber)?.intValue ?? 0
            let ts = (f["timestamp"] as? NSNumber)?.doubleValue ?? 0
            let sha = f["sha"] as? String ?? ""
            return CloudRemoteFile(
                filename: filename,
                size: size,
                timestamp: Date(timeIntervalSince1970: ts),
                sha: sha
            )
        }
    }

    struct DownloadJob { let filename: String; let out: URL }
    struct UploadJob { let filename: String; let local: URL; let mtime: Date }
    struct BatchOp { let op: String; let filename: String; let error: String? }

    /// Run many downloads + uploads inside a SINGLE logged-on helper session.
    /// One Steam logon for the whole sync — spawning a process per file gets the
    /// account CM-throttled after ~100 logons. `onProgress` fires per completed
    /// op with (completed, total).
    func batch(
        appID: Int,
        downloads: [DownloadJob],
        uploads: [UploadJob],
        account: String,
        refreshToken: String,
        onProgress: @escaping @Sendable (Int, Int) -> Void
    ) async throws -> [BatchOp] {
        guard !downloads.isEmpty || !uploads.isEmpty else { return [] }
        let binary = try binaryOrThrow()

        let jobs: [String: Any] = [
            "appid": appID,
            "downloads": downloads.map { ["filename": $0.filename, "out": $0.out.path] },
            "uploads": uploads.map { ["filename": $0.filename, "in": $0.local.path,
                                      "mtime": Int($0.mtime.timeIntervalSince1970)] }
        ]
        let tmp = FileManager.default.temporaryDirectory
        let jobsFile = tmp.appendingPathComponent("gn-cloud-jobs-\(UUID().uuidString).json")
        let tokenFile = tmp.appendingPathComponent("gn-cloud-\(UUID().uuidString).tok")
        try JSONSerialization.data(withJSONObject: jobs).write(to: jobsFile, options: .atomic)
        try refreshToken.write(to: tokenFile, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: jobsFile)
            try? FileManager.default.removeItem(at: tokenFile)
        }

        let total = downloads.count + uploads.count
        let collector = BatchCollector()
        _ = try await runStreaming(binary: binary, args: [
            "batch", "--appid", String(appID), "--jobs", jobsFile.path,
            "--account", account, "--token-file", tokenFile.path
        ]) { obj in
            if obj["summary"] != nil { return }
            if let opName = obj["op"] as? String, let filename = obj["filename"] as? String {
                let err = obj["error"] as? String
                collector.add(BatchOp(op: opName, filename: filename, error: err))
                onProgress(collector.count, total)
            } else if let err = obj["error"] as? String {
                // Top-level failure (e.g. the single logon failed before any op).
                collector.setFatal(err,
                                   authFailed: (obj["auth_failed"] as? Bool) ?? false,
                                   rateLimited: (obj["rate_limited"] as? Bool) ?? false)
            }
        }

        if collector.rateLimited { throw CloudSyncClientError.rateLimited }
        if collector.authFailed { throw CloudSyncClientError.authExpired }
        if let fatal = collector.fatal, collector.ops.isEmpty { throw CloudSyncClientError.helper(fatal) }
        return collector.ops
    }

    // MARK: - Process plumbing

    /// Run a one-shot command, returning the last JSON object the helper
    /// printed. Writes the refresh token to a temp file so it never appears in
    /// argv / `ps` output.
    /// Run a command whose payload is a JSON array under `key`, and hand back
    /// its rows. Owns the cast and the "no <key> array" error so each command
    /// keeps only its own row mapping.
    private func runOnceArray(
        _ key: String, args: [String], account: String, refreshToken: String
    ) async throws -> [[String: Any]] {
        let obj = try await runOnce(args: args, account: account, refreshToken: refreshToken)
        guard let raw = obj[key] as? [[String: Any]] else {
            throw CloudSyncClientError.badOutput("no \(key) array")
        }
        return raw
    }

    private func runOnce(args: [String], account: String, refreshToken: String) async throws -> [String: Any] {
        let binary = try binaryOrThrow()
        let tokenFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("gn-cloud-\(UUID().uuidString).tok")
        try refreshToken.write(to: tokenFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tokenFile) }

        let fullArgs = args + ["--account", account, "--token-file", tokenFile.path]
        let last = ResultBox()
        _ = try await runStreaming(binary: binary, args: fullArgs) { obj in
            if let err = obj["error"] as? String {
                last.setError(err,
                              authFailed: (obj["auth_failed"] as? Bool) ?? false,
                              rateLimited: (obj["rate_limited"] as? Bool) ?? false)
            } else {
                last.setDict(obj)
            }
        }
        if last.rateLimited { throw CloudSyncClientError.rateLimited }
        if last.authFailed { throw CloudSyncClientError.authExpired }
        if let err = last.error { throw CloudSyncClientError.helper(err) }
        guard let obj = last.dict else {
            throw CloudSyncClientError.badOutput("no JSON result")
        }
        return obj
    }

    /// Stream the helper, decoding each stdout line as JSON and forwarding any
    /// object to `onObject`. Returns the process exit code.
    private func runStreaming(
        binary: URL,
        args: [String],
        onObject: @escaping @Sendable ([String: Any]) -> Void
    ) async throws -> Int32 {
        let leftover = LineBox()
        let result = try await ShellRunner.run(
            executable: binary.path,
            arguments: args,
            environment: ["DOTNET_CLI_TELEMETRY_OPTOUT": "1", "DOTNET_NOLOGO": "1"],
            outputHandler: { chunk in
                for line in leftover.feed(chunk) {
                    guard let data = line.data(using: .utf8),
                          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                    else { continue }
                    onObject(obj)
                }
            }
        )
        for line in leftover.flush() {
            if let data = line.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                onObject(obj)
            }
        }
        return result.exitCode
    }
}

// MARK: - Small thread-safe boxes (output handler runs off-main)

private final class LineBox: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = ""

    func feed(_ chunk: String) -> [String] {
        lock.lock(); defer { lock.unlock() }
        buffer += chunk
        var lines = buffer.components(separatedBy: "\n")
        if buffer.hasSuffix("\n") {
            buffer = ""
        } else {
            buffer = lines.removeLast()
        }
        return lines.filter { !$0.isEmpty }
    }

    func flush() -> [String] {
        lock.lock(); defer { lock.unlock() }
        let rest = buffer
        buffer = ""
        return rest.isEmpty ? [] : [rest]
    }
}

private final class BatchCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var _ops: [CloudSyncClient.BatchOp] = []
    private var _fatal: String?
    private var _authFailed = false
    private var _rateLimited = false

    func add(_ op: CloudSyncClient.BatchOp) { lock.lock(); _ops.append(op); lock.unlock() }
    func setFatal(_ msg: String, authFailed: Bool, rateLimited: Bool) {
        lock.lock(); _fatal = msg; _authFailed = authFailed; _rateLimited = rateLimited; lock.unlock()
    }

    var ops: [CloudSyncClient.BatchOp] { lock.lock(); defer { lock.unlock() }; return _ops }
    var count: Int { lock.lock(); defer { lock.unlock() }; return _ops.count }
    var fatal: String? { lock.lock(); defer { lock.unlock() }; return _fatal }
    var authFailed: Bool { lock.lock(); defer { lock.unlock() }; return _authFailed }
    var rateLimited: Bool { lock.lock(); defer { lock.unlock() }; return _rateLimited }
}

private final class ResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _auth: CloudSyncClient.AuthResult?
    private var _dict: [String: Any]?
    private var _error: String?
    private var _authFailed = false

    private var _rateLimited = false

    func set(_ a: CloudSyncClient.AuthResult) { lock.lock(); _auth = a; lock.unlock() }
    func setDict(_ d: [String: Any]) { lock.lock(); _dict = d; lock.unlock() }
    func setError(_ e: String, authFailed: Bool = false, rateLimited: Bool = false) {
        lock.lock(); _error = e; _authFailed = authFailed; _rateLimited = rateLimited; lock.unlock()
    }

    var auth: CloudSyncClient.AuthResult? { lock.lock(); defer { lock.unlock() }; return _auth }
    var dict: [String: Any]? { lock.lock(); defer { lock.unlock() }; return _dict }
    var error: String? { lock.lock(); defer { lock.unlock() }; return _error }
    var authFailed: Bool { lock.lock(); defer { lock.unlock() }; return _authFailed }
    var rateLimited: Bool { lock.lock(); defer { lock.unlock() }; return _rateLimited }
}

// MARK: - Play session handle

/// A live "playing this game" announcement held open with Steam for as long as
/// the game runs. Always `end()` it — dropping it leaves the helper announcing
/// until BEER itself exits.
final class SteamPlaySession: Sendable {
    let appID: Int
    private let process: SpawnedProcess
    private let state: ResultBox

    fileprivate init(appID: Int, process: SpawnedProcess, state: ResultBox) {
        self.appID = appID
        self.process = process
        self.state = state
    }

    /// Set when the helper reported a problem — most likely the Steam
    /// connection dropping mid-game, after which the hours stop accruing.
    var failureMessage: String? { state.error }

    /// The app's new total, re-read by the helper on the logon it already held
    /// once the session ended — so refreshing the number costs no extra logon.
    /// Nil if the session failed, or if Steam had not yet credited the hours.
    /// Only meaningful after `end()`.
    var finalPlaytimeMinutes: Int? {
        (state.dict?["playtime_forever"] as? NSNumber)?.intValue
    }

    /// Retract the announcement. Closing stdin is the helper's cue; it needs a
    /// moment after that to tell Steam it has stopped, so give it time to exit
    /// on its own rather than killing it outright.
    func end() async {
        await process.end()
        PlaySessionRegistry.clear()
    }
}

/// Remembers the PID of a live play-session helper so a BEER that died without
/// unwinding can clean it up next launch.
///
/// Belt-and-braces: the helper already exits on its own when BEER's end of its
/// stdin pipe closes, which covers even a force quit. This catches the
/// remainder — a helper wedged on a dead socket, say.
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
    /// "in-game" status behind.
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

/// Everything the play-session helper prints, captured to a file.
///
/// A play session outlives the call that starts it, so its output has nowhere
/// else to go — and without this, a presence or play-time problem leaves no
/// trace at all to debug from.
enum PlaySessionLog {
    private static let lock = NSLock()

    static func start(appID: Int) {
        lock.withLock {
            try? AppPaths.ensureBaseDirectories()
            let header = "=== play session — appid \(appID) — \(Date()) ===\n"
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
