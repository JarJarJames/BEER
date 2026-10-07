import Foundation

// DepotDownloaderController invokes the native DepotDownloader binary.
//
// Every install uses the same SteamClient refresh token that signed the user
// into BEER. CloudSyncClient writes a short-lived DepotDownloader-compatible
// account cache, this controller runs:
//   ./DepotDownloader -app <id> -dir <path> -os windows -osarch 64
//                     -username <name> -remember-password
// and the cache is removed immediately afterward. The token never appears in
// argv and DepotDownloader never owns a second authentication session.
//
// Output streamed from DepotDownloader is parsed for:
//   • " Pre-allocating ", " Downloaded ", " Validating "         → status phases
//   • "  ##.##% ..." or "Downloaded XXX / YYY MB"                → progress
//   • "Total downloaded: ..." or "Depot ... downloaded"          → completion

@MainActor
final class DepotDownloaderController: ObservableObject {
    @Published var lastError: String?
    @Published private(set) var activeDownloads = 0

    var isBusy: Bool { activeDownloads > 0 }

    private let cloudClient = CloudSyncClient()
    private var authSessionDepth = 0
    private var authCacheURL: URL?

    private var stateURL: URL {
        AppPaths.applicationSupport.appendingPathComponent("depotdownloader-state.json")
    }

    func load() {
        // If the app was terminated during a download, remove the transient
        // DepotDownloader credential cache recorded before the process began.
        if let data = try? Data(contentsOf: stateURL),
           let payload = try? JSONDecoder().decode(StoredState.self, from: data),
           let path = payload.authCachePath {
            try? FileManager.default.removeItem(atPath: path)
        }
        try? FileManager.default.removeItem(at: stateURL)
    }

    private func rememberAuthCache(_ url: URL?) {
        if let url,
           let data = try? JSONEncoder().encode(StoredState(authCachePath: url.path)) {
            try? data.write(to: stateURL, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: stateURL)
        }
    }

    private struct StoredState: Codable {
        let authCachePath: String?

        // Older builds stored a DepotDownloader-specific account name here.
        // Keep decoding tolerant so load() can discard that obsolete state.
        private enum CodingKeys: String, CodingKey { case authCachePath }
    }

    // MARK: - Game install

    func installGame(
        appID: Int,
        gameName: String,
        bottle: Bottle,
        auth: SteamCloudAccount,
        events: @escaping @MainActor (DepotDownloaderEvent) -> Void
    ) async throws -> InstallResult {
        let bottlePrefix = AppPaths.prefixURL(for: bottle)
        let safe = sanitize(gameName)
        let installDir = bottlePrefix
            .appendingPathComponent("drive_c", isDirectory: true)
            .appendingPathComponent("Games", isDirectory: true)
            .appendingPathComponent(safe, isDirectory: true)
        try FileManager.default.createDirectory(at: installDir, withIntermediateDirectories: true)

        try await download(appID: appID, into: installDir, auth: auth, events: events)

        guard let exe = LaunchExecutableFinder.find(in: installDir, gameName: gameName) else {
            throw DepotDownloaderError.launchExeNotFound
        }
        return InstallResult(installDirectory: installDir, launchExecutableHostPath: exe)
    }

    // MARK: - DLC install

    /// Pull one DLC's depots into a game that is already installed.
    ///
    /// Safe to point at a populated install dir. DepotDownloader only deletes
    /// files that were in a depot's *own* previous manifest and have since been
    /// dropped from it; a DLC depot downloaded for the first time has no
    /// previous manifest, so nothing existing is touched. That is what lets us
    /// add DLC without re-downloading the base game.
    func installDLC(
        appID: Int,
        installDir: URL,
        auth: SteamCloudAccount,
        events: @escaping @MainActor (DepotDownloaderEvent) -> Void
    ) async throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: installDir.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw DepotDownloaderError.installDirMissing(installDir.path)
        }
        try await download(appID: appID, into: installDir, auth: auth, events: events)
    }

    // MARK: - Shared download

    /// Run DepotDownloader for one app into `installDir`, bridging BEER's
    /// Steam token in for the lifetime of the process.
    private func download(
        appID: Int,
        into installDir: URL,
        auth: SteamCloudAccount,
        events: @escaping @MainActor (DepotDownloaderEvent) -> Void
    ) async throws {
        guard FileManager.default.isExecutableFile(atPath: AppPaths.depotDownloaderExecutableURL.path) else {
            throw DepotDownloaderError.binaryMissing
        }

        try await withAuthSession(auth: auth) {
            try await self.runDownload(appID: appID, into: installDir, auth: auth, events: events)
        }
    }

    /// Hold a DepotDownloader credential cache for the duration of `body`.
    ///
    /// The cache lives at a fixed path derived from the DepotDownloader binary,
    /// so every concurrent run shares one file: it is minted on the first entry
    /// and removed only when the last one leaves. Nesting is what makes a batch
    /// cheap — `installAll` wraps the whole loop, so a six-DLC run costs one
    /// Steam logon to mint the cache instead of six.
    func withAuthSession<T>(auth: SteamCloudAccount, _ body: () async throws -> T) async throws -> T {
        if authSessionDepth == 0 {
            do {
                let cache = try await cloudClient.prepareDepotDownloaderAuth(
                    executable: AppPaths.depotDownloaderExecutableURL,
                    account: auth.accountName,
                    refreshToken: auth.refreshToken
                )
                authCacheURL = cache
                rememberAuthCache(cache)
            } catch {
                throw DepotDownloaderError.authenticationFailed(error.localizedDescription)
            }
        }
        authSessionDepth += 1
        defer {
            authSessionDepth -= 1
            if authSessionDepth == 0 {
                if let cache = authCacheURL {
                    try? FileManager.default.removeItem(at: cache)
                }
                authCacheURL = nil
                rememberAuthCache(nil)
            }
        }
        return try await body()
    }

    private func runDownload(
        appID: Int,
        into installDir: URL,
        auth: SteamCloudAccount,
        events: @escaping @MainActor (DepotDownloaderEvent) -> Void
    ) async throws {
        // Refcounted, not a Bool: a DLC install can overlap a base-game install,
        // and whichever finished first used to clear the flag for both.
        activeDownloads += 1
        defer { activeDownloads -= 1 }

        let args: [String] = [
            "-app", String(appID),
            "-dir", installDir.path,
            "-os", "windows",
            "-osarch", "64",
            "-username", auth.accountName,
            "-remember-password"
        ]

        await MainActor.run { events(.status("Connecting to Steam…")) }

        let logURL = AppPaths.depotDownloaderLogURL(forAppID: appID)
        try? FileManager.default.createDirectory(
            at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? "args: \(args.joined(separator: " "))\n".write(to: logURL, atomically: true, encoding: .utf8)
        let logHandle = try? FileHandle(forWritingTo: logURL)
        try? logHandle?.seekToEnd()
        defer { try? logHandle?.close() }

        // Mutable scratch for the stdout parser thread.
        let tail = Box<[String]>([])
        let lastEmittedProgress = Box<Double>(-1)
        let authFailure = Box<String?>(nil)
        let sessionExpired = Box<Bool>(false)
        let notOwned = Box<String?>(nil)

        let exit = try await runDepotDownloader(args: args) { line in
            // Skip per-chunk progress lines; everything else (logon, licence and
            // ownership messages) is what a failed run needs.
            if parseProgressFraction(line) == nil {
                try? logHandle?.write(contentsOf: Data((line + "\n").utf8))
            }
            tail.value.append(line)
            if tail.value.count > 60 { tail.value.removeFirst() }
            Task { @MainActor in events(.log(line)) }

            // Status phases
            if let phase = parseStatusPhrase(line) {
                Task { @MainActor in events(.status(phase)) }
            }

            // Progress
            if let fraction = parseProgressFraction(line),
               abs(fraction - lastEmittedProgress.value) > 0.001 {
                lastEmittedProgress.value = fraction
                Task { @MainActor in events(.progress(fraction)) }
            }

            // Session-expired detection — DepotDownloader prints these when
            // its cached refresh token has been invalidated and it falls
            // back to the interactive password prompt that we can't satisfy.
            let l = line.lowercased()
            if l.contains("logon requires a username and password or access token") ||
               l.contains("enter account password for") {
                sessionExpired.value = true
            }

            // Auth failures
            if let detail = parseAuthFailure(line) {
                authFailure.value = detail
            }

            // Ownership. DepotDownloader reports this as a plain exception on
            // stdout, so catch it here to explain it rather than surfacing a
            // bare non-zero exit code.
            if let name = parseNotOwned(line) {
                notOwned.value = name
            }

            // Completion sentinels
            if line.contains("Total downloaded:") || line.contains("Depot download complete") || line.contains("downloaded successfully") {
                Task { @MainActor in events(.downloadComplete) }
            }
        }

        if sessionExpired.value {
            throw DepotDownloaderError.sessionExpired
        }

        if let detail = authFailure.value {
            throw DepotDownloaderError.authenticationFailed(detail)
        }

        if let name = notOwned.value {
            throw DepotDownloaderError.appNotOwned(name)
        }

        guard exit == 0 else {
            throw DepotDownloaderError.downloadFailed(exit, tail.value.suffix(15).joined(separator: "\n"))
        }
    }

    // MARK: - Process invocation

    private func runDepotDownloader(
        args: [String],
        lineHandler: @escaping @Sendable (String) -> Void
    ) async throws -> Int32 {
        let exe = AppPaths.depotDownloaderExecutableURL.path

        // Line-buffering layer over ShellRunner's chunk callback.
        let leftover = Box("")
        let result: ProcessResult
        do {
            result = try await ShellRunner.run(
                executable: exe,
                arguments: args,
                environment: [
                    "DOTNET_CLI_TELEMETRY_OPTOUT": "1",
                    "DOTNET_NOLOGO": "1"
                ],
                currentDirectory: AppPaths.depotDownloaderDirectory,
                outputHandler: { chunk in
                    let combined = leftover.value + chunk
                    var lines = combined.components(separatedBy: "\n")
                    if !combined.hasSuffix("\n"), let last = lines.last {
                        leftover.value = last
                        lines.removeLast()
                    } else {
                        leftover.value = ""
                    }
                    for line in lines where !line.isEmpty {
                        lineHandler(scrub(line))
                    }
                }
            )
        } catch {
            throw DepotDownloaderError.spawnFailed(error.localizedDescription)
        }
        if !leftover.value.isEmpty {
            lineHandler(scrub(leftover.value))
        }
        return result.exitCode
    }

    private func sanitize(_ s: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_."))
        let mapped = s.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        return String(mapped).trimmingCharacters(in: CharacterSet(charactersIn: "_ ")).ifEmpty(default: "Game")
    }
}
