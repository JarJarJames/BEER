import Foundation

// DepotDownloaderController invokes the native DepotDownloader binary.
//
// Every install uses the same SteamClient refresh token that signed the user
// into BEER. CloudSyncClient writes a short-lived DepotDownloader-compatible
// account cache, this controller runs:
//   ./DepotDownloader -app <id> -dir <path> -os windows -osarch 64
//                     -username <name> -remember-password -loginid <random>
// and the cache is removed immediately afterward. The token never appears in
// argv and DepotDownloader never owns a second authentication session.
//
// Output streamed from DepotDownloader is parsed for:
//   • " Pre-allocating ", " Validating ", percentage lines       → status phases
//   • "  ##.##% ..." or "Downloaded XXX / YYY MB"                → progress
//   • "Total downloaded: ..." or "Depot ... downloaded"          → completion

@MainActor
final class DepotDownloaderController: ObservableObject {
    @Published var lastError: String?
    @Published private(set) var activeDownloads = 0

    var isBusy: Bool { activeDownloads > 0 }

    /// Downloads Pause can stop right now, by Downloads entry: DepotDownloader
    /// is running for them. Not during bottle setup or emulator patching.
    @Published private(set) var pausableIDs: Set<Int> = []
    private var stoppers: [Int: ProcessStopper] = [:]

    private let cloudClient = CloudSyncClient()
    private var authSessionDepth = 0
    private var authCacheURL: URL?

    /// Where the in-flight credential cache's path is recorded, so a launch
    /// after a crash can delete it. Tests point this at a temporary folder.
    var stateURL = AppPaths.applicationSupport.appendingPathComponent("depotdownloader-state.json")

    func load() {
        // If the app was terminated during a download, remove the transient
        // DepotDownloader credential cache recorded before the process began.
        // No record is the normal case: nothing was left behind.
        guard let data = try? Data(contentsOf: stateURL) else { return }
        if let payload = attempt("decode the DepotDownloader auth record", log: Log.install, {
               try JSONDecoder().decode(StoredState.self, from: data)
           }),
           let path = payload.authCachePath,
           !removeAuthCache(at: URL(fileURLWithPath: path)) {
            // Keep the record so the next launch tries the delete again.
            return
        }
        rememberAuthCache(nil)
    }

    /// Delete DepotDownloader's credential cache, which holds the refresh
    /// token. Returns false if it is still on disk.
    private func removeAuthCache(at url: URL) -> Bool {
        do {
            try FileManager.default.removeItemIfPresent(at: url)
            return true
        } catch {
            Log.install.fault("Couldn't delete DepotDownloader's credential cache; the next launch will retry: \(error.localizedDescription)")
            return false
        }
    }

    private func rememberAuthCache(_ url: URL?) {
        if let url {
            // Without this record, a crash mid-download leaves the credential
            // cache somewhere the next launch can't find it.
            attempt("record the DepotDownloader auth cache path", log: Log.install) {
                try JSONEncoder().encode(StoredState(authCachePath: url.path)).write(to: stateURL, options: .atomic)
            }
        } else {
            attempt("remove the DepotDownloader auth record", log: Log.install) {
                try FileManager.default.removeItemIfPresent(at: stateURL)
            }
        }
    }

    private struct StoredState: Codable {
        let authCachePath: String?

        // Older builds stored a DepotDownloader-specific account name here.
        // Keep decoding tolerant so load() can discard that obsolete state.
        private enum CodingKeys: String, CodingKey { case authCachePath }
    }

    // MARK: - Game install

    /// `installDir` is the game's folder, inside its bottle or on a drive.
    func installGame(
        appID: Int,
        gameName: String,
        installDir: URL,
        auth: SteamCloudAccount,
        depots: [Int]? = nil,
        events: @escaping @MainActor (DepotDownloaderEvent) -> Void
    ) async throws -> InstallResult {
        // Say the drive is missing, rather than fail on a path that's gone.
        try GameFolders.requireDrive(for: installDir)
        try FileManager.default.createDirectory(at: installDir, withIntermediateDirectories: true)

        try await download(appID: appID, downloadID: appID, into: installDir, auth: auth, depots: depots, events: events)

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
    ///
    /// A DLC whose files are among the game's own depots is fetched with the
    /// game's `appID` and just those `depots`; `downloadID` is still the DLC's
    /// own, so Pause stops this run and not the game's.
    func installDLC(
        appID: Int,
        downloadID: Int,
        installDir: URL,
        auth: SteamCloudAccount,
        depots: [Int]? = nil,
        events: @escaping @MainActor (DepotDownloaderEvent) -> Void
    ) async throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: installDir.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw DepotDownloaderError.installDirMissing(installDir.path)
        }
        try await download(appID: appID, downloadID: downloadID, into: installDir, auth: auth, depots: depots, events: events)
    }

    // MARK: - Shared download

    /// Run DepotDownloader for one app into `installDir`, bridging BEER's
    /// Steam token in for the lifetime of the process.
    private func download(
        appID: Int,
        downloadID: Int,
        into installDir: URL,
        auth: SteamCloudAccount,
        depots: [Int]?,
        events: @escaping @MainActor (DepotDownloaderEvent) -> Void
    ) async throws {
        guard FileManager.default.isExecutableFile(atPath: AppPaths.depotDownloaderExecutableURL.path) else {
            throw DepotDownloaderError.binaryMissing
        }

        try await withAuthSession(auth: auth) {
            try await self.runDownload(appID: appID, downloadID: downloadID, into: installDir, auth: auth, depots: depots, events: events)
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
                let removed = authCacheURL.map(removeAuthCache(at:)) ?? true
                authCacheURL = nil
                // On failure keep the on-disk record so the next launch retries.
                if removed { rememberAuthCache(nil) }
            }
        }
        return try await body()
    }

    private func runDownload(
        appID: Int,
        downloadID: Int,
        into installDir: URL,
        auth: SteamCloudAccount,
        depots: [Int]?,
        events: @escaping @MainActor (DepotDownloaderEvent) -> Void
    ) async throws {
        // Refcounted, not a Bool: a DLC install can overlap a base-game install,
        // and whichever finished first used to clear the flag for both.
        activeDownloads += 1
        defer { activeDownloads -= 1 }

        let stopper = ProcessStopper()
        stoppers[downloadID] = stopper
        pausableIDs.insert(downloadID)
        defer {
            stoppers[downloadID] = nil
            pausableIDs.remove(downloadID)
        }

        let args = Self.downloadArguments(
            appID: appID, installDir: installDir,
            accountName: auth.accountName, loginID: Self.newLoginID(), depots: depots)

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
        let status = Box(DepotDownloaderStatus())
        let authFailure = Box<String?>(nil)
        let sessionExpired = Box<Bool>(false)
        let notOwned = Box<String?>(nil)

        let exit = try await runDepotDownloader(args: args, stopper: stopper) { line in
            // Skip per-chunk progress lines; everything else (logon, licence and
            // ownership messages) is what a failed run needs.
            if parseProgressFraction(line) == nil {
                try? logHandle?.write(contentsOf: Data((line + "\n").utf8))
            }
            tail.value.append(line)
            if tail.value.count > 60 { tail.value.removeFirst() }
            Task { @MainActor in events(.log(line)) }

            // Status phases
            if let phase = status.value.update(with: line) {
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

        // Whatever it printed on the way out, it stopped because it was told to.
        if stopper.wasStopped {
            throw DepotDownloaderError.paused
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

    // MARK: - Pause

    /// Stop the DepotDownloader run for Downloads entry `id`. The install
    /// that started it then ends with `DepotDownloaderError.paused`, once the
    /// process has exited; what came down stays for Resume.
    func pause(_ id: Int, in downloads: DownloadsStore) {
        guard let stopper = stoppers[id] else { return }
        downloads.markPausing(appID: id)
        stopper.stop()
    }

    // MARK: - Arguments

    /// `depots`, when given, is exactly what to fetch. DepotDownloader then
    /// skips its own OS and language filter, so pass the filtered list the
    /// helper's `installsize` reports.
    static func downloadArguments(
        appID: Int, installDir: URL, accountName: String, loginID: UInt32, depots: [Int]? = nil
    ) -> [String] {
        let depotArguments = depots.map { ["-depot"] + $0.map(String.init) } ?? []
        return [
            "-app", String(appID),
            "-dir", installDir.path,
            "-os", "windows",
            "-osarch", "64",
            "-username", accountName,
            "-remember-password",
            "-loginid", String(loginID)
        ] + depotArguments
    }

    /// Steam ends any session on the account that logs on with a LoginID
    /// already in use. Without `-loginid`, DepotDownloader falls back to an ID
    /// made from this Mac's LAN address — the same one the real Steam client
    /// sends — so every install signed the user's Steam client out.
    ///
    /// Random per run, not fixed: a DLC install can overlap a base-game install,
    /// and two runs sharing an ID would knock each other off. The ceiling keeps
    /// it below the CloudSync helper's fixed presence ID (0x42454552).
    static func newLoginID() -> UInt32 {
        UInt32.random(in: 1...0x3FFF_FFFF)
    }

    // MARK: - Process invocation

    private func runDepotDownloader(
        args: [String],
        stopper: ProcessStopper,
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
                stopper: stopper,
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
}
