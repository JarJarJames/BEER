import Foundation

// DepotDownloaderController invokes the native DepotDownloader binary.
//
// First-time use:
//   ./DepotDownloader -app <id> -dir <path> -os windows -osarch 64 -qr
//   → DepotDownloader prints an ASCII-art QR. The user scans it with the
//     Steam Mobile App and approves. Once approved, DepotDownloader prints
//     "Logging in as 'AccountName'..." and we capture the account name.
//     The refresh token is cached in DepotDownloader's account.config.
//
// Subsequent installs:
//   ./DepotDownloader -app <id> -dir <path> -os windows -osarch 64
//                     -username <name> -remember-password
//   → No QR; the cached refresh token is reused. Silent re-login.
//
// Output streamed from DepotDownloader is parsed for:
//   • "Use the Steam Mobile App to sign in with this QR code:"  → QR block start
//   • blank line                                                 → QR block end
//   • "The QR code has changed:"                                 → reset + restart capture
//   • "Logging in as 'X'"                                        → capture account name
//   • " Pre-allocating ", " Downloaded ", " Validating "         → status phases
//   • "  ##.##% ..." or "Downloaded XXX / YYY MB"                → progress
//   • "Total downloaded: ..." or "Depot ... downloaded"          → completion

private final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

enum DepotDownloaderEvent {
    case status(String)
    case qrCode(asciiArt: String)
    case loggedIn(account: String)
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
    @Published private(set) var loggedInAccount: String?
    @Published private(set) var isBusy = false
    @Published var lastError: String?

    private var stateURL: URL {
        AppPaths.applicationSupport.appendingPathComponent("depotdownloader-state.json")
    }

    func load() {
        guard let data = try? Data(contentsOf: stateURL),
              let payload = try? JSONDecoder().decode(StoredState.self, from: data) else {
            return
        }
        loggedInAccount = payload.account
    }

    func signOut() {
        loggedInAccount = nil
        persist()
        // Also blow away DepotDownloader's cached tokens — its file lives in
        // .NET IsolatedStorage, so we can't surgically clear one account, but
        // wiping the whole DepotDownloader/ tree is fine.
        try? FileManager.default.removeItem(at: AppPaths.depotDownloaderDirectory.appendingPathComponent("account.config"))
    }

    private func persist() {
        let payload = StoredState(account: loggedInAccount)
        if let data = try? JSONEncoder().encode(payload) {
            try? data.write(to: stateURL, options: .atomic)
        }
    }

    private struct StoredState: Codable { let account: String? }

    // MARK: - Game install

    struct InstallResult {
        let installDirectory: URL
        let launchExecutableHostPath: URL
    }

    /// Public entry point. If the first attempt fails because Steam invalidated
    /// our cached refresh token (DepotDownloader can't auth non-interactively),
    /// we wipe the cached account and retry once with `-qr` so the user can
    /// re-approve from their Steam mobile app.
    func installGame(
        appID: Int,
        gameName: String,
        bottle: Bottle,
        events: @escaping @MainActor (DepotDownloaderEvent) -> Void
    ) async throws -> InstallResult {
        do {
            return try await runInstallAttempt(appID: appID, gameName: gameName, bottle: bottle, events: events)
        } catch DepotDownloaderError.sessionExpired {
            events(.status("Steam session expired — re-authenticating via QR…"))
            loggedInAccount = nil
            persist()
            return try await runInstallAttempt(appID: appID, gameName: gameName, bottle: bottle, events: events)
        }
    }

    private func runInstallAttempt(
        appID: Int,
        gameName: String,
        bottle: Bottle,
        events: @escaping @MainActor (DepotDownloaderEvent) -> Void
    ) async throws -> InstallResult {
        guard FileManager.default.isExecutableFile(atPath: AppPaths.depotDownloaderExecutableURL.path) else {
            throw DepotDownloaderError.binaryMissing
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

        // Build the argv. Use cached account if we have one; else trigger QR flow.
        var args: [String] = [
            "-app", String(appID),
            "-dir", installDir.path,
            "-os", "windows",
            "-osarch", "64"
        ]
        if let account = loggedInAccount {
            args.append(contentsOf: ["-username", account, "-remember-password"])
        } else {
            args.append("-qr")
        }

        await MainActor.run { events(.status("Connecting to Steam…")) }

        // Mutable scratch for the stdout parser thread.
        let qrParser = Box(QRBlockParser())
        let tail = Box<[String]>([])
        let lastEmittedProgress = Box<Double>(-1)
        let authFailure = Box<String?>(nil)
        let sessionExpired = Box<Bool>(false)
        let installedSuccessfully = Box<Bool>(false)
        let capturedAccount = Box<String?>(nil)

        let exit = try await runDepotDownloader(args: args) { line in
            // QR block capture first — if this is a QR-data line we want to
            // suppress it from the log tail entirely so it doesn't show up in
            // the on-screen "DepotDownloader output" disclosure as block art.
            let qrResult = qrParser.value.consume(line: line)
            if !qrResult.isQRDataLine {
                tail.value.append(line)
                if tail.value.count > 60 { tail.value.removeFirst() }
                Task { @MainActor in events(.log(line)) }
            }
            if let qr = qrResult.completedMatrix {
                Task { @MainActor in events(.qrCode(asciiArt: qr)) }
            }

            // "Logging in as 'X'..." or "Next time you can login with -username X -remember-password"
            if let account = parseLoggingInAs(line) ?? parseNextTimeLogin(line) {
                capturedAccount.value = account
                Task { @MainActor in events(.loggedIn(account: account)) }
            }

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

        // Persist the captured account name from the QR run.
        if let acc = capturedAccount.value, loggedInAccount != acc {
            loggedInAccount = acc
            persist()
        }

        // Expired-session takes priority — the public installGame wrapper
        // catches this specifically and retries via QR.
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

private func parseLoggingInAs(_ line: String) -> String? {
    // "Logging in as 'username'..."
    if let match = line.firstMatch(of: /Logging in as ['"]([A-Za-z0-9._\-]+)['"]/) {
        return String(match.output.1)
    }
    return nil
}

private func parseNextTimeLogin(_ line: String) -> String? {
    // "Success! Next time you can login with -username username -remember-password instead of -qr."
    if let match = line.firstMatch(of: /-username\s+([A-Za-z0-9._\-]+)\s+-remember-password/) {
        return String(match.output.1)
    }
    return nil
}

private func parseStatusPhrase(_ line: String) -> String? {
    let lower = line.lowercased()
    if lower.contains("got app info") || lower.contains("got app info!") { return "Got app info" }
    if lower.contains("got cdn auth token") { return "Authenticated with CDN" }
    if lower.contains("pre-allocating") { return "Pre-allocating disk space…" }
    if lower.contains("validating") { return "Validating files…" }
    if lower.contains("downloading depot") { return "Downloading…" }
    if lower.contains("logging in with qr code") { return "Waiting for Steam Mobile App scan…" }
    if lower.contains("the qr code has changed") { return "QR code refreshed — rescan" }
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

// MARK: - QR block parser
//
// DepotDownloader prints the QR like:
//
//   Use the Steam Mobile App to sign in with this QR code:
//   ████████████████  ██  ██████  ████████
//   ██  ██████  ████      ██  ██  ██  ████
//   ...
//   ████████████████████████████████████████
//   <no terminator until Steam refreshes the challenge or download begins>
//
// QRCoder emits one row per module row with one █ per module column (size=1),
// so a complete QR is a SQUARE matrix: lines.count == lines[0].count. We
// detect that and emit immediately — no need to wait for a blank line.

private struct QRBlockParser {
    struct Result {
        /// True iff this line is part of a QR ASCII block — caller should
        /// suppress it from the user-visible log tail.
        var isQRDataLine: Bool = false
        /// Set on the line that completes the QR matrix. Contains the
        /// full block (newline-joined) ready to render.
        var completedMatrix: String? = nil
    }

    private var capturing = false
    private var lines: [String] = []
    private var emitted = false

    mutating func consume(line: String) -> Result {
        // Outside a QR block: watch for the section header line.
        if !capturing {
            if line.lowercased().contains("steam mobile app") &&
               line.lowercased().contains("qr code") {
                capturing = true
                lines = []
                emitted = false
            }
            // The header itself is fine to log.
            return Result()
        }

        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // A real log message (starts with a letter or digit, e.g. "Got CDN
        // auth token") ends the QR block. Emit final state if we never did
        // and let this line through to the log as normal.
        if let first = trimmed.first, first.isLetter || first.isNumber {
            let final: String? = (!emitted && !lines.isEmpty) ? lines.joined(separator: "\n") : nil
            capturing = false
            lines = []
            emitted = false
            return Result(completedMatrix: final)
        }

        // Blank line inside the block — absorb (don't reset). DepotDownloader
        // sometimes prints a blank line before/after the QR for spacing.
        if trimmed.isEmpty {
            return Result(isQRDataLine: true)
        }

        // Anything else inside capture mode is QR data. Don't be picky about
        // which block character it is — QRCoder defaults to "██" / "  " but
        // user terminals can re-encode block characters and we want to
        // survive that.
        lines.append(line)

        // Emit when the matrix is complete. QRCoder's default ASCII rendering
        // uses TWO characters per dark module (██) and TWO spaces per light
        // module, so a complete square QR has rows == cols/2. We also accept
        // rows == cols in case a future build switches to single-char modules.
        if !emitted, let firstLine = lines.first {
            let cols = firstLine.count
            if cols >= 10 && (lines.count == cols / 2 || lines.count == cols) {
                emitted = true
                return Result(isQRDataLine: true, completedMatrix: lines.joined(separator: "\n"))
            }
        }
        return Result(isQRDataLine: true)
    }
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
