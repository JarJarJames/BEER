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

private final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

enum DepotDownloaderEvent {
    case status(String)
    case progress(Double)
    case log(String)
    case downloadComplete
}

enum DepotDownloaderError: LocalizedError {
    case binaryMissing
    case spawnFailed(String)
    case authenticationFailed(String)
    case sessionExpired
    case downloadFailed(Int32, String)
    case launchExeNotFound

    var errorDescription: String? {
        switch self {
        case .binaryMissing:
            return "DepotDownloader is not installed. Open the app's onboarding step to install it."
        case .spawnFailed(let detail):
            return "Could not start DepotDownloader: \(detail)"
        case .authenticationFailed(let detail):
            return "Steam sign-in failed: \(detail)"
        case .sessionExpired:
            return "Steam session expired."
        case .downloadFailed(let code, let tail):
            return "DepotDownloader exited with code \(code). Last output:\n\(tail)"
        case .launchExeNotFound:
            return "Download completed but we couldn't find a Windows .exe in the install directory."
        }
    }
}

@MainActor
final class DepotDownloaderController: ObservableObject {
    @Published private(set) var isBusy = false
    @Published var lastError: String?

    private let cloudClient = CloudSyncClient()

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

    struct InstallResult {
        let installDirectory: URL
        let launchExecutableHostPath: URL
    }

    func installGame(
        appID: Int,
        gameName: String,
        bottle: Bottle,
        auth: SteamCloudAccount,
        events: @escaping @MainActor (DepotDownloaderEvent) -> Void
    ) async throws -> InstallResult {
        guard FileManager.default.isExecutableFile(atPath: AppPaths.depotDownloaderExecutableURL.path) else {
            throw DepotDownloaderError.binaryMissing
        }

        let authCache: URL
        do {
            authCache = try await cloudClient.prepareDepotDownloaderAuth(
                executable: AppPaths.depotDownloaderExecutableURL,
                account: auth.accountName,
                refreshToken: auth.refreshToken
            )
        } catch {
            throw DepotDownloaderError.authenticationFailed(error.localizedDescription)
        }
        rememberAuthCache(authCache)
        defer {
            try? FileManager.default.removeItem(at: authCache)
            rememberAuthCache(nil)
        }

        let bottlePrefix = AppPaths.prefixURL(for: bottle)
        let safe = sanitize(gameName)
        let installDir = bottlePrefix
            .appendingPathComponent("drive_c", isDirectory: true)
            .appendingPathComponent("Games", isDirectory: true)
            .appendingPathComponent(safe, isDirectory: true)
        try FileManager.default.createDirectory(at: installDir, withIntermediateDirectories: true)

        isBusy = true
        defer { isBusy = false }

        let args: [String] = [
            "-app", String(appID),
            "-dir", installDir.path,
            "-os", "windows",
            "-osarch", "64",
            "-username", auth.accountName,
            "-remember-password"
        ]

        await MainActor.run { events(.status("Connecting to Steam…")) }

        // Mutable scratch for the stdout parser thread.
        let tail = Box<[String]>([])
        let lastEmittedProgress = Box<Double>(-1)
        let authFailure = Box<String?>(nil)
        let sessionExpired = Box<Bool>(false)
        let installedSuccessfully = Box<Bool>(false)

        let exit = try await runDepotDownloader(args: args) { line in
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

            // Completion sentinels
            if line.contains("Total downloaded:") || line.contains("Depot download complete") || line.contains("downloaded successfully") {
                installedSuccessfully.value = true
                Task { @MainActor in events(.downloadComplete) }
            }
        }

        if sessionExpired.value {
            throw DepotDownloaderError.sessionExpired
        }

        if let detail = authFailure.value {
            throw DepotDownloaderError.authenticationFailed(detail)
        }

        guard exit == 0 else {
            throw DepotDownloaderError.downloadFailed(exit, tail.value.suffix(15).joined(separator: "\n"))
        }

        guard let exe = LaunchExecutableFinder.find(in: installDir, gameName: gameName) else {
            throw DepotDownloaderError.launchExeNotFound
        }
        return InstallResult(installDirectory: installDir, launchExecutableHostPath: exe)
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

// MARK: - Parser helpers (all nonisolated & pure)

private func scrub(_ line: String) -> String {
    var out = line.replacingOccurrences(of: "\r", with: "")
    if let re = try? NSRegularExpression(pattern: "\\u{1B}\\[[0-9;]*[a-zA-Z]") {
        let range = NSRange(out.startIndex..., in: out)
        out = re.stringByReplacingMatches(in: out, range: range, withTemplate: "")
    }
    return out
}

private func parseStatusPhrase(_ line: String) -> String? {
    let lower = line.lowercased()
    if lower.contains("got app info") || lower.contains("got app info!") { return "Got app info" }
    if lower.contains("got cdn auth token") { return "Authenticated with CDN" }
    if lower.contains("pre-allocating") { return "Pre-allocating disk space…" }
    if lower.contains("validating") { return "Validating files…" }
    if lower.contains("downloading depot") { return "Downloading…" }
    return nil
}

private func parseProgressFraction(_ line: String) -> Double? {
    // DepotDownloader prints lines like " 12.34% C:\\... " during download.
    if let m = line.firstMatch(of: /^\s*([0-9]+(?:\.[0-9]+)?)%/) {
        if let v = Double(m.output.1) { return max(0, min(1, v / 100)) }
    }
    // Older builds: "Downloaded XYZ / TOTAL MB"
    if let m = line.firstMatch(of: /Downloaded ([0-9.]+)\s*\/\s*([0-9.]+)\s*MB/) {
        if let d = Double(m.output.1), let t = Double(m.output.2), t > 0 {
            return max(0, min(1, d / t))
        }
    }
    return nil
}

private func parseAuthFailure(_ line: String) -> String? {
    let lower = line.lowercased()
    if lower.contains("invalid password") { return "Invalid password" }
    if lower.contains("rate limit") { return "Steam is rate-limiting sign-in attempts. Wait a few minutes." }
    if lower.contains("unable to logon") {
        return String(line.trimmingCharacters(in: .whitespaces))
    }
    if lower.contains("guard data was rejected") { return "Steam Guard data was rejected" }
    return nil
}

// MARK: - Launch executable heuristic

enum LaunchExecutableFinder {
    /// Walk the install dir, find Windows `.exe` files, and pick the most
    /// likely main game executable. Heuristic:
    ///   1. Drop common installers / redists / crash handlers.
    ///   2. Prefer files whose basename contains the game name (letters-only compare).
    ///   3. Otherwise return the largest remaining .exe.
    static func find(in installDir: URL, gameName: String) -> URL? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: installDir, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) else {
            return nil
        }

        let skip = [
            "unins", "redist", "vcredist", "vc_redist", "directx", "dxsetup", "dotnet", "dotnetfx",
            "crashreport", "crashpad", "crashhandler", "uninstall", "uninstaller",
            "_setup", "setup", "installer", "report", "updater", "patch", "easyanticheat",
            "battleye", "anticheat"
        ]

        var candidates: [(url: URL, size: Int64, name: String)] = []
        for case let url as URL in enumerator {
            guard url.pathExtension.lowercased() == "exe" else { continue }
            let lower = url.lastPathComponent.lowercased()
            if skip.contains(where: { lower.contains($0) }) { continue }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            candidates.append((url, size, url.lastPathComponent))
        }

        let normalizedGame = gameName.lowercased().filter(\.isLetter)
        if normalizedGame.count > 2,
           let match = candidates.first(where: { $0.name.lowercased().filter(\.isLetter).contains(normalizedGame) }) {
            return match.url
        }
        return candidates.max(by: { $0.size < $1.size })?.url
    }
}

private extension String {
    func ifEmpty(default value: String) -> String { isEmpty ? value : self }
}
